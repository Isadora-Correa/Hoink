import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/file_saver.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/page.dart';

const _icons = <String, IconData>{
  'receitas-despesas': Symbols.receipt_long,
  'fluxo-de-caixa': Symbols.waterfall_chart,
  'clientes': Symbols.groups,
  'contas-a-receber': Symbols.south_west,
  'contas-a-pagar': Symbols.north_east,
  'dividas': Symbols.credit_score,
  'cofrinhos': Symbols.savings,
  'investimentos': Symbols.trending_up,
  'rendimentos': Symbols.paid,
  'patrimonio': Symbols.account_balance_wallet,
  'orcamentos': Symbols.donut_small,
};

/// Tipos que aceitam filtro por categoria.
const _withCategory = {'receitas-despesas', 'contas-a-pagar', 'contas-a-receber', 'orcamentos'};

final reportTypesProvider = FutureProvider<List<({String type, String title})>>(
  (ref) => ref.read(repositoryProvider).reportTypes(),
);

/// Formata uma célula como na exportação (os números vêm prontos da API).
String formatReportCell(String type, Object? v) {
  if (v == null || v == '') return '';
  return switch (type) {
    'money' => formatBRL((v as num).toInt()),
    'percent' => formatPercentBps((v as num).toInt()),
    'date' =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$v')
          ? formatBrDate('$v')
          : RegExp(r'^\d{4}-\d{2}$').hasMatch('$v')
          ? '${'$v'.substring(5)}/${'$v'.substring(0, 4)}'
          : '$v',
    _ => '$v',
  };
}

/// Relatórios: prévia na tela e exportação em PDF, XLSX e CSV com os mesmos números.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _type = 'receitas-despesas';
  String _period = 'month';
  DateTimeRange? _custom;
  String? _categoryId;
  Report? _report;
  bool _loading = false;
  String? _downloading;

  Map<String, Object?> _query() => {
    'period': _period,
    'ref': ref.read(monthProvider),
    if (_period == 'custom' && _custom != null) 'from': isoDate(_custom!.start),
    if (_period == 'custom' && _custom != null) 'to': isoDate(_custom!.end),
    if (_withCategory.contains(_type)) 'categoryId': _categoryId,
  };

  String? get _entityId => ref.read(currentEntityProvider)?.id;

  Future<void> _preview() async {
    if (_period == 'custom' && _custom == null) return showError(context, 'Escolha o período');
    setState(() => _loading = true);
    try {
      final r = await ref.read(repositoryProvider).report(_entityId, _type, _query());
      setState(() => _report = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(String format) async {
    if (_period == 'custom' && _custom == null) return showError(context, 'Escolha o período');
    setState(() => _downloading = format);
    try {
      final bytes = await ref.read(repositoryProvider).reportFile(_entityId, _type, format, _query());
      if (bytes == null) throw 'Relatório não encontrado';
      final mime = switch (format) {
        'pdf' => 'application/pdf',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        _ => 'text/csv',
      };
      await saveFile(bytes, 'hoink-$_type-${ref.read(monthProvider)}.$format', mime);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(reportTypesProvider).value ?? const [];
    final entity = ref.watch(currentEntityProvider);
    final month = ref.watch(monthProvider);
    final categories = entity == null
        ? const <Category>[]
        : (ref.watch(categoriesProvider(entity.id)).value ?? const []);
    final r = _report;
    return ModulePage(
      title: 'Relatórios',
      subtitle: 'Os mesmos números do app, em PDF, planilha (XLSX) ou CSV. ${entity?.name ?? 'Consolidado (Total)'}.',
      maxWidth: 1200,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in types)
              ChoiceChip(
                key: Key('report-${t.type}'),
                avatar: Icon(_icons[t.type] ?? Symbols.description, size: 18),
                label: Text(t.title),
                selected: _type == t.type,
                onSelected: (_) => setState(() {
                  _type = t.type;
                  _report = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        HoinkCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'month', label: Text('Mês')),
                      ButtonSegment(value: 'quarter', label: Text('Trimestre')),
                      ButtonSegment(value: 'year', label: Text('Ano')),
                      ButtonSegment(value: 'custom', label: Text('Personalizado')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) => setState(() => _period = s.first),
                  ),
                  if (_period == 'custom')
                    OutlinedButton.icon(
                      icon: const Icon(Symbols.date_range, size: 18),
                      label: Text(
                        _custom == null
                            ? 'Escolher período'
                            : '${formatBrDate(isoDate(_custom!.start))} a ${formatBrDate(isoDate(_custom!.end))}',
                      ),
                      onPressed: () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDateRange: _custom,
                        );
                        if (range != null) setState(() => _custom = range);
                      },
                    )
                  else
                    Text('Referência: ${monthLabel(month)} (use o mês no topo)', style: HoinkText.bodySm),
                  if (_withCategory.contains(_type) && categories.isNotEmpty)
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _categoryId,
                        decoration: const InputDecoration(labelText: 'Categoria'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Todas')),
                          for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('preview-report'),
                    onPressed: _loading ? null : _preview,
                    icon: const Icon(Symbols.visibility, size: 18),
                    label: const Text('Ver na tela'),
                  ),
                  for (final (format, label, icon) in [
                    ('pdf', 'PDF', Symbols.picture_as_pdf),
                    ('xlsx', 'Planilha', Symbols.table_view),
                    ('csv', 'CSV', Symbols.csv),
                  ])
                    OutlinedButton.icon(
                      key: Key('download-$format'),
                      onPressed: _downloading != null ? null : () => _download(format),
                      icon: _downloading == format
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(icon, size: 18),
                      label: Text(label),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (r != null) ...[
          Text(r.title, style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary)),
          Text('${r.scope} • ${r.periodLabel}', style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (final s in r.sections) ...[_SectionTable(s), const SizedBox(height: 20)],
          for (final n in r.notes) Text(n, style: HoinkText.bodySm.copyWith(color: HoinkColors.outline)),
        ],
      ],
    );
  }
}

class _SectionTable extends StatelessWidget {
  const _SectionTable(this.s);
  final ReportSection s;

  @override
  Widget build(BuildContext context) {
    bool numeric(ReportColumn c) => c.type == 'money' || c.type == 'percent' || c.type == 'number';
    final head = HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title, style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
        const SizedBox(height: 8),
        HoinkCard(
          padding: const EdgeInsets.all(8),
          child: s.rows.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Sem dados no período.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 38,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 52,
                    columnSpacing: 22,
                    columns: [
                      for (final c in s.columns)
                        DataColumn(
                          label: Text(c.label, style: head),
                          numeric: numeric(c),
                        ),
                    ],
                    rows: [
                      for (final row in s.rows)
                        DataRow(
                          cells: [for (final c in s.columns) DataCell(Text(formatReportCell(c.type, row[c.key])))],
                        ),
                      if (s.totals != null)
                        DataRow(
                          color: const WidgetStatePropertyAll(HoinkColors.surfaceLow),
                          cells: [
                            for (final c in s.columns)
                              DataCell(Text(formatReportCell(c.type, s.totals![c.key]), style: HoinkText.labelMd)),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
        if (s.note != null) ...[
          const SizedBox(height: 6),
          Text(s.note!, style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
        ],
      ],
    );
  }
}
