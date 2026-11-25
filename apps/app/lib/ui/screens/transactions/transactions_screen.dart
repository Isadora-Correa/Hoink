import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../shell/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../../../core/money_input.dart';

class TxnFilter {
  const TxnFilter({this.q = '', this.kind, this.status, this.accountId, this.page = 1, this.sort = 'date_desc'});
  final String q;
  final String? kind;
  final String? status;
  final String? accountId;
  final int page;
  final String sort;

  TxnFilter copyWith({
    String? q,
    Object? kind = _keep,
    Object? status = _keep,
    Object? accountId = _keep,
    int? page,
    String? sort,
  }) => TxnFilter(
    q: q ?? this.q,
    kind: kind == _keep ? this.kind : kind as String?,
    status: status == _keep ? this.status : status as String?,
    accountId: accountId == _keep ? this.accountId : accountId as String?,
    page: page ?? this.page,
    sort: sort ?? this.sort,
  );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is TxnFilter &&
      other.q == q &&
      other.kind == kind &&
      other.status == status &&
      other.accountId == accountId &&
      other.page == page &&
      other.sort == sort;
  @override
  int get hashCode => Object.hash(q, kind, status, accountId, page, sort);
}

class _FilterController extends Notifier<TxnFilter> {
  @override
  TxnFilter build() {
    // Trocar de ambiente ou de mês volta para a primeira página e limpa o filtro de conta.
    ref.watch(effectiveScopeProvider);
    ref.watch(monthProvider);
    return const TxnFilter();
  }

  void update(TxnFilter f) => state = f;
}

final txnFilterProvider = NotifierProvider<_FilterController, TxnFilter>(_FilterController.new);

