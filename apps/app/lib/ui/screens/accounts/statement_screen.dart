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

typedef _StatementArgs = ({String entityId, String accountId, String month});

final _statementProvider = FutureProvider.family<Statement, _StatementArgs>((ref, a) async {
  ref.watch(dataVersionProvider);
  final d = DateTime.parse('${a.month}-01');
  final last = DateTime(d.year, d.month + 1, 0);
  return ref.read(repositoryProvider).statement(a.entityId, a.accountId, '${a.month}-01', isoDate(last));
});

/// Extrato de uma conta: saldo de abertura, movimentações liquidadas e saldo acumulado.
class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key, required this.entityId, required this.accountId});
  final String entityId;
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final st = ref.watch(_statementProvider((entityId: entityId, accountId: accountId, month: month)));
    return st.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e),
      data: (s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go('/contas'),
                        icon: const Icon(Symbols.arrow_back),
                        tooltip: 'Voltar',
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.account.name,
                              style: HoinkText.headlineLgMobile.copyWith(color: HoinkColors.primary),
                            ),
                            Text(
                              'Extrato de ${monthLabel(month)}',
                              style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref.read(monthProvider.notifier).set(shiftMonth(month, -1)),
                        icon: const Icon(Symbols.chevron_left),
                        tooltip: 'Mês anterior',
                      ),
                      IconButton(
                        onPressed: () => ref.read(monthProvider.notifier).set(shiftMonth(month, 1)),
                        icon: const Icon(Symbols.chevron_right),
                        tooltip: 'Próximo mês',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HeroCard(
                    child: Row(
                      children: [
                        Expanded(child: _Stat('Saldo inicial do período', s.openingBalanceCents)),
                        Expanded(child: _Stat('Saldo final do período', s.closingBalanceCents)),
                        Expanded(child: _Stat('Saldo atual', s.account.balanceCents)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  HoinkCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: s.entries.isEmpty
                        ? const EmptyState(
                            title: 'Sem movimentações',
                            message: 'Nenhuma movimentação liquidada neste período.',
                          )
                        : Column(
                            children: [
                              for (final e in s.entries) ...[_EntryRow(e), if (e != s.entries.last) const Divider()],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.cents);
  final String label;
  final int cents;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer)),
      const SizedBox(height: 6),
      MoneyText(cents, style: HoinkText.headlineMd, color: Colors.white),
    ],
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.e);
  final StatementEntry e;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            formatBrDate(e.date).substring(0, 5),
            style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.description, style: HoinkText.labelMd, overflow: TextOverflow.ellipsis),
              Text(
                e.categoryName ?? transactionTypeLabels[e.type] ?? e.type,
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(
              e.direction == 'IN' ? e.amountCents : -e.amountCents,
              signed: true,
              style: HoinkText.labelMd.copyWith(fontSize: 14),
              color: e.direction == 'IN' ? HoinkColors.surfaceTint : HoinkColors.onSurface,
            ),
            Text(
              'Saldo ${formatBRL(e.balanceAfterCents)}',
              style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
            ),
          ],
        ),
      ],
    ),
  );
}
