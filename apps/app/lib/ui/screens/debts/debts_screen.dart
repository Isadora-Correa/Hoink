import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/page.dart';

final debtsProvider = FutureProvider.family<List<Debt>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).debts(entityId, includeClosed: true);
});

final debtProvider = FutureProvider.family<Debt, ({String entityId, String id})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).debt(a.entityId, a.id);
});

/// Taxa em partes por milhão → "1,49% a.m.".
String formatRatePpm(int ppm) {
  final pct = ppm / 10000;
  final s = pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : (ppm % 100 == 0 ? 2 : 4)).replaceAll('.', ',');
  return '$s% a.m.';
}

/// "1,49" → 14900 (partes por milhão). A taxa é um parâmetro, não dinheiro.
int? parseRateToPpm(String input) {
  final s = input.replaceAll('%', '').replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) return 0;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v > 100) return null;
  return (v * 10000).round();
}

class _StatePill extends StatelessWidget {
  const _StatePill(this.state);
  final String state;
  @override
  Widget build(BuildContext context) => switch (state) {
    'PAID' => const Pill('Paga', icon: Symbols.check),
    'OVERDUE' => const StatusPill('OVERDUE'),
    'PARTIAL' => const StatusPill('PARTIAL'),
    _ => const StatusPill('PENDING'),
  };
}

/// Financiamentos, empréstimos e outras dívidas com cronograma.
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = entitiesInScope(ref);
    final single = shown.length == 1 ? shown.first : null;
    return ModulePage(
      title: 'Dívidas',
      subtitle:
          'Financiamentos e empréstimos com parcelas, juros e saldo devedor. As parcelas entram em Contas a pagar.',
      action: single != null && single.canWrite
          ? FilledButton.icon(
              key: const Key('new-debt'),
              onPressed: () => context.push('/dividas/nova?ambiente=${single.id}'),
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('Nova dívida'),
            )
          : null,
      children: [
        for (final e in shown) ...[
          if (shown.length > 1)
            EntityHeading(
              e,
              trailing: e.canWrite
                  ? TextButton.icon(
                      onPressed: () => context.push('/dividas/nova?ambiente=${e.id}'),
                      icon: const Icon(Symbols.add, size: 18),
                      label: const Text('Nova dívida'),
                    )
                  : null,
            ),
          _EntityDebts(entity: e),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _EntityDebts extends ConsumerWidget {
  const _EntityDebts({required this.entity});
  final FinancialEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(debtsProvider(entity.id))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(debtsProvider(entity.id))),
          data: (debts) {
            final active = debts.where((d) => d.status == 'ACTIVE').toList();
            final closed = debts.where((d) => d.status != 'ACTIVE').toList();
            if (debts.isEmpty) {
              return HoinkCard(
                child: EmptyState(
                  title: 'Nenhuma dívida cadastrada',
                  message: 'Cadastre financiamentos e empréstimos para ver o saldo devedor e simular a quitação.',
                  action: entity.canWrite
                      ? FilledButton(
                          onPressed: () => context.push('/dividas/nova?ambiente=${entity.id}'),
                          child: const Text('Cadastrar dívida'),
                        )
                      : null,
                ),
              );
            }
            final outstanding = active.fold<int>(0, (s, d) => s + d.summary.outstandingPrincipalCents);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (active.isNotEmpty) ...[
                  Text(
                    'Saldo devedor total: ${formatBRL(outstanding)}',
                    style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final d in active) ...[_DebtCard(debt: d), const SizedBox(height: 12)],
                if (closed.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Quitadas e canceladas (${closed.length})', style: HoinkText.labelMd),
                    children: [
                      for (final d in closed) ...[_DebtCard(debt: d), const SizedBox(height: 8)],
                    ],
                  ),
              ],
            );
          },
        );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.debt});
  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final s = debt.summary;
    final next = s.nextInstallment;
    return HoinkCard(
      padding: const EdgeInsets.all(20),
      onTap: () => context.push('/dividas/${debt.entityId}/${debt.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                Symbols.credit_score,
                background: HoinkColors.tertiaryFixed,
                foreground: HoinkColors.tertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(debt.name, style: HoinkText.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        debtKindLabels[debt.kind]!,
                        ?debt.creditor,
                        debt.system,
                        formatRatePpm(debt.monthlyRatePpm),
                      ].join(' • '),
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (debt.status == 'PAID_OFF')
                const Pill('Quitada', icon: Symbols.check)
              else if (debt.status == 'CANCELED')
                const StatusPill('CANCELED')
              else if (s.overdueInstallments > 0)
                const StatusPill('OVERDUE'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _Figure('Saldo devedor', s.outstandingPrincipalCents),
              _Figure('Falta pagar', s.remainingTotalCents),
              if (next != null)
                _Figure('Próxima parcela', next.totalCents, caption: 'vence ${formatBrDate(next.dueDate)}'),
            ],
          ),
          const SizedBox(height: 12),
          ProgressRail(value: s.progressBps / 10000),
          const SizedBox(height: 6),
          Text(
            '${formatPercentBps(s.progressBps)} quitado • ${s.paidInstallments} pagas, ${s.remainingInstallments} restantes',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.cents, {this.caption});
  final String label;
  final int cents;
  final String? caption;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
      MoneyText(cents, style: HoinkText.headlineSm),
      if (caption != null) Text(caption!, style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
    ],
  );
}