final txnPageProvider = FutureProvider<PageResult<Txn>>((ref) async {
  ref.watch(dataVersionProvider);
  final f = ref.watch(txnFilterProvider);
  final month = ref.watch(monthProvider);
  final scope = ref.watch(effectiveScopeProvider);
  await ref.watch(entitiesProvider.future);
  final entity = ref.watch(currentEntityProvider);
  final last = DateTime(int.parse(month.substring(0, 4)), int.parse(month.substring(5)) + 1, 0).day;
  return ref
      .read(repositoryProvider)
      .transactions(
        entityId: scope == Scope.total ? null : entity?.id,
        query: {
          'page': f.page,
          'pageSize': 20,
          'q': f.q,
          'kind': f.kind,
          'status': f.status,
          'accountId': f.accountId,
          'sort': f.sort,
          'from': '$month-01',
          'to': '$month-${last.toString().padLeft(2, '0')}',
        },
      );
});

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late final _search = TextEditingController(text: widget.initialQuery ?? '');
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) {
      Future.microtask(() => ref.read(txnFilterProvider.notifier).update(TxnFilter(q: widget.initialQuery!)));
    }
  }

  @override
  void didUpdateWidget(TransactionsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialQuery != widget.initialQuery) {
      _search.text = widget.initialQuery ?? '';
      ref.read(txnFilterProvider.notifier).update(ref.read(txnFilterProvider).copyWith(q: _search.text, page: 1));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _set(TxnFilter f) => ref.read(txnFilterProvider.notifier).update(f);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final f = ref.watch(txnFilterProvider);
    final page = ref.watch(txnPageProvider);
    final dash = ref.watch(dashboardProvider).value;
    final entity = ref.watch(currentEntityProvider);
    final accounts = entity == null
        ? const <Account>[]
        : (ref.watch(accountsProvider(entity.id)).value ?? const <Account>[]);
    final month = ref.watch(monthProvider);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXTRATO INTELIGENTE',
          style: HoinkText.labelSm.copyWith(color: HoinkColors.surfaceTint, letterSpacing: 1),
        ),
        Text(
          'Lançamentos',
          style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(color: HoinkColors.primary),
        ),
        Text(
          '${monthLabel(month)} • ${entity?.name ?? 'Visão consolidada'}',
          style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
        ),
      ],
    );

    final kpis = dash == null
        ? const SizedBox.shrink()
        : KpiWrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MiniKpi('Receitas', dash.realized.incomeCents, Symbols.arrow_downward, HoinkColors.surfaceTint),
              _MiniKpi('Despesas', -dash.realized.expenseCents, Symbols.arrow_upward, HoinkColors.error),
              _MiniKpi(
                'Saldo do mês',
                dash.realized.netCents,
                Symbols.account_balance_wallet,
                HoinkColors.pine,
                dark: true,
              ),
              _MiniKpi(
                'A pagar',
                // Saída prevista: negativo como "Despesas" (antes aparecia "+ R$" no card).
                -(dash.forecast.expenseCents + dash.overdue.expenseCents),
                Symbols.schedule,
                HoinkColors.tertiaryContainer,
              ),
            ],
          );

    // Busca + um botão "Filtros" que abre tudo num lugar só (tipo, status, conta, ordem).
    final activeCount =
        [f.kind, f.status, f.accountId].where((v) => v != null).length + (f.sort == 'date_desc' ? 0 : 1);
    final filters = HoinkCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar neste mês',
                    prefixIcon: Icon(Symbols.search, size: 20),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () => _set(f.copyWith(q: v.trim(), page: 1)));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: activeCount > 0,
                label: Text('$activeCount'),
                backgroundColor: HoinkColors.pigPink,
                textColor: HoinkColors.pine,
                child: FilledButton.tonalIcon(
                  key: const Key('txn-filters'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () async {
                    final next = await showTxnFilters(context, f, accounts);
                    if (next != null) _set(next.copyWith(page: 1));
                  },
                  icon: const Icon(Symbols.tune, size: 18),
                  label: const Text('Filtros'),
                ),
              ),
            ],
          ),
          if (activeCount > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _set(TxnFilter(q: f.q)),
                child: const Text('Limpar filtros'),
              ),
            ),
        ],
      ),
    );

    final list = page.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(txnPageProvider)),
      data: (p) => HoinkCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p.total} lançamento(s) encontrados',
                      style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (p.items.isEmpty)
              EmptyState(
                title: 'Nada por aqui',
                message: 'Nenhum lançamento corresponde aos filtros deste mês.',
                action: FilledButton(
                  onPressed: () => context.push('/lancamentos/novo'),
                  child: const Text('Novo lançamento'),
                ),
              ),
            for (final t in p.items) ...[
              TransactionTile(
                t,
                onTap: t.isTransfer
                    ? () => _transferSheet(context, t)
                    : () => context.push('/lancamentos/${t.entityId}/${t.id}'),
                trailingExtra: t.isOpen
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          tooltip: t.isIn ? 'Confirmar recebimento' : 'Pagar',
                          icon: const Icon(Symbols.check_circle, color: HoinkColors.surfaceTint),
                          onPressed: () => settleDialog(context, ref, t),
                        ),
                      )
                    : null,
              ),
              const Divider(),
            ],
            if (p.totalPages > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Página ${p.page} de ${p.totalPages}', style: HoinkText.bodySm),
                    IconButton(
                      onPressed: p.page > 1 ? () => _set(f.copyWith(page: p.page - 1)) : null,
                      icon: const Icon(Symbols.chevron_left),
                    ),
                    IconButton(
                      onPressed: p.page < p.totalPages ? () => _set(f.copyWith(page: p.page + 1)) : null,
                      icon: const Icon(Symbols.chevron_right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: () async => ref.read(dataVersionProvider.notifier).bump(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 8, wide ? 24 : 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: header),
                      if (wide)
                        FilledButton.icon(
                          onPressed: () => context.push('/lancamentos/novo'),
                          icon: const Icon(Symbols.add_circle, size: 18),
                          label: const Text('Novo Lançamento'),
                        ),
                    ],
                  ),
                  if (!wide) ...[const SizedBox(height: 8), const MonthPicker(expanded: true)],
                  const SizedBox(height: 16),
                  kpis,
                  const SizedBox(height: 16),
                  filters,
                  const SizedBox(height: 16),
                  list,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _transferSheet(BuildContext context, Txn t) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.description, style: HoinkText.headlineMd),
            const SizedBox(height: 8),
            Text('${formatBRL(t.amountCents)} • ${formatBrDate(t.competenceDate)}', style: HoinkText.bodyMd),
            Text(
              transferClassificationLabels[t.transferClassification] ?? 'Transferência',
              style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Transferências não são receitas nem despesas. Para alterar, exclua e registre novamente.',
              style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: HoinkColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Symbols.delete),
              label: const Text('Excluir transferência (as duas pernas)'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && t.transferId != null) {
      try {
        await ref.read(repositoryProvider).deleteTransfer(t.transferId!);
        ref.read(dataVersionProvider.notifier).bump();
        if (context.mounted) showSuccess(context, 'Transferência excluída');
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }
  }
}

