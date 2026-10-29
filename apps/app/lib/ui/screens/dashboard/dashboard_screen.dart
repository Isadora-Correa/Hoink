import 'package:fl_chart/fl_chart.dart';
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
import '../../widgets/icons.dart';
import '../../widgets/transaction_tile.dart';

String _greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
}

const _chartColors = [
  HoinkColors.pine,
  HoinkColors.pigPink,
  Color(0xFF5E6B66),
  HoinkColors.primaryFixedDim,
  HoinkColors.tertiaryContainer,
  HoinkColors.outlineVariant,
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    return RefreshIndicator(
      onRefresh: () async => ref.read(dataVersionProvider.notifier).bump(),
      child: dash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(dashboardProvider)),
        data: (d) => wide ? _DesktopDashboard(d) : _MobileDashboard(d),
      ),
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome(this.d);
  final Dashboard d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final scope = ref.watch(effectiveScopeProvider);
    final mode = switch (scope) {
      Scope.personal => 'Modo Pessoal',
      Scope.business => 'Modo Profissional',
      Scope.total => 'Visão Consolidada',
    };
    return HoinkCard(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_greeting()}, ${user?.firstName ?? ''}!',
                style: HoinkText.headlineLg.copyWith(color: HoinkColors.primary),
              ),
              const SizedBox(height: 4),
              Text(
                'Seu fluxo de caixa sob controle neste mês. Seu dinheiro, do seu jeito.',
                style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              Pill(monthLabel(d.month), dot: HoinkColors.primaryFixedDim),
              Pill(
                mode,
                icon: Symbols.person,
                background: HoinkColors.tertiaryFixed,
                foreground: HoinkColors.onTertiaryFixed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceHero extends ConsumerWidget {
  const _BalanceHero(this.d, {this.mobile = false});
  final Dashboard d;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideValuesProvider);
    final active = d.accounts.where((a) => !a.archived).length;
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                d.scope == 'consolidated' ? 'SALDO CONSOLIDADO' : 'SALDO EM CONTAS',
                style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer, letterSpacing: 1.2),
              ),
              InkResponse(
                onTap: () => ref.read(hideValuesProvider.notifier).toggle(),
                child: Icon(
                  hidden ? Symbols.visibility_off : Symbols.visibility,
                  size: 18,
                  color: HoinkColors.onPrimaryContainer,
                  semanticLabel: hidden ? 'Mostrar valores' : 'Ocultar valores',
                ),
              ),
              Pill(
                '${formatBRL(d.realized.netCents, signed: true)} no mês',
                icon: d.realized.netCents >= 0 ? Symbols.trending_up : Symbols.trending_down,
                background: d.realized.netCents >= 0 ? HoinkColors.primaryFixed : HoinkColors.tertiaryFixed,
                foreground: d.realized.netCents >= 0 ? HoinkColors.primary : HoinkColors.onTertiaryFixed,
              ),
            ],
          ),
          const SizedBox(height: 12),
          MoneyText(
            d.totalBalanceCents,
            hidden: hidden,
            style: (mobile ? HoinkText.currencyDisplayMobile : HoinkText.currencyDisplay).copyWith(
              fontSize: mobile ? 30 : 40,
            ),
            color: Colors.white,
          ),
          const SizedBox(height: 4),
          Text(
            d.scope == 'consolidated'
                ? 'Soma dos seus ambientes, ponderada pela sua participação'
                : '$active ${active == 1 ? 'conta ativa' : 'contas ativas'} • saldo calculado pelas movimentações liquidadas',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  icon: Symbols.arrow_downward,
                  label: 'Entradas',
                  cents: d.realized.incomeCents,
                  hidden: hidden,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  icon: Symbols.arrow_upward,
                  label: 'Saídas',
                  cents: d.realized.expenseCents,
                  hidden: hidden,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  icon: Symbols.schedule,
                  label: 'A pagar',
                  cents: d.forecast.expenseCents,
                  hidden: hidden,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.label, required this.cents, required this.hidden});
  final IconData icon;
  final String label;
  final int cents;
  final bool hidden;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: HoinkColors.primaryFixedDim),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      MoneyText(cents, hidden: hidden, style: HoinkText.headlineSm, color: Colors.white),
    ],
  );
}

