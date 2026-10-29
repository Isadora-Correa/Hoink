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
import '../transactions/transactions_screen.dart' show settleDialog;

final payablesProvider = FutureProvider.family<PayablesPage, ({String entityId, String kind, String status})>((
  ref,
  a,
) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).payables(a.entityId, kind: a.kind, status: a.status);
});

/// Contas a receber (cobranças) e a pagar (obrigações) em aberto, com atraso e próximos 7 dias.
class PayablesScreen extends ConsumerStatefulWidget {
  const PayablesScreen({super.key, this.initialKind = 'receivable'});
  final String initialKind;
  @override
  ConsumerState<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends ConsumerState<PayablesScreen> {
  late String _kind = widget.initialKind;
  String _status = 'open';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final entity = ref.watch(currentEntityProvider) ?? (ref.watch(entitiesProvider).value ?? const []).firstOrNull;
    if (entity == null) return const Center(child: CircularProgressIndicator());
    final page = ref.watch(payablesProvider((entityId: entity.id, kind: _kind, status: _status)));
    final receivable = _kind == 'receivable';

    Widget kpi(String label, int cents, IconData icon, Color color) => SizedBox(
      width: 220,
      child: HoinkCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MoneyText(cents, style: HoinkText.headlineMd),
          ],
        ),
      ),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 8, wide ? 24 : 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Contas a pagar e receber',
                  style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(
                    color: HoinkColors.primary,
                  ),
                ),
                Text(
                  '${entity.name} • valores em aberto, inclusive recebimentos e pagamentos parciais',
                  style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: HoinkColors.pine,
                        selectedForegroundColor: HoinkColors.ivory,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 'receivable',
                          label: Text('A receber'),
                          icon: Icon(Symbols.south_west, size: 16),
                        ),
                        ButtonSegment(
                          value: 'payable',
                          label: Text('A pagar'),
                          icon: Icon(Symbols.north_east, size: 16),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'open', label: Text('Em aberto')),
                        ButtonSegment(value: 'overdue', label: Text('Em atraso')),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) => setState(() => _status = s.first),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/lancamentos/novo?tipo=${receivable ? 'INCOME' : 'EXPENSE'}'),
                      icon: const Icon(Symbols.add, size: 18),
                      label: Text(receivable ? 'Nova cobrança' : 'Nova conta a pagar'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                page.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => ErrorState(e),
                  data: (p) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          kpi(
                            receivable ? 'A receber' : 'A pagar',
                            p.openCents,
                            Symbols.account_balance_wallet,
                            HoinkColors.pine,
                          ),
                          kpi('Em atraso', p.overdueCents, Symbols.warning, HoinkColors.error),
                          kpi('Próximos 7 dias', p.next7DaysCents, Symbols.event_upcoming, HoinkColors.surfaceTint),
                        ],
                      ),
                      if (p.cardInvoices.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Faturas de cartão', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                        const SizedBox(height: 8),
                        HoinkCard(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            children: [
                              for (final inv in p.cardInvoices)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const IconBadge(Symbols.credit_card),
                                  title: Text('${inv.cardName} • fatura de ${monthLabel(inv.month)}'),
                                  subtitle: Text('Vence em ${formatBrDate(inv.dueDate)}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(formatBRL(inv.remainingCents), style: HoinkText.labelMd),
                                      const Icon(Symbols.chevron_right),
                                    ],
                                  ),
                                  onTap: () => context.push('/cartoes/${inv.entityId}/${inv.cardId}'),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      HoinkCard(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: p.items.isEmpty
                            ? EmptyState(
                                title: _status == 'overdue' ? 'Nada em atraso' : 'Nada em aberto',
                                message: receivable
                                    ? 'Cobranças pendentes e recebimentos parciais aparecem aqui.'
                                    : 'Contas pendentes e pagamentos parciais aparecem aqui.',
                              )
                            : Column(
                                children: [
                                  for (final t in p.items) ...[
                                    TransactionTile(
                                      t,
                                      onTap: () => context.push('/lancamentos/${t.entityId}/${t.id}'),
                                      trailingExtra: IconButton(
                                        tooltip: receivable ? 'Registrar recebimento' : 'Registrar pagamento',
                                        icon: const Icon(Symbols.check_circle, color: HoinkColors.surfaceTint),
                                        onPressed: () => settleDialog(context, ref, t),
                                      ),
                                    ),
                                    if (t != p.items.last) const Divider(),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