/// Diálogo de liquidação (total ou parcial) de um lançamento em aberto.
Future<void> settleDialog(BuildContext context, WidgetRef ref, Txn t) async {
  // Contas recorrentes de valor variável/estimado: informa-se o valor final da conta e paga-se tudo.
  final variable = (t.recurring?.isVariable ?? false) && t.settledAmountCents == 0;
  final amount = TextEditingController(text: formatAmount(variable ? t.amountCents : t.remainingCents));
  var date = DateTime.now();
  final result = await showDialog<(int, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t.isIn ? 'Confirmar recebimento' : 'Registrar pagamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.description, style: HoinkText.headlineSm),
            Text(
              variable ? 'Valor previsto: ${formatBRL(t.amountCents)}' : 'Em aberto: ${formatBRL(t.remainingCents)}',
              style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('settle-amount'),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [BrlInputFormatter()],
              decoration: InputDecoration(
                labelText: variable ? 'Valor final da conta' : 'Valor pago agora',
                helperText: variable ? 'Altera só esta ocorrência; as próximas continuam com o valor previsto.' : null,
                helperMaxLines: 2,
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Symbols.calendar_today, size: 18),
              label: Text('Data: ${formatBrDate(isoDate(date))}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => date = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final cents = parseBRLToCents(amount.text);
              if (cents == null || cents <= 0 || (!variable && cents > t.remainingCents)) return;
              Navigator.pop(ctx, (cents, isoDate(date)));
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
  if (result == null) return;
  try {
    final repo = ref.read(repositoryProvider);
    if (variable) {
      await repo.settle(t.entityId, t.id, result.$2, finalAmountCents: result.$1);
    } else {
      await repo.settle(t.entityId, t.id, result.$2, amountCents: result.$1);
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) {
      final full = variable || result.$1 == t.remainingCents;
      showSuccess(context, full ? 'Lançamento liquidado' : 'Pagamento parcial registrado');
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi(this.label, this.cents, this.icon, this.color, {this.dark = false});
  final String label;
  final int cents;
  final IconData icon;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: dark ? HoinkColors.primaryFixedDim : color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HoinkText.labelSm.copyWith(
                  color: dark ? HoinkColors.onPrimaryContainer : HoinkColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Valores grandes encolhem em vez de estourar o card estreito do celular.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            cents,
            signed: true,
            style: HoinkText.headlineMd,
            color: dark ? Colors.white : HoinkColors.onSurface,
          ),
        ),
      ],
    );
    return SizedBox(
      width: 210,
      child: dark
          ? HeroCard(padding: const EdgeInsets.all(18), child: card)
          : HoinkCard(padding: const EdgeInsets.all(18), child: card),
    );
  }
}

const _kindLabels = {
  null: 'Todos',
  'income': 'Receitas',
  'expense': 'Despesas',
  'transfer': 'Transferências',
  'recurring': 'Recorrentes',
};
const _sortLabels = {
  'date_desc': 'Mais recentes',
  'date_asc': 'Mais antigos',
  'amount_desc': 'Maior valor',
  'amount_asc': 'Menor valor',
};

/// Filtros de lançamentos num painel só. Devolve o filtro novo (ou null se fechar sem aplicar).
Future<TxnFilter?> showTxnFilters(BuildContext context, TxnFilter current, List<Account> accounts) =>
    showModalBottomSheet<TxnFilter>(
      context: context,
      // Acima da barra de navegação e do botão "+ Novo".
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HoinkColors.surfaceLowest,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) {
        var f = current;
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Filtros', style: HoinkText.headlineSm),
                  const SizedBox(height: 16),
                  Text('Tipo', style: HoinkText.labelMd),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _kindLabels.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: f.kind == e.key,
                          showCheckmark: false,
                          selectedColor: HoinkColors.pine,
                          labelStyle: HoinkText.labelMd.copyWith(
                            color: f.kind == e.key ? HoinkColors.ivory : HoinkColors.onSurface,
                          ),
                          backgroundColor: HoinkColors.surfaceLowest,
                          shape: const StadiumBorder(side: BorderSide(color: HoinkColors.stroke)),
                          onSelected: (_) => setState(() => f = f.copyWith(kind: e.key)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: f.status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Todos os status')),
                      for (final s in ['SETTLED', 'PENDING', 'PLANNED', 'PARTIAL', 'OVERDUE', 'CANCELED'])
                        DropdownMenuItem<String?>(value: s, child: Text(statusLabels[s]!)),
                    ],
                    onChanged: (v) => setState(() => f = f.copyWith(status: v)),
                  ),
                  if (accounts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: f.accountId,
                      decoration: const InputDecoration(labelText: 'Conta'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Todas as contas')),
                        for (final a in accounts)
                          DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(a.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => f = f.copyWith(accountId: v)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: f.sort,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: [for (final e in _sortLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => f = f.copyWith(sort: v)),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Symbols.event_repeat, size: 18),
                      label: const Text('Gerenciar recorrências'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.go('/recorrencias');
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('apply-filters'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.pop(ctx, f),
                    child: const Text('Aplicar'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => Navigator.pop(ctx, TxnFilter(q: current.q)),
                    child: const Text('Limpar filtros'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