class _KpiCard extends ConsumerWidget {
  const _KpiCard({
    required this.label,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.cents,
    required this.caption,
    this.progress,
    this.progressColor = HoinkColors.surfaceTint,
  });
  final String label;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final int cents;
  final String caption;
  final double? progress;
  final Color progressColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideValuesProvider);
    return HoinkCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurfaceVariant)),
              ),
              IconBadge(icon, background: iconBg, foreground: iconFg, size: 32, radius: 10),
            ],
          ),
          const SizedBox(height: 16),
          MoneyText(cents, hidden: hidden, style: HoinkText.headlineLg),
          const SizedBox(height: 4),
          Text(caption, style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
          if (progress != null) ...[const SizedBox(height: 14), ProgressRail(value: progress!, color: progressColor)],
        ],
      ),
    );
  }
}

List<Widget> _kpis(Dashboard d) => [
  _KpiCard(
    label: 'Entradas do Mês',
    icon: Symbols.arrow_downward,
    iconBg: HoinkColors.surfaceContainer,
    iconFg: HoinkColors.surfaceTint,
    cents: d.realized.incomeCents,
    caption: d.forecast.incomeCents > 0 ? '+ ${formatBRL(d.forecast.incomeCents)} previstos' : 'Receitas confirmadas',
    progress: d.realized.incomeCents + d.forecast.incomeCents == 0
        ? 0
        : d.realized.incomeCents / (d.realized.incomeCents + d.forecast.incomeCents),
  ),
  _KpiCard(
    label: 'Despesas do Mês',
    icon: Symbols.arrow_upward,
    iconBg: HoinkColors.errorContainer,
    iconFg: HoinkColors.onErrorContainer,
    cents: d.realized.expenseCents,
    caption: d.realized.incomeCents > 0
        ? '${formatPercentBps((d.realized.expenseCents * 10000 / d.realized.incomeCents).round())} das entradas'
        : 'Despesas realizadas',
    progress: d.realized.incomeCents == 0 ? 0 : d.realized.expenseCents / d.realized.incomeCents,
    progressColor: HoinkColors.error,
  ),
  _KpiCard(
    label: 'Contas a Pagar',
    icon: Symbols.schedule,
    iconBg: HoinkColors.tertiaryFixed,
    iconFg: HoinkColors.tertiaryContainer,
    cents: d.forecast.expenseCents + d.overdue.expenseCents,
    caption: d.overdue.count > 0
        ? '${d.overdue.count} em atraso • ${formatBRL(d.overdue.expenseCents)}'
        : 'Nenhuma conta em atraso',
  ),
];

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart(this.d);
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final maxY = d.series.fold<int>(1, (m, s) => [m, s.incomeCents, s.expenseCents].reduce((a, b) => a > b ? a : b));
    return HoinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Evolução do seu dinheiro',
            eyebrow: 'Fluxo de caixa',
            trailing: Wrap(
              spacing: 12,
              children: const [
                _Legend(color: HoinkColors.pine, label: 'Entradas'),
                _Legend(color: HoinkColors.tertiaryFixedDim, label: 'Saídas'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: PrivacyBlur(
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.15,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 3,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: HoinkColors.surfaceHigh, strokeWidth: 1, dashArray: [4, 4]),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) {
                          final s = d.series[v.toInt()];
                          final current = s.month == d.month;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              monthShort(s.month),
                              style: HoinkText.bodySm.copyWith(
                                color: current ? HoinkColors.primary : HoinkColors.onSurfaceVariant,
                                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => HoinkColors.charcoal,
                      getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                        '${rodIndex == 0 ? 'Entradas' : 'Saídas'}\n${formatBRL(rod.toY.round())}',
                        HoinkText.bodySm.copyWith(color: HoinkColors.ivory),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < d.series.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: d.series[i].incomeCents.toDouble(),
                            width: 16,
                            color: HoinkColors.pine,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                          BarChartRodData(
                            toY: d.series[i].expenseCents.toDouble(),
                            width: 16,
                            color: HoinkColors.tertiaryFixedDim,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HoinkColors.surfaceLow,
              borderRadius: BorderRadius.circular(HoinkRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Symbols.insights, size: 18, color: HoinkColors.surfaceTint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Resultado acumulado em 6 meses: '),
                        TextSpan(
                          text: formatBRL(d.series.fold(0, (s, p) => s + p.netCents), signed: true),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    style: HoinkText.bodySm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label, style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
    ],
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard(this.d);
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final cats = d.expensesByCategory;
    final top = cats.take(5).toList();
    return HoinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Gastos por categoria', style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary)),
              ),
              Text('Este mês', style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          if (cats.isEmpty)
            Text(
              'Nenhuma despesa liquidada neste mês.',
              style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
            )
          else ...[
            SizedBox(
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PrivacyBlur(
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 52,
                        sectionsSpace: 2,
                        sections: [
                          for (var i = 0; i < top.length; i++)
                            PieChartSectionData(
                              value: top[i].cents.toDouble(),
                              color: _chartColors[i % _chartColors.length],
                              radius: 22,
                              showTitle: false,
                            ),
                          if (cats.length > 5)
                            PieChartSectionData(
                              value: cats.skip(5).fold<int>(0, (s, c) => s + c.cents).toDouble(),
                              color: HoinkColors.surfaceHighest,
                              radius: 22,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total', style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
                      Text(
                        formatBRL(d.realized.expenseCents),
                        style: HoinkText.labelMd.copyWith(color: HoinkColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    IconBadge(
                      categoryIcon(top[i].icon),
                      size: 32,
                      radius: 10,
                      foreground: _chartColors[i % _chartColors.length] == HoinkColors.pigPink
                          ? HoinkColors.tertiaryContainer
                          : HoinkColors.pine,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(top[i].name, style: HoinkText.labelMd),
                          const SizedBox(height: 4),
                          ProgressRail(
                            value: top[i].shareBps / 10000,
                            color: _chartColors[i % _chartColors.length],
                            height: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatBRL(top[i].cents),
                          style: HoinkText.labelMd.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        Text(
                          formatPercentBps(top[i].shareBps),
                          style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard(this.d);
  final Dashboard d;
  @override
  Widget build(BuildContext context) => HoinkCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Últimos lançamentos',
          trailing: TextButton(onPressed: () => context.go('/lancamentos'), child: const Text('Ver extrato completo')),
        ),
        const SizedBox(height: 8),
        if (d.recent.isEmpty)
          EmptyState(
            title: 'Nenhum lançamento ainda',
            message: 'Registre sua primeira receita ou despesa.',
            action: FilledButton(
              onPressed: () => context.push('/lancamentos/novo'),
              child: const Text('Novo lançamento'),
            ),
          )
        else
          for (final t in d.recent) ...[
            TransactionTile(t, onTap: () => t.isTransfer ? null : context.push('/lancamentos/${t.entityId}/${t.id}')),
            if (t != d.recent.last) const Divider(),
          ],
      ],
    ),
  );
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard(this.d);
  final Dashboard d;
  @override
  Widget build(BuildContext context) {
    if (d.upcoming.isEmpty && d.overdue.count == 0) return const SizedBox.shrink();
    return HoinkCard(
      color: const Color(0xFFFFF7F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.event_upcoming, color: HoinkColors.tertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Próximos 7 dias', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
              ),
              if (d.overdue.count > 0) StatusPill('OVERDUE'),
            ],
          ),
          if (d.overdue.count > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${d.overdue.count} lançamento(s) em atraso. Total em aberto: ${formatBRL(d.overdue.expenseCents + d.overdue.incomeCents)}.',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onErrorContainer),
              ),
            ),
          const SizedBox(height: 8),
          for (final t in d.upcoming)
            TransactionTile(t, onTap: () => context.push('/lancamentos/${t.entityId}/${t.id}')),
        ],
      ),
    );
  }
}

class _AccountsCard extends ConsumerWidget {
  const _AccountsCard(this.d);
  final Dashboard d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideValuesProvider);
    final accounts = d.accounts.where((a) => !a.archived).toList();
    return HoinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.account_balance, color: HoinkColors.pine),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Minhas contas', style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary)),
              ),
              TextButton.icon(
                onPressed: () => context.go('/contas'),
                icon: const Icon(Symbols.add_circle, size: 18),
                label: const Text('Gerenciar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (accounts.isEmpty)
            Text(
              'Cadastre uma conta para começar.',
              style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
          for (final a in accounts)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HoinkColors.surfaceLow,
                borderRadius: BorderRadius.circular(HoinkRadius.md),
              ),
              child: InkWell(
                onTap: () => context.go('/contas/${a.entityId}/${a.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name, style: HoinkText.labelMd),
                          Text(
                            a.institution ?? accountTypeLabels[a.type]!,
                            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    MoneyText(a.balanceCents, hidden: hidden, style: HoinkText.labelMd.copyWith(fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntitiesCard extends ConsumerWidget {
  const _EntitiesCard(this.d);
  final Dashboard d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (d.entities.isEmpty) return const SizedBox.shrink();
    final hidden = ref.watch(hideValuesProvider);
    return HoinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Composição do consolidado', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
          const SizedBox(height: 4),
          Text(
            'Transferências entre ambientes não contam como receita nem despesa.',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final e in d.entities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  IconBadge(e.kind == 'PERSONAL' ? Symbols.person : Symbols.business_center, size: 32, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: HoinkText.labelMd),
                        Text(
                          'Participação: ${formatPercentBps(e.ownershipShareBps)}',
                          style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  MoneyText(
                    e.attributableBalanceCents,
                    hidden: hidden,
                    style: HoinkText.labelMd.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard(this.d);
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 24, width: 24);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Welcome(d),
                gap,
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: _BalanceHero(d)),
                      for (final k in _kpis(d)) ...[const SizedBox(width: 16), Expanded(child: k)],
                    ],
                  ),
                ),
                gap,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 8, child: Column(children: [_CashFlowChart(d), gap, _RecentCard(d)])),
                    gap,
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          if (d.scope == 'consolidated') ...[_EntitiesCard(d), gap],
                          _UpcomingCard(d),
                          if (d.upcoming.isNotEmpty || d.overdue.count > 0) gap,
                          _AccountsCard(d),
                          gap,
                          _CategoryCard(d),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard(this.d);
  final Dashboard d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    const gap = SizedBox(height: 16);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text('Olá, ${user?.firstName ?? ''}!', style: HoinkText.headlineLgMobile.copyWith(color: HoinkColors.primary)),
        Text('Seu dinheiro, do seu jeito.', style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: MonthPicker()),
        gap,
        _BalanceHero(d, mobile: true),
        gap,
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Symbols.arrow_downward,
                label: 'Entrada',
                bg: HoinkColors.mint,
                onTap: () => context.push('/lancamentos/novo?tipo=INCOME'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Symbols.arrow_upward,
                label: 'Saída',
                bg: HoinkColors.pigPink,
                onTap: () => context.push('/lancamentos/novo?tipo=EXPENSE'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Symbols.sync_alt,
                label: 'Transferir',
                bg: HoinkColors.primaryFixed,
                onTap: () => context.push('/lancamentos/novo?tipo=TRANSFER'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Symbols.account_balance,
                label: 'Contas',
                bg: HoinkColors.surfaceContainer,
                onTap: () => context.go('/contas'),
              ),
            ),
          ],
        ),
        gap,
        if (d.scope == 'consolidated') ...[_EntitiesCard(d), gap],
        _UpcomingCard(d),
        if (d.upcoming.isNotEmpty || d.overdue.count > 0) gap,
        _CashFlowChart(d),
        gap,
        _CategoryCard(d),
        gap,
        _RecentCard(d),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.bg, required this.onTap});
  final IconData icon;
  final String label;
  final Color bg;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HoinkCard(
    padding: const EdgeInsets.symmetric(vertical: 14),
    onTap: onTap,
    child: Column(
      children: [
        IconBadge(icon, background: bg, foreground: HoinkColors.pine, size: 40, radius: 20),
        const SizedBox(height: 6),
        Text(label, style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurface)),
      ],
    ),
  );
}
