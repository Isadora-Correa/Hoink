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
  const StatementScreen({super.key, required this.entityId, required this.accountId, this.showBack = true});
  final String entityId;
  final String accountId;

  /// Falso quando o extrato aparece dentro da tela "Extrato" (que já tem a escolha da conta).
  final bool showBack;

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
                      if (showBack) ...[
                        IconButton(
                          onPressed: () => context.go('/contas'),
                          icon: const Icon(Symbols.arrow_back),
                          tooltip: 'Voltar',
                        ),
                        const SizedBox(width: 8),
                      ],
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

/// Extrato no menu: escolhe a conta (do ambiente atual ou de todos no Total) e mostra o extrato do mês.
class StatementHubScreen extends ConsumerStatefulWidget {
  const StatementHubScreen({super.key});
  @override
  ConsumerState<StatementHubScreen> createState() => _StatementHubScreenState();
}

class _StatementHubScreenState extends ConsumerState<StatementHubScreen> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(effectiveScopeProvider);
    final entities = ref.watch(entitiesProvider).value ?? const <FinancialEntity>[];
    final current = ref.watch(currentEntityProvider);
    final shown = scope == Scope.total ? entities : [?current];
    final accounts = <Account>[
      for (final e in shown)
        ...(ref.watch(accountsProvider(e.id)).value ?? const <Account>[]).where((a) => !a.archived),
    ];
    if (accounts.isEmpty) {
      return const EmptyState(
        title: 'Nenhuma conta',
        message: 'Cadastre uma conta em Minhas Contas para ver o extrato.',
      );
    }
    final selected = accounts.where((a) => a.id == _accountId).firstOrNull ?? accounts.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Conta:', style: HoinkText.labelMd),
              for (final a in accounts)
                ChoiceChip(
                  key: Key('statement-account-${a.id}'),
                  label: Text(a.name),
                  selected: a.id == selected.id,
                  onSelected: (_) => setState(() => _accountId = a.id),
                ),
            ],
          ),
        ),
        Expanded(
          child: StatementScreen(
            key: ValueKey(selected.id),
            entityId: selected.entityId,
            accountId: selected.id,
            showBack: false,
          ),
        ),
      ],
    );
  }
}