/// Cadastro de dívida com prévia do cronograma calculada pela API.
class DebtFormScreen extends ConsumerStatefulWidget {
  const DebtFormScreen({super.key, this.entityId});
  final String? entityId;
  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  final _name = TextEditingController();
  final _creditor = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  final _count = TextEditingController(text: '12');
  final _fees = TextEditingController();
  final _paid = TextEditingController(text: '0');
  String _kind = 'LOAN';
  String _system = 'PRICE';
  DateTime _firstDue = DateTime(DateTime.now().year, DateTime.now().month + 1, 10);
  String? _accountId;
  DebtSimulation? _simulation;
  bool _busy = false;

  String? get _entityId => widget.entityId ?? ref.read(currentEntityProvider)?.id;

  Map<String, Object?>? _simulationBody() {
    final principal = parseBRLToCents(_principal.text);
    final rate = parseRateToPpm(_rate.text);
    final count = int.tryParse(_count.text);
    final fees = _fees.text.trim().isEmpty ? 0 : parseBRLToCents(_fees.text);
    if (principal == null || principal <= 0) return _invalid('Informe o valor financiado');
    if (rate == null) return _invalid('Taxa de juros inválida (ex.: 1,49)');
    if (count == null || count < 1 || count > 600) return _invalid('Número de parcelas entre 1 e 600');
    if (fees == null || fees < 0) return _invalid('Encargos inválidos');
    return {
      'principalCents': principal,
      'monthlyRatePpm': rate,
      'system': _system,
      'installmentCount': count,
      'firstDueDate': isoDate(_firstDue),
      'feesCents': fees,
    };
  }

  Map<String, Object?>? _invalid(String message) {
    showError(context, message);
    return null;
  }

