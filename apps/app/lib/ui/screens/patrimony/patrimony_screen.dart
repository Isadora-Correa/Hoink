import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/page.dart';

/// Patrimônio do ambiente atual (ou consolidado).
final patrimonyProvider = FutureProvider<Patrimony>((ref) async {
  ref.watch(dataVersionProvider);
  await ref.watch(entitiesProvider.future);
  final entity = ref.watch(currentEntityProvider);
  return ref.read(repositoryProvider).patrimony(entityId: entity?.id);
});

/// Patrimônio líquido = ativos − passivos, com histórico mensal. Não é o mesmo que saldo disponível.
class PatrimonyScreen extends ConsumerWidget {
  const PatrimonyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = ref.watch(currentEntityProvider);
    return ModulePage(
      title: 'Patrimônio',
      subtitle: 'Tudo o que você tem menos tudo o que deve. Dinheiro guardado ou investido não é contado duas vezes.',
      action: entity != null && entity.canWrite
          ? FilledButton.icon(
              key: const Key('new-asset'),
              onPressed: () => showItemForm(context, ref, entity.id),
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('Bem ou dívida'),
            )
          : null,
      children: [
        ref
            .watch(patrimonyProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(patrimonyProvider)),
              data: (p) {
                final assets = HoinkCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Ativos', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                      const SizedBox(height: 8),
                      ValueRow('Contas (saldo disponível)', p.cashCents),
                      ValueRow('Cofrinhos', p.piggyBanksCents),
                      ValueRow('Investimentos', p.investmentsCents),
                      ValueRow('Bens', p.otherAssetsCents),
                      const Divider(),
                      ValueRow('Total', p.assetsCents, bold: true),
                    ],
                  ),
                );
                final liabilities = HoinkCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Passivos', style: HoinkText.headlineSm.copyWith(color: HoinkColors.tertiaryContainer)),
                      const SizedBox(height: 8),
                      ValueRow('Empréstimos e financiamentos', p.debtsCents),
                      ValueRow('Cartões (compras a pagar)', p.cardsCents),
                      ValueRow('Outras obrigações', p.otherLiabilitiesCents),
                      const Divider(),
                      ValueRow('Total', p.liabilitiesCents, bold: true),
                    ],
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HeroCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PATRIMÔNIO LÍQUIDO',
                            style: HoinkText.labelSm.copyWith(
                              color: HoinkColors.onPrimaryContainer,
                              letterSpacing: 1.2,
                            ),
                          ),
                          MoneyText(
                            p.netWorthCents,
                            style: HoinkText.displayHero.copyWith(fontSize: 40),
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ativos ${formatBRL(p.assetsCents)} − passivos ${formatBRL(p.liabilitiesCents)}',
                            style: HoinkText.bodySm.copyWith(color: HoinkColors.primaryFixedDim),
                          ),
                          if (p.history.length > 1) ...[
                            const SizedBox(height: 4),
                            Text(() {
                              final first = p.history.first;
                              final diff = p.netWorthCents - first.netWorthCents;
                              return '${diff >= 0 ? '+' : ''}${formatBRL(diff)} desde ${monthLabel(first.month).toLowerCase()}';
                            }(), style: HoinkText.labelMd.copyWith(color: HoinkColors.mint)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) => c.maxWidth < 700
                          ? Column(children: [assets, const SizedBox(height: 12), liabilities])
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: assets),
                                const SizedBox(width: 16),
                                Expanded(child: liabilities),
                              ],
                            ),
                    ),
                    if (p.history.length > 1) ...[
                      const SizedBox(height: 24),
                      const SectionTitle('Evolução mensal', eyebrow: 'Histórico'),
                      const SizedBox(height: 8),
                      HoinkCard(
                        padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                        child: SizedBox(height: 220, child: PrivacyBlur(child: _HistoryChart(p))),
                      ),
                    ],
                    if (entity != null) ...[
                      const SizedBox(height: 24),
                      const SectionTitle('Bens e outras dívidas', eyebrow: 'Informados por você'),
                      const SizedBox(height: 8),
                      HoinkCard(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: p.items.isEmpty
                            ? const EmptyState(
                                title: 'Nenhum bem cadastrado',
                                message: 'Imóveis, veículos e outras dívidas entram no patrimônio pelo valor que você informar.',
                              )
                            : Column(
                                children: [
                                  for (final i in p.items)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: IconBadge(
                                        i.side == 'ASSET' ? Symbols.home_work : Symbols.money_off,
                                        background: i.side == 'ASSET'
                                            ? HoinkColors.surfaceContainer
                                            : HoinkColors.tertiaryFixed,
                                        foreground: i.side == 'ASSET'
                                            ? HoinkColors.pine
                                            : HoinkColors.tertiaryContainer,
                                      ),
                                      title: Text(i.name),
                                      subtitle: Text('${i.category} • valor de ${formatBrDate(i.valuedAt)}'),
                                      trailing: Text(
                                        '${i.side == 'LIABILITY' ? '−' : ''}${formatBRL(i.valueCents)}',
                                        style: HoinkText.labelMd,
                                      ),
                                      onTap: () => showItemForm(context, ref, entity.id, item: i),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ],
                );
              },
            ),
      ],
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart(this.p);
  final Patrimony p;

  @override
  Widget build(BuildContext context) {
    final h = p.history;
    return LineChart(
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
                if (k < 0 || k >= h.length || v != k.toDouble()) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(monthShort(h[k].month), style: HoinkText.bodySm),
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
                  '${['Patrimônio líquido', 'Ativos', 'Passivos'][s.barIndex]}: ${formatBRL(s.y.round())}',
                  HoinkText.bodySm.copyWith(color: HoinkColors.ivory),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final (pick, color, width) in [
            ((dynamic x) => x.netWorthCents as int, HoinkColors.pine, 3.0),
            ((dynamic x) => x.assetsCents as int, HoinkColors.primaryFixedDim, 1.5),
            ((dynamic x) => x.liabilitiesCents as int, HoinkColors.pigPink, 1.5),
          ])
            LineChartBarData(
              spots: [for (var k = 0; k < h.length; k++) FlSpot(k.toDouble(), pick(h[k]).toDouble())],
              color: color,
              barWidth: width,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

/// Bem (imóvel, veículo…) ou outra dívida informada manualmente.
Future<void> showItemForm(BuildContext context, WidgetRef ref, String entityId, {PatrimonyItem? item}) async {
  final name = TextEditingController(text: item?.name);
  final value = TextEditingController(text: item == null ? '' : formatAmount(item.valueCents));
  var side = item?.side ?? 'ASSET';
  var category = item?.category ?? 'Imóvel';
  var date = item == null ? DateTime.now() : parseIso(item.valuedAt);
  const assetCats = ['Imóvel', 'Veículo', 'Eletrônicos', 'Participação em empresa', 'Outros bens'];
  const liabilityCats = ['Empréstimo de pessoa', 'Impostos a pagar', 'Outras dívidas'];
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final cats = side == 'ASSET' ? assetCats : liabilityCats;
        if (!cats.contains(category)) category = cats.first;
        return AlertDialog(
          title: Text(item == null ? 'Novo item' : 'Editar item'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'ASSET', label: Text('Bem')),
                    ButtonSegment(value: 'LIABILITY', label: Text('Dívida')),
                  ],
                  selected: {side},
                  onSelectionChanged: (s) => setState(() => side = s.first),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(side),
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => category = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('item-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Apartamento, Moto'),
                ),
                const SizedBox(height: 12),
                MoneyField(controller: value, label: 'Valor', fieldKey: const Key('item-value')),
                const SizedBox(height: 12),
                DateField(label: 'Valor em', value: date, onChanged: (d) => setState(() => date = d)),
              ],
            ),
          ),
          actions: [
            if (item != null)
              TextButton(
                onPressed: () async {
                  final ok = await runAction(
                    ctx,
                    ref,
                    () => ref.read(repositoryProvider).deletePatrimonyItem(entityId, item.id),
                    'Item removido',
                  );
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Remover'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              key: const Key('save-item'),
              onPressed: () async {
                final cents = parseBRLToCents(value.text);
                if (name.text.trim().isEmpty || cents == null || cents < 0) {
                  return showError(ctx, 'Informe nome e valor');
                }
                final ok = await runAction(
                  ctx,
                  ref,
                  () => ref.read(repositoryProvider).savePatrimonyItem(entityId, {
                    'side': side,
                    'category': category,
                    'name': name.text.trim(),
                    'valueCents': cents,
                    'valuedAt': isoDate(date),
                  }, id: item?.id),
                  'Patrimônio atualizado',
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
