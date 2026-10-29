import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../shell/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';
import '../../widgets/page.dart';

/// Projeção do ambiente atual (ou consolidada quando o escopo é Total).
final cashflowProvider = FutureProvider<Cashflow>((ref) async {
  ref.watch(dataVersionProvider);
  await ref.watch(entitiesProvider.future);
  final entity = ref.watch(currentEntityProvider);
  return ref.read(repositoryProvider).cashflow(entityId: entity?.id);
});

final budgetsProvider = FutureProvider.family<BudgetsPage, ({String entityId, String month})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).budgets(a.entityId, a.month);
});

final reserveProvider = FutureProvider.family<EmergencyReserve, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).reserve(entityId);
});

/// Planejamento: fluxo de caixa projetado (30/60/90 dias), orçamentos por categoria e reserva de emergência.
class PlanningScreen extends ConsumerWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = ref.watch(currentEntityProvider);
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    return ModulePage(
      title: 'Planejamento',
      subtitle: 'Para onde o seu caixa vai nos próximos meses, quanto ainda cabe no orçamento e como está sua reserva.',
      maxWidth: 1200,
      children: [
        const _CashflowSection(),
        const SizedBox(height: 28),
        if (entity == null)
          HoinkCard(
            child: Text(
              'Orçamentos e reserva de emergência são definidos por ambiente. Escolha Pessoal ou Pro no topo para vê-los.',
              style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
          )
        else if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _BudgetsSection(entity: entity)),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _ReserveSection(entity: entity)),
            ],
          )
        else ...[
          _BudgetsSection(entity: entity),
          const SizedBox(height: 28),
          _ReserveSection(entity: entity),
        ],
      ],
    );
  }
}

class _CashflowSection extends ConsumerStatefulWidget {
  const _CashflowSection();
  @override
  ConsumerState<_CashflowSection> createState() => _CashflowSectionState();
}

class _CashflowSectionState extends ConsumerState<_CashflowSection> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Fluxo de caixa projetado',
          eyebrow: 'Previsão',
          trailing: SegmentedButton<int>(
            key: const Key('cashflow-horizon'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: HoinkColors.pine,
              selectedForegroundColor: HoinkColors.ivory,
            ),
            segments: const [
              ButtonSegment(value: 30, label: Text('30 dias')),
              ButtonSegment(value: 60, label: Text('60 dias')),
              ButtonSegment(value: 90, label: Text('90 dias')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
        ),
        const SizedBox(height: 12),
        ref
            .watch(cashflowProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(cashflowProvider)),
              data: (cf) {
                final h = cf.horizons.firstWhere((x) => x.days == _days, orElse: () => cf.horizons.first);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cf.alerts.isNotEmpty) ...[AlertBanner(cf.alerts), const SizedBox(height: 12)],
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        KpiTile('Saldo hoje', cf.startBalanceCents, icon: Symbols.account_balance_wallet),
                        KpiTile(
                          'Só confirmado',
                          h.endBalanceConfirmedCents,
                          icon: Symbols.verified,
                          caption: 'em ${formatBrDate(h.until)}',
                        ),
                        KpiTile(
                          'Com previstos',
                          h.endBalanceProjectedCents,
                          icon: Symbols.query_stats,
                          color: HoinkColors.surfaceTint,
                          caption: 'em ${formatBrDate(h.until)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) {
                        final chart = HoinkCard(
                          padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                          child: _CashChart(points: cf.points.take(_days + 1).toList()),
                        );
                        final table = HoinkCard(padding: const EdgeInsets.all(20), child: _HorizonTable(h));
                        if (c.maxWidth < 760) return Column(children: [chart, const SizedBox(height: 12), table]);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: chart),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: table),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
      ],
    );
  }
}

class _HorizonTable extends StatelessWidget {
  const _HorizonTable(this.h);
  final CashHorizon h;