  Future<void> _simulate() async {
    final body = _simulationBody();
    final entityId = _entityId;
    if (body == null || entityId == null) return;
    try {
      final sim = await ref.read(repositoryProvider).simulateDebt(entityId, body);
      setState(() => _simulation = sim);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    final body = _simulationBody();
    final entityId = _entityId;
    if (body == null || entityId == null) return;
    if (_name.text.trim().isEmpty) return showError(context, 'Informe um nome para a dívida');
    if (_accountId == null) return showError(context, 'Escolha a conta que paga as parcelas');
    setState(() => _busy = true);
    try {
      final debt = await ref.read(repositoryProvider).createDebt(entityId, {
        ...body,
        'kind': _kind,
        'name': _name.text.trim(),
        'creditor': _creditor.text.trim().isEmpty ? null : _creditor.text.trim(),
        'accountId': _accountId,
        'paidInstallments': int.tryParse(_paid.text) ?? 0,
      });
      ref.read(dataVersionProvider.notifier).bump();
      if (mounted) {
        showSuccess(context, 'Dívida cadastrada');
        context.go('/dividas/${debt.entityId}/${debt.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entityId = _entityId;
    if (entityId == null) {
      return const Center(child: Text('Escolha o ambiente Pessoal ou Pro para cadastrar a dívida.'));
    }
    final accounts = ref.watch(accountsProvider(entityId)).value?.where((a) => !a.archived).toList() ?? const [];
    _accountId ??= accounts.firstOrNull?.id;
    final sim = _simulation;
    const gap = SizedBox(height: 12);
    return ModulePage(
      title: 'Nova dívida',
      subtitle: 'Informe as condições do contrato. A hoink. calcula as parcelas separando principal, juros e encargos.',
      leading: IconButton(onPressed: () => context.go('/dividas'), icon: const Icon(Symbols.arrow_back)),
      maxWidth: 760,
      children: [
        HoinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [for (final e in debtKindLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _kind = v!),
              ),
              gap,
              TextField(
                key: const Key('debt-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Financiamento do carro'),
              ),
              gap,
              TextField(
                controller: _creditor,
                decoration: const InputDecoration(labelText: 'Credor (banco, financeira, pessoa)'),
              ),
              gap,
              MoneyField(controller: _principal, label: 'Valor financiado', fieldKey: const Key('debt-principal')),
              gap,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('debt-rate'),
                      controller: _rate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Juros ao mês', suffixText: '% a.m.'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('debt-count'),
                      controller: _count,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Parcelas'),
                    ),
                  ),
                ],
              ),
              gap,
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'PRICE', label: Text('PRICE (parcelas iguais)')),
                  ButtonSegment(value: 'SAC', label: Text('SAC (parcelas decrescentes)')),
                ],
                selected: {_system},
                onSelectionChanged: (s) => setState(() => _system = s.first),
              ),
              gap,
              DateField(label: '1º vencimento', value: _firstDue, onChanged: (d) => setState(() => _firstDue = d)),
              gap,
              MoneyField(
                controller: _fees,
                label: 'Encargos por parcela (opcional)',
                helper: 'Seguro, tarifa ou taxa fixa cobrada em toda parcela.',
              ),
              gap,
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Conta que paga as parcelas'),
                items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              gap,
              TextField(
                controller: _paid,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Parcelas já pagas antes de usar a hoink.',
                  helperText: 'Elas aparecem como pagas, sem gerar lançamentos.',
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    key: const Key('simulate-debt'),
                    onPressed: _simulate,
                    icon: const Icon(Symbols.calculate, size: 18),
                    label: const Text('Simular'),
                  ),
                  FilledButton(
                    key: const Key('save-debt'),
                    onPressed: _busy ? null : _save,
                    child: const Text('Cadastrar dívida'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (sim != null) ...[
          const SizedBox(height: 16),
          HoinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Simulação', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                const SizedBox(height: 8),
                ValueRow(_system == 'PRICE' ? 'Parcela' : '1ª parcela → última', sim.firstPaymentCents, bold: true),
                if (_system == 'SAC') ValueRow('Última parcela', sim.lastPaymentCents),
                ValueRow('Total de juros', sim.totalInterestCents),
                if (sim.totalFeesCents > 0) ValueRow('Total de encargos', sim.totalFeesCents),
                ValueRow('Total a pagar', sim.totalCents, bold: true),
                const SizedBox(height: 8),
                _ScheduleTable(
                  rows: [
                    for (final r in sim.rows.take(6))
                      (r.number, r.dueDate, r.principalCents, r.interestCents, r.feesCents, r.totalCents, null),
                  ],
                ),
                if (sim.rows.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '… e mais ${sim.rows.length - 6} parcelas',
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

typedef _Row = (int? number, String dueDate, int principal, int interest, int fees, int total, Widget? status);

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({required this.rows});
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final head = HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant);
    String money(int c) => formatBRL(c);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columnSpacing: 20,
        columns: [
          DataColumn(label: Text('Nº', style: head)),
          DataColumn(label: Text('Vencimento', style: head)),
          DataColumn(label: Text('Principal', style: head), numeric: true),
          DataColumn(label: Text('Juros', style: head), numeric: true),
          DataColumn(label: Text('Encargos', style: head), numeric: true),
          DataColumn(label: Text('Parcela', style: head), numeric: true),
          if (rows.any((r) => r.$7 != null)) DataColumn(label: Text('Situação', style: head)),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(r.$1?.toString() ?? '—')),
                DataCell(Text(formatBrDate(r.$2))),
                DataCell(Text(money(r.$3))),
                DataCell(Text(money(r.$4))),
                DataCell(Text(money(r.$5))),
                DataCell(Text(money(r.$6), style: HoinkText.labelMd)),
                if (rows.any((x) => x.$7 != null)) DataCell(r.$7 ?? const SizedBox()),
              ],
            ),
        ],
      ),
    );
  }
}

