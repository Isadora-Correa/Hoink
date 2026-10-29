import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/api_client.dart';
import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../shell/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';
import '../cards/cards_screen.dart' show cardsProvider, showPurchaseForm;
import '../contacts/contacts_screen.dart' show contactsProvider;
import 'transactions_screen.dart' show settleDialog;

/// Cadastro e edição de lançamentos (protótipo "Novo Lançamento" / "Cadastrar Nova Despesa").
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.entityId,
    this.transactionId,
    this.initialType,
    this.initialRecurring = false,
    this.initialContactId,
  });
  final String? entityId;
  final String? transactionId;
  final String? initialType;
  final bool initialRecurring;
  final String? initialContactId;

  bool get isEdit => transactionId != null;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _counterparty = TextEditingController();
  final _notes = TextEditingController();
  final _tags = TextEditingController();
  final _settledPartial = TextEditingController();
  final _intervalCount = TextEditingController(text: '1');
  final _maxOccurrences = TextEditingController(text: '12');

  // Recorrência (somente na criação)
  late bool _recurring = widget.initialRecurring;
  String _frequency = 'MONTHLY';
  String _intervalUnit = 'MONTH';
  String _amountKind = 'FIXED';
  String _endMode = 'NONE'; // NONE | DATE | COUNT
  DateTime? _endDate;

  late String _type = switch (widget.initialType) {
    'INCOME' => 'INCOME',
    'TRANSFER' => 'TRANSFER',
    _ => 'EXPENSE',
  };
  String? _entityId;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  late String? _contactId = widget.initialContactId;
  String _status = 'SETTLED';
  String _classification = 'PRO_LABORE';
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  bool _busy = false;
  bool _loading = false;
  Txn? _original;
  Map<String, List<String>> _fieldErrors = const {};
  // Mesma chave em reenvios do mesmo formulário evita lançamentos duplicados.
  final _idempotencyKey = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _entityId = widget.entityId;
    if (widget.isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await ref.read(repositoryProvider).transaction(widget.entityId!, widget.transactionId!);
      setState(() {
        _original = t;
        _type = t.type;
        _amount.text = formatAmount(t.amountCents);
        _description.text = t.description;
        _counterparty.text = t.counterparty ?? '';
        _notes.text = t.notes ?? '';
        _tags.text = t.tags.join(', ');
        _accountId = t.account.id;
        _categoryId = t.category?.id;
        _contactId = t.contactId;
        _status = t.status;
        _settledPartial.text = t.status == 'PARTIAL' ? formatAmount(t.settledAmountCents) : '';
        _date = parseIso(t.competenceDate);
        _dueDate = t.dueDate == null ? null : parseIso(t.dueDate!);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _amount,
      _description,
      _counterparty,
      _notes,
      _tags,
      _settledPartial,
      _intervalCount,
      _maxOccurrences,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _resolveEntityId(List<FinancialEntity> entities) {
    if (_entityId != null) return _entityId;
    final current = ref.read(currentEntityProvider);
    return current?.id ?? entities.where((e) => e.isPersonal).firstOrNull?.id;
  }

  void _close() => context.canPop() ? context.pop() : context.go('/lancamentos');

  /// Compras no cartão têm fluxo próprio: escolhe-se o cartão e o número de parcelas.
  Future<void> _cardPurchase() async {
    final entityId = _resolveEntityId(ref.read(entitiesProvider).value ?? const []);
    if (entityId == null) return;
    final cards = await ref.read(cardsProvider(entityId).future);
    if (!mounted) return;
    if (cards.isEmpty) {
      showError(context, 'Cadastre um cartão de crédito primeiro');
      context.go('/cartoes');
      return;
    }
    final card = cards.length == 1
        ? cards.first
        : await showDialog<CreditCard>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Qual cartão?'),
              children: [
                for (final c in cards)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, c),
                    child: Text('${c.name} • disponível ${formatBRL(c.availableCents)}'),
                  ),
              ],
            ),
          );
    if (card == null || !mounted) return;
    await showPurchaseForm(context, ref, card);
    if (mounted) _close();
  }

  /// Ao editar uma ocorrência: só ela, desta em diante ou a série inteira.
  Future<String?> _askScope() => showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Aplicar alteração em…'),
      children: [
        for (final (value, title, subtitle) in [
          ('THIS', 'Somente esta ocorrência', 'As demais continuam iguais.'),
          ('FROM', 'Esta e as próximas', 'As anteriores ficam como estão.'),
          ('SERIES', 'Toda a série', 'Pagamentos já realizados não mudam.'),
        ])
          SimpleDialogOption(
            key: Key('scope-$value'),
            onPressed: () => Navigator.pop(ctx, value),
            child: ListTile(title: Text(title), subtitle: Text(subtitle), contentPadding: EdgeInsets.zero),
          ),
      ],
    ),
  );

  Future<void> _submit(String entityId) async {
    setState(() => _fieldErrors = const {});
    if (!_form.currentState!.validate()) return;
    final cents = parseBRLToCents(_amount.text)!;
    final repo = ref.read(repositoryProvider);
    setState(() => _busy = true);
    try {
      if (_type == 'TRANSFER') {
        await repo.createTransfer(
          {
            'fromAccountId': _accountId,
            'toAccountId': _toAccountId,
            'amountCents': cents,
            'date': isoDate(_date),
            'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
            'classification': _isCrossEntity() ? _classification : 'INTERNAL',
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          }..removeWhere((_, v) => v == null),
          idempotencyKey: _idempotencyKey,
        );
      } else {
        final tags = _tags.text
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        final body = <String, Object?>{
          'description': _description.text.trim(),
          'amountCents': cents,
          'accountId': _accountId,
          'categoryId': _categoryId,
          'status': _status,
          if (_status == 'PARTIAL') 'settledAmountCents': parseBRLToCents(_settledPartial.text),
          'competenceDate': isoDate(_date),
          'dueDate': _dueDate == null ? null : isoDate(_dueDate!),
          'counterparty': _counterparty.text.trim().isEmpty ? null : _counterparty.text.trim(),
          'contactId': _contactId,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'tags': tags,
        };
        if (widget.isEdit && (_original?.isRecurring ?? false)) {
          final scope = await _askScope();
          if (scope == null) return;
          if (scope == 'THIS') {
            await repo.updateTransaction(entityId, widget.transactionId!, body);
          } else {
            await repo.updateRecurring(
              entityId,
              _original!.recurring!.ruleId,
              scope: scope,
              fromDate: scope == 'FROM' ? _original!.recurring!.occurrenceDate : null,
              changes: {
                'description': body['description'],
                'amountCents': body['amountCents'],
                'accountId': body['accountId'],
                'categoryId': body['categoryId'],
                'counterparty': body['counterparty'],
                'contactId': body['contactId'],
                'notes': body['notes'],
              },
            );
          }
        } else if (widget.isEdit) {
          // Ao reabrir um lançamento já liquidado, a data de liquidação é mantida pelo backend.
          await repo.updateTransaction(entityId, widget.transactionId!, body);
        } else if (_recurring) {
          final rule = await repo.createRecurring(entityId, {
            'type': _type,
            'description': body['description'],
            'amountCents': cents,
            'amountKind': _amountKind,
            'accountId': _accountId,
            'categoryId': _categoryId,
            'counterparty': body['counterparty'],
            'contactId': _contactId,
            'notes': body['notes'],
            'frequency': _frequency,
            if (_frequency == 'CUSTOM') 'intervalCount': int.tryParse(_intervalCount.text) ?? 1,
            if (_frequency == 'CUSTOM') 'intervalUnit': _intervalUnit,
            'startDate': isoDate(_date),
            if (_endMode == 'DATE' && _endDate != null) 'endDate': isoDate(_endDate!),
            if (_endMode == 'COUNT') 'maxOccurrences': int.tryParse(_maxOccurrences.text) ?? 12,
          });
          // "Pago" na criação liquida a primeira ocorrência, se ela já venceu.
          final first = rule.occurrences.firstOrNull;
          if (_status == 'SETTLED' && first != null && first.competenceDate.compareTo(isoDate(DateTime.now())) <= 0) {
            await repo.settle(entityId, first.id, first.competenceDate);
          }
        } else {
          await repo.createTransaction(entityId, {...body, 'type': _type}, idempotencyKey: _idempotencyKey);
        }
      }
      ref.read(dataVersionProvider.notifier).bump();
      if (!mounted) return;
      showSuccess(
        context,
        widget.isEdit
            ? 'Lançamento atualizado'
            : (_type == 'TRANSFER'
                  ? 'Transferência registrada'
                  : (_recurring ? 'Recorrência criada — próximas ocorrências geradas' : 'Lançamento salvo')),
      );
      _close();
    } on ApiException catch (e) {
      setState(() => _fieldErrors = e.fieldErrors);
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String entityId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text('O saldo da conta será recalculado. A exclusão fica registrada no histórico de auditoria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HoinkColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteTransaction(entityId, widget.transactionId!);
      ref.read(dataVersionProvider.notifier).bump();
      if (mounted) {
        showSuccess(context, 'Lançamento excluído');
        _close();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  List<Account> _allAccounts() {
    final entities = ref.read(entitiesProvider).value ?? const [];
    return [for (final e in entities) ...(ref.read(accountsProvider(e.id)).value ?? const <Account>[])]
        .where((a) => !a.archived)
        .toList();
  }

  bool _isCrossEntity() {
    final all = _allAccounts();
    final from = all.where((a) => a.id == _accountId).firstOrNull;
    final to = all.where((a) => a.id == _toAccountId).firstOrNull;
    return from != null && to != null && from.entityId != to.entityId;
  }

  String? _err(String field) => _fieldErrors[field]?.first;

  Widget _recurrenceOptions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Frequência', style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in frequencyLabels.entries)
                ChoiceChip(
                  key: Key('freq-${e.key}'),
                  label: Text(e.value),
                  selected: _frequency == e.key,
                  showCheckmark: false,
                  selectedColor: HoinkColors.pine,
                  labelStyle: HoinkText.labelMd.copyWith(
                    color: _frequency == e.key ? HoinkColors.ivory : HoinkColors.onSurface,
                  ),
                  onSelected: (_) => setState(() => _frequency = e.key),
                ),
            ],
          ),
          if (_frequency == 'CUSTOM') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('A cada'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    controller: _intervalCount,
                    keyboardType: TextInputType.number,
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Inválido' : null,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _intervalUnit,
                  items: [
                    for (final e in intervalUnitLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _intervalUnit = v!),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text('Valor', style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final e in amountKindLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {_amountKind},
            onSelectionChanged: (v) => setState(() => _amountKind = v.first),
          ),
          if (_amountKind != 'FIXED')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ao pagar cada ocorrência você informa o valor real (ex.: a conta de energia do mês).',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
              ),
            ),
          const SizedBox(height: 12),
          Text('Termina', style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (value, label) in [('NONE', 'Nunca'), ('DATE', 'Em uma data'), ('COUNT', 'Após N vezes')])
                ChoiceChip(
                  label: Text(label),
                  selected: _endMode == value,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _endMode = value),
                ),
              if (_endMode == 'DATE')
                OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime(_date.year + 1, _date.month, _date.day),
                      firstDate: _date,
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _endDate = d);
                  },
                  child: Text(_endDate == null ? 'Escolher data' : formatBrDate(isoDate(_endDate!))),
                ),
              if (_endMode == 'COUNT')
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _maxOccurrences,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(suffixText: 'vezes'),
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Inválido' : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'As ocorrências são criadas como previstas e entram na sua previsão de caixa. '
            'Para mudar o valor de um mês só, edite aquela ocorrência.',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entities = ref.watch(entitiesProvider).value ?? const [];
    for (final e in entities) {
      ref.watch(accountsProvider(e.id));
    }
    final entityId = _resolveEntityId(entities);
    if (_loading || entityId == null) return const Center(child: CircularProgressIndicator());

    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final entity = entities.firstWhere((e) => e.id == entityId);
    final accounts = (ref.watch(accountsProvider(entityId)).value ?? const <Account>[])
        .where((a) => !a.archived || a.id == _accountId)
        .toList();
    final categories = ref.watch(categoriesProvider(entityId)).value ?? const <Category>[];
    final kind = _type == 'INCOME' ? 'INCOME' : 'EXPENSE';
    final visibleCats = categories.where((c) => c.kind == kind).toList();
    final isTransfer = _type == 'TRANSFER';
    final allAccounts = _allAccounts();

    // Pessoal/PJ: ao lado do título no desktop; numa linha própria no celular.
    final showPicker = !widget.isEdit && !isTransfer && entities.length > 1;
    final entityPicker = SegmentedButton<String>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: HoinkColors.pine,
        selectedForegroundColor: HoinkColors.ivory,
      ),
      segments: [
        for (final e in entities)
          ButtonSegment(
            value: e.id,
            label: Text(e.isPersonal ? 'Pessoal' : 'PJ'),
            icon: Icon(e.isPersonal ? Symbols.person : Symbols.business_center, size: 16),
          ),
      ],
      selected: {entityId},
      onSelectionChanged: (s) => setState(() {
        _entityId = s.first;
        _accountId = null;
        _categoryId = null;
      }),
    );

    final header = Row(
      children: [
        IconButton(
          style: IconButton.styleFrom(
            backgroundColor: HoinkColors.surfaceLowest,
            foregroundColor: HoinkColors.pine,
            fixedSize: const Size(44, 44),
          ),
          onPressed: _close,
          icon: const Icon(Symbols.arrow_back),
          tooltip: 'Voltar',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FLUXO DE CAIXA • ${monthLabel(isoMonth(_date)).toUpperCase()}',
                style: HoinkText.labelSm.copyWith(color: HoinkColors.surfaceTint),
              ),
              Text(
                widget.isEdit ? 'Editar lançamento' : (isTransfer ? 'Nova transferência' : 'Novo lançamento'),
                style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(color: HoinkColors.primary),
              ),
            ],
          ),
        ),
        if (showPicker && wide) entityPicker,
      ],
    );

    final typeTabs = widget.isEdit
        ? Pill(transactionTypeLabels[_type] ?? _type, background: HoinkColors.pine, foreground: HoinkColors.ivory)
        : Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: HoinkColors.surfaceLowest,
              borderRadius: BorderRadius.circular(HoinkRadius.lg),
              boxShadow: HoinkShadows.level1,
            ),
            child: Row(
              children: [
                for (final (value, label, icon) in [
                  ('EXPENSE', 'Despesa', Symbols.north_east),
                  ('INCOME', 'Receita', Symbols.south_west),
                  ('TRANSFER', 'Transferência', Symbols.sync_alt),
                ])
                  Expanded(
                    child: _TypeTab(
                      label: label,
                      icon: icon,
                      active: _type == value,
                      onTap: () => setState(() {
                        _type = value;
                        _categoryId = null;
                        if (value == 'TRANSFER') _status = 'SETTLED';
                      }),
                    ),
                  ),
                Expanded(
                  child: Tooltip(
                    message: 'Cofrinhos chegam na Fase 3',
                    child: _TypeTab(
                      label: wide ? 'Aporte Cofrinho' : 'Cofrinho',
                      icon: Symbols.savings,
                      active: false,
                      onTap: null,
                    ),
                  ),
                ),
              ],
            ),
          );

    final amountCard = HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'VALOR DO LANÇAMENTO',
                  style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer, letterSpacing: 1.2),
                ),
              ),
              Pill(
                isTransfer
                    ? 'Não é receita nem despesa'
                    : (_status == 'SETTLED' ? (_type == 'INCOME' ? 'Recebido' : 'Débito imediato') : 'Em aberto'),
                dot: HoinkColors.pine,
                background: HoinkColors.mint,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('amount'),
            controller: _amount,
            autofocus: !widget.isEdit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: HoinkText.displayHero.copyWith(
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            cursorColor: HoinkColors.mint,
            validator: (v) {
              final c = parseBRLToCents(v ?? '');
              if (c == null || c <= 0) return 'Informe um valor maior que zero';
              return null;
            },
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixText: 'R\$ ',
              prefixStyle: HoinkText.headlineLg.copyWith(color: HoinkColors.primaryFixedDim),
              hintText: '0,00',
              hintStyle: HoinkText.displayHero.copyWith(color: HoinkColors.onPrimaryContainer),
              errorText: _err('amountCents'),
              errorStyle: HoinkText.bodySm.copyWith(color: HoinkColors.tertiaryFixedDim),
            ),
          ),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = d);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.schedule, size: 18, color: HoinkColors.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  isTransfer
                      ? 'Data: ${formatDayMonth(isoDate(_date))}'
                      : 'Competência: ${formatDayMonth(isoDate(_date))}',
                  style: HoinkText.bodyMd.copyWith(color: HoinkColors.primaryFixedDim),
                ),
                const Icon(Symbols.expand_more, size: 18, color: HoinkColors.primaryFixedDim),
              ],
            ),
          ),
        ],
      ),
    );

    InputDecoration deco(String label, IconData icon, {String? field}) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      errorText: field == null ? null : _err(field),
    );

    final fields = <Widget>[
      TextFormField(
        controller: _description,
        validator: (v) => !isTransfer && (v ?? '').trim().isEmpty ? 'Informe a descrição' : null,
        decoration: deco(
          isTransfer ? 'Descrição (opcional)' : (_type == 'INCOME' ? 'Descrição da receita' : 'Descrição da despesa'),
          Symbols.short_text,
          field: 'description',
        ),
      ),
      if (!isTransfer)
        TextFormField(
          controller: _counterparty,
          decoration: deco(
            _type == 'INCOME' ? 'Cliente / Pagador' : 'Estabelecimento / Beneficiário',
            Symbols.storefront,
          ),
        ),
    ];

    final contactKind = _type == 'INCOME' ? 'CLIENT' : 'SUPPLIER';
    final contacts = isTransfer
        ? const <Contact>[]
        : (ref.watch(contactsProvider((entityId: entityId, kind: contactKind))).value ?? const <Contact>[]);
    final showContactPicker = !isTransfer && (contacts.isNotEmpty || _contactId != null);
    final contactPicker = DropdownButtonFormField<String?>(
      key: const Key('contact-picker'),
      initialValue: contacts.any((c) => c.id == _contactId) ? _contactId : null,
      isExpanded: true,
      decoration: deco(_type == 'INCOME' ? 'Cliente (opcional)' : 'Fornecedor (opcional)', Symbols.groups),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
        for (final c in contacts)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => _contactId = v),
    );

    final settlements = _original?.settlements ?? const <SettlementEntry>[];
    final settlementHistory = HoinkCard(
      color: HoinkColors.surfaceLow,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_type == 'INCOME' ? 'Histórico de recebimentos' : 'Histórico de pagamentos', style: HoinkText.labelMd),
          const SizedBox(height: 8),
          for (final st in settlements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Symbols.check_circle, size: 16, color: HoinkColors.surfaceTint),
                  const SizedBox(width: 8),
                  Expanded(child: Text(formatBrDate(st.date), style: HoinkText.bodyMd)),
                  Text(formatBRL(st.amountCents), style: HoinkText.labelMd),
                ],
              ),
            ),
          if (_original != null) ...[
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Em aberto', style: HoinkText.bodySm)),
                Text(formatBRL(_original!.remainingCents), style: HoinkText.labelMd),
              ],
            ),
          ],
        ],
      ),
    );

    final categoryPicker = isTransfer
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Categoria', style: HoinkText.headlineSm)),
                  if (_categoryId != null)
                    Text(
                      '${categories.firstWhere((c) => c.id == _categoryId, orElse: () => visibleCats.first).name} selecionada',
                      style: HoinkText.labelSm.copyWith(color: HoinkColors.surfaceTint),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in visibleCats)
                    _CategoryChip(
                      category: c,
                      active: c.id == _categoryId,
                      onTap: () => setState(() => _categoryId = c.id == _categoryId ? null : c.id),
                    ),
                ],
              ),
            ],
          );

    Widget accountDropdown({
      required String label,
      required String? value,
      required List<Account> options,
      required ValueChanged<String?> onChanged,
      bool showEntity = false,
    }) {
      final names = {for (final e in entities) e.id: e.isPersonal ? 'PF' : 'PJ'};
      return DropdownButtonFormField<String>(
        initialValue: options.any((a) => a.id == value) ? value : null,
        isExpanded: true,
        validator: (v) => v == null ? 'Selecione a conta' : null,
        decoration: deco(label, Symbols.credit_card, field: 'accountId'),
        items: [
          for (final a in options)
            DropdownMenuItem(
              value: a.id,
              child: Text(
                '${showEntity ? '[${names[a.entityId]}] ' : ''}${a.name} • ${formatBRL(a.balanceCents)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      );
    }

    final accountSection = isTransfer
        ? Column(
            children: [
              accountDropdown(
                label: 'Conta de origem',
                value: _accountId,
                options: allAccounts,
                showEntity: true,
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 16),
              accountDropdown(
                label: 'Conta de destino',
                value: _toAccountId,
                options: allAccounts.where((a) => a.id != _accountId).toList(),
                showEntity: true,
                onChanged: (v) => setState(() => _toAccountId = v),
              ),
              if (_isCrossEntity()) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _classification,
                  isExpanded: true,
                  decoration: deco('Classificação gerencial (entre Pessoal e PJ)', Symbols.label),
                  items: [
                    for (final e in transferClassificationLabels.entries)
                      if (e.key != 'INTERNAL') DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _classification = v!),
                ),
              ],
              if (allAccounts.length < 2)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Cadastre pelo menos duas contas para transferir.',
                    style: HoinkText.bodySm.copyWith(color: HoinkColors.error),
                  ),
                ),
            ],
          )
        : accounts.isEmpty
        ? HoinkCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Symbols.info, color: HoinkColors.tertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Nenhuma conta em ${entity.name}. Cadastre uma conta primeiro.', style: HoinkText.bodyMd),
                ),
                TextButton(onPressed: () => context.go('/contas'), child: const Text('Cadastrar')),
              ],
            ),
          )
        : accountDropdown(
            label: _type == 'INCOME' ? 'Conta de destino' : 'Origem do dinheiro',
            value: _accountId,
            options: accounts,
            onChanged: (v) => setState(() => _accountId = v),
          );

    final statusSection = isTransfer
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _recurring && !widget.isEdit
                    ? 'Primeira ocorrência'
                    : (_type == 'INCOME' ? 'Status do recebimento' : 'Status da despesa'),
                style: HoinkText.headlineSm,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (value, label, icon) in [
                    ('SETTLED', _type == 'INCOME' ? 'Recebido' : 'Liquidado / Pago', Symbols.check_circle),
                    if (!(_recurring && !widget.isEdit)) ('PENDING', 'Pendente', Symbols.hourglass_top),
                    ('PLANNED', 'Previsto', Symbols.event),
                    if (widget.isEdit || _status == 'PARTIAL') ('PARTIAL', 'Parcial', Symbols.timelapse),
                  ])
                    _StatusOption(
                      label: label,
                      icon: icon,
                      active: _status == value,
                      onTap: () => setState(() => _status = value),
                    ),
                ],
              ),
              if (_status == 'PARTIAL') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _settledPartial,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final p = parseBRLToCents(v ?? '');
                    final total = parseBRLToCents(_amount.text) ?? 0;
                    if (p == null || p <= 0 || p >= total) return 'Informe um valor maior que zero e menor que o total';
                    return null;
                  },
                  decoration: deco('Valor já liquidado', Symbols.payments, field: 'settledAmountCents'),
                ),
              ],
              if (_status != 'SETTLED' && !(_recurring && !widget.isEdit)) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Symbols.event, size: 18),
                  label: Text(
                    _dueDate == null ? 'Definir vencimento' : 'Vencimento: ${formatBrDate(isoDate(_dueDate!))}',
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dueDate ?? _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _dueDate = d);
                  },
                ),
              ],
            ],
          );

    final phase2 = isTransfer
        ? const SizedBox.shrink()
        : HoinkCard(
            color: HoinkColors.surfaceLow,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.isEdit && (_original?.isRecurring ?? false))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Symbols.event_repeat, color: HoinkColors.surfaceTint),
                    title: Text(
                      'Ocorrência de recorrência ${frequencyLabels[_original!.recurring!.frequency]?.toLowerCase() ?? ''}',
                      style: HoinkText.labelMd,
                    ),
                    subtitle: const Text(
                      'Ao salvar, escolha se vale só para esta, desta em diante ou para toda a série.',
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          context.push('/recorrencias/${_original!.entityId}/${_original!.recurring!.ruleId}'),
                      child: const Text('Ver série'),
                    ),
                  )
                else if (!widget.isEdit) ...[
                  SwitchListTile(
                    key: const Key('recurring-toggle'),
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Symbols.repeat, color: HoinkColors.pine),
                    title: Text(
                      _type == 'INCOME' ? 'Receita fixa ou recorrente' : 'Despesa fixa ou recorrente',
                      style: HoinkText.labelMd,
                    ),
                    subtitle: const Text('Cria as próximas ocorrências automaticamente'),
                    value: _recurring,
                    onChanged: (v) => setState(() => _recurring = v),
                  ),
                  if (_recurring) _recurrenceOptions(),
                ],
                if (!widget.isEdit && _type == 'EXPENSE') ...[
                  const Divider(),
                  ListTile(
                    key: const Key('card-purchase'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Symbols.layers, color: HoinkColors.pine),
                    title: Text('Compra no cartão ou parcelada', style: HoinkText.labelMd),
                    subtitle: const Text('Lance no cartão de crédito e divida em parcelas nas próximas faturas'),
                    trailing: const Icon(Symbols.chevron_right),
                    onTap: _cardPurchase,
                  ),
                ],
              ],
            ),
          );

    final extra = Column(
      children: [
        if (!isTransfer)
          TextFormField(controller: _tags, decoration: deco('Tags (separadas por vírgula)', Symbols.sell)),
        const SizedBox(height: 16),
        TextFormField(controller: _notes, maxLines: 3, minLines: 1, decoration: deco('Observações', Symbols.notes)),
      ],
    );

    final actions = Row(
      children: [
        if (widget.isEdit) ...[
          IconButton(
            tooltip: 'Excluir',
            onPressed: () => _delete(entityId),
            icon: const Icon(Symbols.delete, color: HoinkColors.error),
          ),
          if (_original?.isOpen ?? false)
            TextButton.icon(
              onPressed: () async {
                await settleDialog(context, ref, _original!);
                if (mounted) _load();
              },
              icon: const Icon(Symbols.check_circle),
              label: const Text('Registrar pagamento'),
            ),
        ],
        const Spacer(),
        TextButton(onPressed: _close, child: const Text('Cancelar')),
        const SizedBox(width: 12),
        FilledButton.icon(
          key: const Key('save-transaction'),
          onPressed: _busy || (isTransfer ? allAccounts.length < 2 : accounts.isEmpty) ? null : () => _submit(entityId),
          icon: const Icon(Symbols.check, size: 18),
          label: Text(
            _busy ? 'Salvando...' : (isTransfer ? 'Transferir' : 'Salvar ${_type == 'INCOME' ? 'receita' : 'despesa'}'),
          ),
        ),
      ],
    );

    const gap = SizedBox(height: 20);
    final formColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        amountCard,
        gap,
        if (wide && fields.length == 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fields[0]),
              const SizedBox(width: 16),
              Expanded(child: fields[1]),
            ],
          )
        else
          for (final f in fields) ...[f, const SizedBox(height: 16)],
        if (showContactPicker) ...[contactPicker, gap],
        if (settlements.isNotEmpty) ...[settlementHistory, gap],
        gap,
        categoryPicker,
        gap,
        accountSection,
        gap,
        statusSection,
        gap,
        phase2,
        gap,
        extra,
        const SizedBox(height: 28),
        actions,
      ],
    );

    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.all(wide ? 24 : 16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  if (showPicker && !wide) ...[
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: entityPicker),
                  ],
                  const SizedBox(height: 20),
                  typeTabs,
                  const SizedBox(height: 20),
                  wide ? HoinkCard(padding: const EdgeInsets.all(32), child: formColumn) : formColumn,
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  const _TypeTab({required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fg = active ? HoinkColors.ivory : (disabled ? HoinkColors.outlineVariant : HoinkColors.onSurfaceVariant);
    return Material(
      color: active ? HoinkColors.pine : Colors.transparent,
      borderRadius: BorderRadius.circular(HoinkRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(HoinkRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: disabled && !active ? HoinkColors.tertiaryFixedDim : fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: HoinkText.labelMd.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.active, required this.onTap});
  final Category category;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: active,
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(HoinkRadius.md),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: active ? HoinkColors.pine : HoinkColors.surfaceLowest,
          borderRadius: BorderRadius.circular(HoinkRadius.md),
          border: Border.all(color: active ? HoinkColors.pine : HoinkColors.stroke),
        ),
        child: Column(
          children: [
            Icon(
              categoryIcon(category.icon),
              color: active ? HoinkColors.ivory : HoinkColors.pine,
              fill: active ? 1 : 0,
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HoinkText.labelSm.copyWith(color: active ? HoinkColors.ivory : HoinkColors.onSurface),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(HoinkRadius.md),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: active ? HoinkColors.pine : HoinkColors.surfaceLowest,
        borderRadius: BorderRadius.circular(HoinkRadius.md),
        border: Border.all(color: active ? HoinkColors.pine : HoinkColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: active ? HoinkColors.ivory : HoinkColors.pine),
          const SizedBox(width: 8),
          Text(label, style: HoinkText.labelMd.copyWith(color: active ? HoinkColors.ivory : HoinkColors.onSurface)),
        ],
      ),
    ),
  );
}