  @override
  Widget build(BuildContext context) {
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(t.toUpperCase(), style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Próximos ${h.days} dias', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
        head('Receitas'),
        ValueRow('Confirmadas', h.incomeConfirmedCents),
        ValueRow('Previstas', h.incomePlannedCents, color: HoinkColors.onSurfaceVariant),
        head('Despesas'),
        ValueRow('Confirmadas', h.expenseConfirmedCents),
        ValueRow('Previstas', h.expensePlannedCents, color: HoinkColors.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(
          'Confirmado: cobranças e contas lançadas, faturas de cartão e parcelas de dívidas. '
          'Previsto: ocorrências de recorrências e valores estimados.',
          style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CashChart extends StatelessWidget {
  const _CashChart({required this.points});
  final List<CashPoint> points;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final p in points) ...[p.confirmedCents, p.projectedCents],
    ];
    final minV = values.reduce((a, b) => a < b ? a : b).toDouble();
    final maxV = values.reduce((a, b) => a > b ? a : b).toDouble();
    final pad = ((maxV - minV).abs() * 0.15).clamp(10000, double.infinity);
    final step = (points.length / 4).ceilToDouble();
    LineChartBarData line(List<int> ys, Color color, {bool dashed = false}) => LineChartBarData(
      spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i].toDouble())],
      isCurved: false,
      color: color,
      barWidth: 2.5,
      dashArray: dashed ? [6, 4] : null,
      dotData: const FlDotData(show: false),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 16,
          children: [
            _Legend(color: HoinkColors.pine, label: 'Só confirmado'),
            _Legend(color: HoinkColors.pigPink, label: 'Com previstos', dashed: true),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: PrivacyBlur(
            child: LineChart(
              LineChartData(
                minY: minV - pad,
                maxY: maxV + pad,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: HoinkColors.surfaceHigh, strokeWidth: 1, dashArray: [4, 4]),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (minV < 0) HorizontalLine(y: 0, color: HoinkColors.error.withValues(alpha: 0.5), strokeWidth: 1),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (v, meta) => v == meta.max || v == meta.min
                          ? const SizedBox()
                          : Text(_compact(v), style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: step,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox();
                        final d = parseIso(points[i].date);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => HoinkColors.charcoal,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${s.barIndex == 0 ? formatBrDate(points[s.x.toInt()].date) : ''}${s.barIndex == 0 ? '\n' : ''}'
                          '${s.barIndex == 0 ? 'Confirmado' : 'Com previstos'}: ${formatBRL(s.y.round())}',
                          HoinkText.bodySm.copyWith(color: HoinkColors.ivory),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  line([for (final p in points) p.confirmedCents], HoinkColors.pine),
                  line([for (final p in points) p.projectedCents], HoinkColors.pigPink, dashed: true),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _compact(double cents) {
    if (Privacy.hidden) return '••';
    final v = cents / 100;
    if (v.abs() >= 1000) return 'R\$ ${(v / 1000).toStringAsFixed(v.abs() >= 10000 ? 0 : 1).replaceAll('.', ',')} mil';
    return 'R\$ ${v.toStringAsFixed(0)}';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 3,
        decoration: BoxDecoration(
          color: dashed ? null : color,
          border: dashed ? Border(top: BorderSide(color: color, width: 3)) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: HoinkText.bodySm),
    ],
  );
}

class _BudgetsSection extends ConsumerWidget {
  const _BudgetsSection({required this.entity});
  final FinancialEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final budgets = ref.watch(budgetsProvider((entityId: entity.id, month: month)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Orçamentos de ${monthLabel(month).toLowerCase()}',
          eyebrow: 'Limites por categoria',
          trailing: entity.canWrite
              ? TextButton.icon(
                  key: const Key('new-budget'),
                  onPressed: () => showBudgetForm(context, ref, entity.id),
                  icon: const Icon(Symbols.add, size: 18),
                  label: const Text('Orçamento'),
                )
              : null,
        ),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: MonthPicker()),
        const SizedBox(height: 12),
        budgets.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorState(e),
          data: (page) {
            if (page.items.isEmpty) {
              return HoinkCard(
                child: EmptyState(
                  title: 'Nenhum orçamento',
                  message: 'Defina quanto quer gastar por mês em mercado, lazer ou transporte e receba alertas.',
                  action: entity.canWrite
                      ? FilledButton(
                          onPressed: () => showBudgetForm(context, ref, entity.id),
                          child: const Text('Criar orçamento'),
                        )
                      : null,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.alerts.isNotEmpty) ...[AlertBanner(page.alerts), const SizedBox(height: 12)],
                HoinkCard(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    children: [
                      for (final b in page.items) ...[
                        _BudgetRow(entityId: entity.id, budget: b),
                        if (b != page.items.last) const Divider(height: 1),
                      ],
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ValueRow(
                          'Gasto ${formatBRL(page.spentCents)} de ${formatBRL(page.limitCents)}',
                          page.limitCents - page.spentCents,
                          bold: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.entityId, required this.budget});
  final String entityId;
  final BudgetItem budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = budget;
    final color = switch (b.state) {
      'EXCEEDED' => HoinkColors.error,
      'WARNING' => HoinkColors.tertiaryContainer,
      _ => HoinkColors.pine,
    };
    return InkWell(
      onTap: () => showBudgetForm(context, ref, entityId, budget: b),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(categoryIcon(b.categoryIcon), size: 32, radius: 10),
                const SizedBox(width: 10),
                Expanded(child: Text(b.categoryName, style: HoinkText.labelMd)),
                Text(
                  '${formatBRL(b.spentCents)} / ${formatBRL(b.limitCents)}',
                  style: HoinkText.labelMd.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressRail(value: b.usedBps / 10000, color: color),
            const SizedBox(height: 4),
            Text(
              [
                b.remainingCents >= 0
                    ? 'Restam ${formatBRL(b.remainingCents)}'
                    : 'Passou ${formatBRL(-b.remainingCents)} do limite',
                if (b.committedCents > 0) '${formatBRL(b.committedCents)} em contas a vencer',
              ].join(' • '),
              style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cria ou altera o orçamento de uma categoria de despesa.
Future<void> showBudgetForm(BuildContext context, WidgetRef ref, String entityId, {BudgetItem? budget}) async {
  final categories = (await ref.read(categoriesProvider(entityId).future)).where((c) => c.kind == 'EXPENSE').toList();
  if (!context.mounted) return;
  final limit = TextEditingController(text: budget == null ? '' : formatAmount(budget.limitCents));
  var categoryId = budget?.categoryId ?? categories.firstOrNull?.id;
  var threshold = (budget?.alertThresholdBps ?? 8000) / 100;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(budget == null ? 'Novo orçamento' : 'Orçamento de ${budget.categoryName}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (budget == null)
                DropdownButtonFormField<String>(
                  key: const Key('budget-category'),
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
              const SizedBox(height: 12),
              MoneyField(controller: limit, label: 'Limite mensal', fieldKey: const Key('budget-limit')),
              const SizedBox(height: 16),
              Text('Avisar ao atingir ${threshold.round()}% do limite', style: HoinkText.bodyMd),
              Slider(
                value: threshold,
                min: 10,
                max: 100,
                divisions: 18,
                label: '${threshold.round()}%',
                onChanged: (v) => setState(() => threshold = v),
              ),
            ],
          ),
        ),
        actions: [
          if (budget != null)
            TextButton(
              onPressed: () async {
                final ok = await runAction(
                  ctx,
                  ref,
                  () => ref.read(repositoryProvider).deleteBudget(entityId, budget.id),
                  'Orçamento removido',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Remover'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('save-budget'),
            onPressed: () async {
              final cents = parseBRLToCents(limit.text);
              if (categoryId == null || cents == null || cents <= 0) {
                showError(ctx, 'Escolha a categoria e informe o limite');
                return;
              }
              final ok = await runAction(
                ctx,
                ref,
                () => ref.read(repositoryProvider).saveBudget(entityId, categoryId!, cents, (threshold * 100).round()),
                'Orçamento salvo',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

class _ReserveSection extends ConsumerWidget {
  const _ReserveSection({required this.entity});
  final FinancialEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Reserva de emergência',
          eyebrow: 'Segurança',
          trailing: entity.canWrite
              ? IconButton(
                  tooltip: 'Configurar reserva',
                  onPressed: () => _configure(context, ref),
                  icon: const Icon(Symbols.tune),
                )
              : null,
        ),
        const SizedBox(height: 12),
        ref
            .watch(reserveProvider(entity.id))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorState(e),
              data: (r) => HeroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GUARDADO',
                      style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer, letterSpacing: 1),
                    ),
                    MoneyText(r.currentCents, style: HoinkText.headlineLg, color: Colors.white),
                    const SizedBox(height: 12),
                    ProgressRail(
                      value: r.progressBps / 10000,
                      color: HoinkColors.mint,
                      track: const Color(0x33FFFFFF),
                      height: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      r.targetCents > 0
                          ? 'Meta: ${formatBRL(r.targetCents)} (${r.targetMonths} meses de despesas)'
                          : 'Lance suas despesas para calcularmos a meta da reserva.',
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.primaryFixedDim),
                    ),
                    if (r.monthsCovered != null)
                      Text(
                        'Cobre ${r.monthsCovered!.toStringAsFixed(1).replaceAll('.', ',')} meses • média de ${formatBRL(r.avgMonthlyExpenseCents)}/mês',
                        style: HoinkText.bodySm.copyWith(color: HoinkColors.primaryFixedDim),
                      ),
                    if (r.missingCents > 0)
                      Text(
                        'Faltam ${formatBRL(r.missingCents)}',
                        style: HoinkText.labelMd.copyWith(color: HoinkColors.pigPink),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      r.accounts.isEmpty
                          ? 'Nenhuma conta na reserva. Toque em configurar para escolher.'
                          : '${r.customAccounts ? 'Contas' : 'Poupanças'}: ${r.accounts.map((a) => a.name).join(', ')}',
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.ivory),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _configure(BuildContext context, WidgetRef ref) async {
    final accounts = (await ref.read(accountsProvider(entity.id).future)).where((a) => !a.archived).toList();
    final current = await ref.read(reserveProvider(entity.id).future);
    if (!context.mounted) return;
    var months = current.targetMonths.toDouble();
    final selected = {for (final a in current.accounts) a.id};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reserva de emergência'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Meta: ${months.round()} meses de despesas', style: HoinkText.bodyMd),
                Slider(
                  value: months,
                  min: 1,
                  max: 24,
                  divisions: 23,
                  label: '${months.round()}',
                  onChanged: (v) => setState(() => months = v),
                ),
                const SizedBox(height: 8),
                Text('Contas que formam a reserva', style: HoinkText.labelMd),
                for (final a in accounts)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(a.id),
                    title: Text(a.name),
                    subtitle: Text(formatBRL(a.balanceCents)),
                    onChanged: (v) => setState(() => v! ? selected.add(a.id) : selected.remove(a.id)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final ok = await runAction(
                  ctx,
                  ref,
                  () => ref.read(repositoryProvider).saveReserve(entity.id, months.round(), selected.toList()),
                  'Reserva atualizada',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