/// Detalhe da dívida: saldo devedor, composição do que foi pago, cronograma e ações.
class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key, required this.entityId, required this.debtId});
  final String entityId;
  final String debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(debtProvider((entityId: entityId, id: debtId)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e),
          data: (d) {
            final s = d.summary;
            final active = d.status == 'ACTIVE';
            final next = s.nextInstallment;
            return ModulePage(
              title: d.name,
              subtitle: [
                debtKindLabels[d.kind]!,
                ?d.creditor,
                '${d.system} • ${formatRatePpm(d.monthlyRatePpm)}',
                'pago pela conta ${d.accountName}',
              ].join(' • '),
              leading: IconButton(onPressed: () => context.go('/dividas'), icon: const Icon(Symbols.arrow_back)),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    KpiTile('Saldo devedor', s.outstandingPrincipalCents, icon: Symbols.account_balance),
                    KpiTile('Falta pagar', s.remainingTotalCents, icon: Symbols.event_upcoming),
                    KpiTile(
                      'Juros já pagos',
                      s.paidInterestCents,
                      icon: Symbols.percent,
                      color: HoinkColors.tertiaryContainer,
                    ),
                    KpiTile('Valor financiado', d.principalCents, icon: Symbols.payments),
                  ],
                ),
                const SizedBox(height: 16),
                HoinkCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProgressRail(value: s.progressBps / 10000, height: 8),
                      const SizedBox(height: 8),
                      Text(
                        '${formatPercentBps(s.progressBps)} do principal quitado • ${s.paidInstallments} parcelas pagas, ${s.remainingInstallments} restantes',
                        style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                      ),
                      const Divider(height: 24),
                      ValueRow('Principal amortizado', s.paidPrincipalCents),
                      ValueRow('Juros pagos', s.paidInterestCents),
                      ValueRow('Encargos pagos', s.paidFeesCents),
                      ValueRow('Multas e juros de mora', s.paidPenaltiesCents),
                      if (active) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (next != null && next.transactionId != null)
                              FilledButton.icon(
                                key: const Key('pay-installment'),
                                onPressed: () => _payInstallment(context, ref, d, next),
                                icon: const Icon(Symbols.payments, size: 18),
                                label: Text('Pagar parcela ${next.number ?? ''}'),
                              ),
                            OutlinedButton.icon(
                              key: const Key('prepay-debt'),
                              onPressed: () => _prepay(context, ref, d),
                              icon: const Icon(Symbols.trending_down, size: 18),
                              label: const Text('Amortizar'),
                            ),
                            OutlinedButton.icon(
                              key: const Key('payoff-debt'),
                              onPressed: () => _payoff(context, ref, d),
                              icon: const Icon(Symbols.task_alt, size: 18),
                              label: const Text('Simular quitação'),
                            ),
                            TextButton(
                              onPressed: () => _cancel(context, ref, d),
                              child: const Text('Cancelar cadastro'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionTitle('Cronograma', eyebrow: '${d.installments.length} lançamentos'),
                const SizedBox(height: 8),
                HoinkCard(
                  padding: const EdgeInsets.all(8),
                  child: _ScheduleTable(
                    rows: [
                      for (final i in d.installments)
                        (
                          i.number,
                          i.dueDate,
                          i.principalCents,
                          i.interestCents,
                          i.feesCents,
                          i.state == 'PAID' && !i.paidBeforeApp ? i.paidCents : i.totalCents,
                          i.kind == 'REGULAR'
                              ? _StatePill(i.state)
                              : Pill(i.kind == 'EXTRA' ? 'Amortização' : 'Quitação', icon: Symbols.bolt),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }

  Future<void> _payInstallment(BuildContext context, WidgetRef ref, Debt d, DebtInstallment i) async {
    final penalty = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Pagar parcela ${i.number}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueRow('Principal', i.principalCents),
                ValueRow('Juros', i.interestCents),
                if (i.feesCents > 0) ValueRow('Encargos', i.feesCents),
                ValueRow('Parcela', i.totalCents, bold: true),
                const SizedBox(height: 12),
                MoneyField(
                  controller: penalty,
                  label: 'Multa e juros de mora (se houver)',
                  helper: 'Some aqui o que foi cobrado a mais por atraso.',
                ),
                const SizedBox(height: 12),
                DateField(label: 'Pago em', value: date, onChanged: (v) => setState(() => date = v)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar pagamento')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final extra = penalty.text.trim().isEmpty ? 0 : parseBRLToCents(penalty.text);
    if (extra == null || extra < 0) return showError(context, 'Valor de multa inválido');
    await runAction(
      context,
      ref,
      () => ref
          .read(repositoryProvider)
          .settle(d.entityId, i.transactionId!, isoDate(date), finalAmountCents: i.totalCents + extra),
      'Parcela paga',
    );
  }

  Future<void> _prepay(BuildContext context, WidgetRef ref, Debt d) async {
    final amount = TextEditingController();
    var mode = 'REDUCE_TERM';
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Amortização extraordinária'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Saldo devedor: ${formatBRL(d.summary.outstandingPrincipalCents)}', style: HoinkText.bodyMd),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Valor a amortizar', fieldKey: const Key('prepay-amount')),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: mode,
                  onChanged: (v) => setState(() => mode = v!),
                  child: const Column(
                    children: [
                      RadioListTile(
                        value: 'REDUCE_TERM',
                        title: Text('Reduzir o prazo'),
                        subtitle: Text('Mantém a parcela e termina antes (economiza mais juros).'),
                      ),
                      RadioListTile(
                        value: 'REDUCE_INSTALLMENT',
                        title: Text('Reduzir a parcela'),
                        subtitle: Text('Mantém o prazo com parcelas menores.'),
                      ),
                    ],
                  ),
                ),
                DateField(label: 'Data', value: date, onChanged: (v) => setState(() => date = v)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Amortizar')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final cents = parseBRLToCents(amount.text);
    if (cents == null || cents <= 0) return showError(context, 'Informe o valor');
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).prepayDebt(d.entityId, d.id, {
        'amountCents': cents,
        'mode': mode,
        'date': isoDate(date),
      }),
      'Amortização registrada e parcelas recalculadas',
    );
  }

  Future<void> _payoff(BuildContext context, WidgetRef ref, Debt d) async {
    var date = DateTime.now();
    final repo = ref.read(repositoryProvider);
    PayoffQuote? quote;
    Object? error;
    Future<void> load(void Function(void Function()) setState) async {
      try {
        final q = await repo.payoffQuote(d.entityId, d.id, isoDate(date));
        setState(() => (quote, error) = (q, null));
      } catch (e) {
        setState(() => error = e);
      }
    }

    var started = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          if (!started) {
            started = true;
            load(setState);
          }
          final q = quote;
          return AlertDialog(
            title: const Text('Quitação antecipada'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DateField(
                    label: 'Quitar em',
                    value: date,
                    onChanged: (v) {
                      setState(() => (date, quote) = (v, null));
                      load(setState);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (error != null)
                    Text(error.toString(), style: HoinkText.bodyMd.copyWith(color: HoinkColors.error))
                  else if (q == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    if (q.overdueCents > 0) ValueRow('Parcelas vencidas', q.overdueCents),
                    ValueRow('Saldo devedor', q.outstandingPrincipalCents),
                    ValueRow('Juros proporcionais até a data', q.accruedInterestCents),
                    ValueRow('Valor para quitar', q.payoffCents, bold: true),
                    const Divider(height: 20),
                    ValueRow('Se pagar até o fim', q.remainingTotalCents),
                    ValueRow('Economia', q.savingsCents, bold: true, color: HoinkColors.surfaceTint),
                    const SizedBox(height: 8),
                    Text(
                      'Juros futuros são descontados na quitação antecipada (CDC, art. 52). Confirme o valor com o credor.',
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fechar')),
              FilledButton(
                onPressed: q == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('Registrar quitação'),
              ),
            ],
          );
        },
      ),
    );
    if (confirm != true || !context.mounted) return;
    await runAction(context, ref, () => repo.payoffDebt(d.entityId, d.id, isoDate(date)), 'Dívida quitada');
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Debt d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar o cadastro?'),
        content: const Text(
          'As parcelas em aberto deixam de aparecer em Contas a pagar. Os pagamentos já registrados continuam no histórico.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar cadastro')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).cancelDebt(d.entityId, d.id),
      'Cadastro cancelado',
    );
  }
}
