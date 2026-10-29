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
import '../../widgets/common.dart';
import '../../widgets/page.dart';

final investmentsProvider = FutureProvider.family<List<Investment>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).investments(entityId);
});

final investmentProvider = FutureProvider.family<Investment, ({String entityId, String id})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).investment(a.entityId, a.id);
});

final marketRatesProvider = FutureProvider<List<MarketRateStatus>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).marketRates();
});

String _pct(double v, {int digits = 2}) => '${v.toStringAsFixed(digits).replaceAll('.', ',')}%';

String rateLabel(Investment i) => switch (i.indexer) {
  'CDI_PERCENT' => '${_pct(i.rateBps / 100, digits: 0)} do CDI',
  'SELIC_PERCENT' => 'Selic + ${_pct(i.rateBps / 100, digits: 0)}',
  'PREFIXED' => '${_pct(i.rateBps / 100)} a.a.',
  'IPCA_PLUS' => 'IPCA + ${_pct(i.rateBps / 100)} a.a.',
  'MARKET' => i.ticker ?? 'Cotação de mercado',
  _ => 'Valor informado',
};

String valueSourceLabel(Investment i) => switch (i.valueSource) {
  'ESTIMATED' => 'Estimado pelo índice',
  'INFORMED' => 'Informado em ${formatBrDate(i.valueDate!)}',
  'MARKET_PRICE' => 'Cotação de ${formatBrDate(i.valueDate!)}',
  _ => 'Sem valor atualizado',
};

/// Investimentos: carteira com motor de cálculo por produto, índices do Banco Central e comparação.
class InvestmentsScreen extends ConsumerWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = ref.watch(currentEntityProvider) ?? (ref.watch(entitiesProvider).value ?? const []).firstOrNull;
    if (entity == null) return const Center(child: CircularProgressIndicator());
    return ModulePage(
      title: 'Investimentos',
      subtitle: 'CDB, LCI, LCA, Tesouro, fundos e ações — cada um calculado do jeito certo, sem cotações inventadas.',
      maxWidth: 1200,
      action: entity.canWrite
          ? FilledButton.icon(
              key: const Key('new-investment'),
              onPressed: () => showInvestmentForm(context, ref, entity.id),
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('Novo investimento'),
            )
          : null,
      children: [
        const _MarketBar(),
        const SizedBox(height: 16),
        ref
            .watch(investmentsProvider(entity.id))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorState(e),
              data: (list) {
                if (list.isEmpty) {
                  return HoinkCard(
                    child: EmptyState(
                      title: 'Nenhum investimento',
                      message: 'Cadastre seus investimentos para acompanhar rendimento, vencimentos e patrimônio.',
                      action: FilledButton(
                        onPressed: () => showInvestmentForm(context, ref, entity.id),
                        child: const Text('Cadastrar investimento'),
                      ),
                    ),
                  );
                }
                final total = list.fold<int>(0, (s, i) => s + i.valueCents);
                final principal = list.fold<int>(0, (s, i) => s + i.principalCents);
                final net = list.fold<int>(0, (s, i) => s + i.netEstimatedCents);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        KpiTile('Carteira (bruto)', total, icon: Symbols.account_balance),
                        KpiTile('Aplicado', principal, icon: Symbols.payments),
                        KpiTile('Ganho', total - principal, icon: Symbols.trending_up, color: HoinkColors.surfaceTint),
                        KpiTile('Líquido estimado', net, icon: Symbols.receipt_long, caption: 'após IR/IOF estimados'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    HoinkCard(
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          showCheckboxColumn: false,
                          columnSpacing: 24,
                          columns: const [
                            DataColumn(label: Text('Investimento')),
                            DataColumn(label: Text('Rentabilidade')),
                            DataColumn(label: Text('Aplicado'), numeric: true),
                            DataColumn(label: Text('Valor atual'), numeric: true),
                            DataColumn(label: Text('Retorno'), numeric: true),
                            DataColumn(label: Text('Vencimento')),
                          ],
                          rows: [
                            for (final i in list)
                              DataRow(
                                onSelectChanged: (_) => context.push('/investimentos/${i.entityId}/${i.id}'),
                                cells: [
                                  DataCell(
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(i.name, style: HoinkText.labelMd),
                                        Text(
                                          [i.kindLabel, ?i.institution].join(' • '),
                                          style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(rateLabel(i))),
                                  DataCell(Text(formatBRL(i.principalCents))),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (i.stale)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 4),
                                            child: Tooltip(
                                              message: 'Valor desatualizado: informe a cotação ou o saldo',
                                              child: Icon(
                                                Symbols.schedule,
                                                size: 16,
                                                color: HoinkColors.tertiaryContainer,
                                              ),
                                            ),
                                          ),
                                        Text(formatBRL(i.valueCents), style: HoinkText.labelMd),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      i.returnBps == null ? '—' : formatPercentBps(i.returnBps!),
                                      style: HoinkText.labelMd.copyWith(
                                        color: (i.returnBps ?? 0) >= 0 ? HoinkColors.surfaceTint : HoinkColors.error,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(i.maturityDate == null ? '—' : formatBrDate(i.maturityDate!))),
                                ],
                              ),
                          ],
                        ),
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

/// Situação dos índices (CDI, Selic, IPCA) vindos do Banco Central.
class _MarketBar extends ConsumerWidget {
  const _MarketBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rates = ref.watch(marketRatesProvider).value;
    if (rates == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in rates)
          Pill(
            r.lastDate == null
                ? '${r.index}: sem dados'
                : r.index == 'IPCA'
                ? 'IPCA ${monthShort(r.lastDate!.substring(0, 7))}: ${_pct(r.ratePct ?? 0)}'
                : '${r.index} ${_pct(r.annualPct ?? 0)} a.a. • ${formatBrDate(r.lastDate!)}',
            icon: r.stale ? Symbols.schedule : Symbols.verified,
            background: r.stale ? HoinkColors.tertiaryFixed : HoinkColors.surfaceLow,
            foreground: r.stale ? HoinkColors.onTertiaryFixed : HoinkColors.pine,
          ),
        Text('Fonte: Banco Central (SGS)', style: HoinkText.bodySm.copyWith(color: HoinkColors.outline)),
      ],
    );
  }
}

/// Cadastro de investimento com o aporte inicial.
Future<void> showInvestmentForm(BuildContext context, WidgetRef ref, String entityId) async {
  final accounts = (await ref.read(accountsProvider(entityId).future)).where((a) => !a.archived).toList();
  if (!context.mounted) return;
  final name = TextEditingController();
  final institution = TextEditingController();
  final ticker = TextEditingController();
  final rate = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  var kind = 'CDB';
  var indexer = 'CDI_PERCENT';
  var date = DateTime.now();
  DateTime? maturity;
  String? accountId = accounts.firstOrNull?.id;
  var fromAccount = true;

  const marketKinds = {'STOCK', 'ETF'};
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final market = indexer == 'MARKET';
        return AlertDialog(
          title: const Text('Novo investimento'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      for (final e in investmentKindLabels.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() {
                      kind = v!;
                      if (marketKinds.contains(kind)) indexer = 'MARKET';
                      if (kind == 'FUND' && indexer != 'MARKET') indexer = 'MARKET';
                      if ({'CDB', 'LCI', 'LCA'}.contains(kind) && indexer == 'MARKET') indexer = 'CDI_PERCENT';
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('investment-name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Produto', hintText: 'Ex.: CDB Banco X 110% CDI'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: institution,
                          decoration: const InputDecoration(labelText: 'Instituição'),
                        ),
                      ),
                      if (market) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: ticker,
                            decoration: const InputDecoration(labelText: 'Código (ex.: ITSA4)'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(indexer),
                    initialValue: indexer,
                    decoration: const InputDecoration(labelText: 'Como rende'),
                    items: [
                      for (final e in indexerLabels.entries)
                        if (!marketKinds.contains(kind) || e.key == 'MARKET')
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => indexer = v!),
                  ),
                  if (!market && indexer != 'MANUAL') ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('investment-rate'),
                      controller: rate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: indexer == 'CDI_PERCENT' || indexer == 'SELIC_PERCENT'
                            ? 'Percentual do índice'
                            : 'Taxa ao ano',
                        suffixText: '%',
                        hintText: indexer == 'CDI_PERCENT' ? '110' : '6,5',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  MoneyField(controller: amount, label: 'Valor aplicado', fieldKey: const Key('investment-amount')),
                  if (market) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantity,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Quantidade de cotas/ações'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DateField(label: 'Data da aplicação', value: date, onChanged: (d) => setState(() => date = d)),
                  if (!market) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Symbols.event, size: 18),
                      label: Text(
                        maturity == null ? 'Vencimento (opcional)' : 'Vence em ${formatBrDate(isoDate(maturity!))}',
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: maturity ?? DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => maturity = d);
                      },
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: fromAccount,
                    onChanged: (v) => setState(() => fromAccount = v),
                    title: const Text('O dinheiro saiu de uma conta'),
                    subtitle: const Text('Desligue para investimentos que você já tinha antes da hoink.'),
                  ),
                  if (fromAccount)
                    DropdownButtonFormField<String>(
                      initialValue: accountId,
                      decoration: const InputDecoration(labelText: 'Conta'),
                      items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                      onChanged: (v) => setState(() => accountId = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              key: const Key('save-investment'),
              onPressed: () async {
                final cents = parseBRLToCents(amount.text);
                final rateBps = rate.text.trim().isEmpty
                    ? 0
                    : ((double.tryParse(rate.text.replaceAll(',', '.')) ?? -1) * 100).round();
                final qty = double.tryParse(quantity.text.replaceAll('.', '').replaceAll(',', '.'));
                if (name.text.trim().isEmpty || cents == null || cents <= 0) {
                  return showError(ctx, 'Informe o produto e o valor');
                }
                if (rateBps < 0) return showError(ctx, 'Taxa inválida');
                if (market && (qty == null || qty <= 0)) return showError(ctx, 'Informe a quantidade');
                final ok = await runAction(
                  ctx,
                  ref,
                  () => ref.read(repositoryProvider).createInvestment(entityId, {
                    'kind': kind,
                    'name': name.text.trim(),
                    'institution': institution.text.trim().isEmpty ? null : institution.text.trim(),
                    'ticker': ticker.text.trim().isEmpty ? null : ticker.text.trim(),
                    'indexer': indexer,
                    'rateBps': rateBps,
                    'maturityDate': maturity == null ? null : isoDate(maturity!),
                    'initial': {
                      'date': isoDate(date),
                      'amountCents': cents,
                      'accountId': fromAccount ? accountId : null,
                      'quantity': ?qty,
                    },
                  }),
                  'Investimento cadastrado',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    ),
  );
}

/// Detalhe: valor (estimado × informado), impostos estimados, evolução e movimentações.
class InvestmentDetailScreen extends ConsumerWidget {
  const InvestmentDetailScreen({super.key, required this.entityId, required this.investmentId});
  final String entityId;
  final String investmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(investmentProvider((entityId: entityId, id: investmentId)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e),
          data: (i) => ModulePage(
            title: i.name,
            subtitle: [i.kindLabel, rateLabel(i), ?i.institution].join(' • '),
            leading: IconButton(onPressed: () => context.go('/investimentos'), icon: const Icon(Symbols.arrow_back)),
            children: [
              if (i.stale) ...[
                AlertBanner([
                  i.isMarket
                      ? 'Cotação desatualizada${i.valueDate == null ? '' : ' (de ${formatBrDate(i.valueDate!)})'}. Informe o preço atual — a hoink. não inventa cotações.'
                      : 'Faltam dados recentes do índice${i.ratesUpTo == null ? '' : ' (até ${formatBrDate(i.ratesUpTo!)})'}: usamos a última taxa conhecida.',
                ], icon: Symbols.schedule),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  KpiTile('Valor atual', i.valueCents, icon: Symbols.account_balance, caption: valueSourceLabel(i)),
                  KpiTile('Aplicado', i.principalCents, icon: Symbols.payments),
                  KpiTile('Ganho', i.gainCents, icon: Symbols.trending_up, color: HoinkColors.surfaceTint),
                  KpiTile(
                    'Líquido estimado',
                    i.netEstimatedCents,
                    icon: Symbols.receipt_long,
                    caption: 'IR/IOF: ${formatBRL(i.taxEstimatedCents)}',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _move(context, ref, i, 'contributions'),
                    icon: const Icon(Symbols.add, size: 18),
                    label: const Text('Aportar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _move(context, ref, i, 'redemptions'),
                    icon: const Icon(Symbols.move_up, size: 18),
                    label: const Text('Resgatar'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('update-value'),
                    onPressed: () => _move(context, ref, i, 'value'),
                    icon: const Icon(Symbols.edit_note, size: 18),
                    label: Text(i.isMarket ? 'Atualizar cotação' : 'Informar saldo do extrato'),
                  ),
                  if (i.isMarket || i.kind == 'FUND')
                    TextButton.icon(
                      onPressed: () => _move(context, ref, i, 'income'),
                      icon: const Icon(Symbols.paid, size: 18),
                      label: const Text('Proventos'),
                    ),
                ],
              ),
              if (i.history.length > 1) ...[
                const SizedBox(height: 24),
                const SectionTitle('Evolução', eyebrow: 'Últimos 12 meses'),
                const SizedBox(height: 8),
                HoinkCard(
                  padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                  child: SizedBox(
                    height: 200,
                    child: PrivacyBlur(
                      child: LineChart(
                        LineChartData(
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(drawVerticalLine: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                reservedSize: 26,
                                getTitlesWidget: (v, _) {
                                  final k = v.toInt();
                                  if (k < 0 || k >= i.history.length || v != k.toDouble()) return const SizedBox();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(monthShort(i.history[k].date.substring(0, 7)), style: HoinkText.bodySm),
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
                                    '${s.barIndex == 0 ? 'Valor' : 'Aplicado'}: ${formatBRL(s.y.round())}',
                                    HoinkText.bodySm.copyWith(color: HoinkColors.ivory),
                                  ),
                              ],
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var k = 0; k < i.history.length; k++)
                                  FlSpot(k.toDouble(), i.history[k].valueCents.toDouble()),
                              ],
                              color: HoinkColors.pine,
                              barWidth: 2.5,
                              dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: [
                                for (var k = 0; k < i.history.length; k++)
                                  FlSpot(k.toDouble(), i.history[k].principalCents.toDouble()),
                              ],
                              color: HoinkColors.pigPink,
                              barWidth: 2,
                              dashArray: [6, 4],
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const SectionTitle('Movimentações'),
              const SizedBox(height: 8),
              HoinkCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    for (final m in i.movements)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: IconBadge(switch (m.kind) {
                          'CONTRIBUTION' => Symbols.add,
                          'REDEMPTION' => Symbols.move_up,
                          'INCOME' => Symbols.paid,
                          _ => Symbols.edit_note,
                        }),
                        title: Text(switch (m.kind) {
                          'CONTRIBUTION' => 'Aporte',
                          'REDEMPTION' => 'Resgate',
                          'INCOME' => 'Proventos',
                          _ => i.isMarket ? 'Cotação informada' : 'Saldo informado',
                        }),
                        subtitle: Text(
                          [
                            formatBrDate(m.date),
                            if (m.quantity != null) '${m.quantity!.toString().replaceAll('.', ',')} cotas',
                            ?m.account,
                          ].join(' • '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m.kind == 'VALUE_UPDATE' && i.isMarket
                                  ? formatBRL((m.unitPrice ?? 0).round())
                                  : formatBRL(m.amountCents),
                              style: HoinkText.labelMd,
                            ),
                            IconButton(
                              tooltip: 'Excluir movimentação',
                              icon: const Icon(Symbols.delete, size: 18),
                              onPressed: () => runAction(
                                context,
                                ref,
                                () => ref.read(repositoryProvider).deleteInvestmentMovement(i.entityId, i.id, m.id),
                                'Movimentação excluída',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
  }

  Future<void> _move(BuildContext context, WidgetRef ref, Investment i, String path) async {
    final accounts = (await ref.read(accountsProvider(i.entityId).future)).where((a) => !a.archived).toList();
    if (!context.mounted) return;
    final amount = TextEditingController();
    final quantity = TextEditingController();
    var date = DateTime.now();
    String? accountId = accounts.firstOrNull?.id;
    final value = path == 'value';
    final title = switch (path) {
      'contributions' => 'Aportar',
      'redemptions' => 'Resgatar',
      'income' => 'Proventos recebidos',
      _ => i.isMarket ? 'Cotação atual' : 'Saldo do extrato',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MoneyField(
                  controller: amount,
                  label: value ? (i.isMarket ? 'Preço por cota/ação' : 'Valor atualizado') : 'Valor',
                  fieldKey: const Key('investment-move-amount'),
                ),
                if (i.isMarket && !value && path != 'income') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                  ),
                ],
                const SizedBox(height: 12),
                DateField(label: 'Data', value: date, onChanged: (d) => setState(() => date = d)),
                if (!value) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Conta'),
                    items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                    onChanged: (v) => setState(() => accountId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    final cents = parseBRLToCents(amount.text);
    if (ok != true || cents == null || cents <= 0 || !context.mounted) return;
    final qty = double.tryParse(quantity.text.replaceAll('.', '').replaceAll(',', '.'));
    final body = value
        ? {'date': isoDate(date), if (i.isMarket) 'unitPriceCents': cents else 'valueCents': cents}
        : {'date': isoDate(date), 'amountCents': cents, 'accountId': accountId, 'quantity': ?qty};
    await runAction(
      context,
      ref,
      () => ref.read(repositoryProvider).investmentAction(i.entityId, i.id, path, body),
      'Registrado',
    );
  }
}
