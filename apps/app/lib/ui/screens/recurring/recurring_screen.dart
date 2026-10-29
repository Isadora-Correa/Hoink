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
import '../transactions/transactions_screen.dart' show settleDialog;

final recurringRulesProvider = FutureProvider.family<List<RecurringRule>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).recurringRules(entityId);
});

final recurringRuleProvider = FutureProvider.family<RecurringRule, ({String entityId, String id})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).recurringRule(a.entityId, a.id);
});

/// Lista das recorrências (contas fixas, assinaturas, salários) do ambiente atual — ou de todos no Total.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final scope = ref.watch(effectiveScopeProvider);
    final current = ref.watch(currentEntityProvider);
    final entities = ref.watch(entitiesProvider).value ?? const <FinancialEntity>[];
    final shown = scope == Scope.total ? entities : [?current];

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 8, wide ? 24 : 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recorrências',
                            style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(
                              color: HoinkColors.primary,
                            ),
                          ),
                          Text(
                            'Contas fixas, assinaturas e receitas que se repetem. Cada ocorrência vira um lançamento previsto.',
                            style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      key: const Key('new-recurring'),
                      onPressed: () => context.push('/lancamentos/novo?recorrente=1'),
                      icon: const Icon(Symbols.add, size: 18),
                      label: Text(wide ? 'Nova recorrência' : 'Nova'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                for (final e in shown) ...[
                  if (scope == Scope.total)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(e.name, style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                    ),
                  _EntityRules(entityId: e.id),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EntityRules extends ConsumerWidget {
  const _EntityRules({required this.entityId});
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(recurringRulesProvider(entityId))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(recurringRulesProvider(entityId))),
          data: (rules) {
            if (rules.isEmpty) {
              return HoinkCard(
                child: EmptyState(
                  title: 'Nenhuma recorrência',
                  message: 'Cadastre aluguel, energia, assinaturas ou salário uma vez e a hoink. cria as próximas.',
                  action: FilledButton(
                    onPressed: () => context.push('/lancamentos/novo?recorrente=1'),
                    child: const Text('Criar recorrência'),
                  ),
                ),
              );
            }
            final active = rules.where((r) => r.status != 'CANCELED').toList();
            final canceled = rules.where((r) => r.status == 'CANCELED').toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in active) ...[_RuleCard(rule: r), const SizedBox(height: 12)],
                if (canceled.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Canceladas (${canceled.length})', style: HoinkText.labelMd),
                    children: [
                      for (final r in canceled) ...[_RuleCard(rule: r), const SizedBox(height: 8)],
                    ],
                  ),
              ],
            );
          },
        );
  }
}

Pill ruleStatusPill(String status) => switch (status) {
  'ACTIVE' => const Pill('Ativa', dot: HoinkColors.surfaceTint, background: HoinkColors.primaryFixed),
  'PAUSED' => const Pill(
    'Pausada',
    icon: Symbols.pause,
    background: HoinkColors.tertiaryFixed,
    foreground: HoinkColors.onTertiaryFixed,
  ),
  _ => const Pill('Cancelada', background: HoinkColors.surfaceHigh, foreground: HoinkColors.outline),
};

class _RuleCard extends ConsumerWidget {
  const _RuleCard({required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = rule;
    return HoinkCard(
      padding: const EdgeInsets.all(18),
      onTap: () => context.push('/recorrencias/${r.entityId}/${r.id}'),
      child: Row(
        children: [
          IconBadge(
            r.categoryIcon != null ? categoryIcon(r.categoryIcon) : Symbols.event_repeat,
            background: r.isIncome ? HoinkColors.surfaceContainer : HoinkColors.surfaceLow,
            foreground: r.isIncome ? HoinkColors.surfaceTint : HoinkColors.pine,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(r.description, style: HoinkText.headlineSm),
                    ruleStatusPill(r.status),
                    if (r.overdueCount > 0) const StatusPill('OVERDUE'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.frequencyLabel} • ${amountKindLabels[r.amountKind]} • ${r.accountName}',
                  style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
                if (r.nextDate != null && r.isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Próxima: ${formatBrDate(r.nextDate!)}',
                      style: HoinkText.labelSm.copyWith(color: HoinkColors.surfaceTint),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                r.isIncome ? r.amountCents : -r.amountCents,
                signed: true,
                style: HoinkText.headlineSm,
                color: r.isIncome ? HoinkColors.surfaceTint : HoinkColors.onSurface,
              ),
              if (r.amountKind != 'FIXED')
                Text('valor previsto', style: HoinkText.bodySm.copyWith(color: HoinkColors.outline)),
            ],
          ),
          RuleActionsMenu(rule: r),
        ],
      ),
    );
  }
}

/// Ações da série: editar, pausar/reativar, cancelar.
class RuleActionsMenu extends ConsumerWidget {
  const RuleActionsMenu({super.key, required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rule.status == 'CANCELED') return const SizedBox(width: 8);
    return PopupMenuButton<String>(
      tooltip: 'Ações da recorrência',
      onSelected: (v) async {
        if (v == 'edit') return editSeriesDialog(context, ref, rule);
        if (v == 'cancel') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cancelar recorrência?'),
              content: const Text(
                'As ocorrências futuras previstas serão removidas. O histórico já pago e as contas vencidas continuam no extrato.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: HoinkColors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cancelar série'),
                ),
              ],
            ),
          );
          if (ok != true) return;
        }
        try {
          await ref.read(repositoryProvider).recurringAction(rule.entityId, rule.id, v);
          ref.read(dataVersionProvider.notifier).bump();
          if (context.mounted) {
            showSuccess(
              context,
              {
                'pause': 'Recorrência pausada',
                'resume': 'Recorrência reativada',
                'cancel': 'Recorrência cancelada',
              }[v]!,
            );
          }
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Editar série')),
        if (rule.status == 'ACTIVE') const PopupMenuItem(value: 'pause', child: Text('Pausar')),
        if (rule.status == 'PAUSED') const PopupMenuItem(value: 'resume', child: Text('Reativar')),
        const PopupMenuItem(value: 'cancel', child: Text('Cancelar série')),
      ],
    );
  }
}

/// Edita a série inteira (realizados preservados). Para alterar só uma ocorrência, edite o lançamento.
Future<void> editSeriesDialog(BuildContext context, WidgetRef ref, RecurringRule rule) async {
  final description = TextEditingController(text: rule.description);
  final amount = TextEditingController(text: formatAmount(rule.amountCents));
  var kind = rule.amountKind;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Editar série'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor previsto', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final e in amountKindLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
              const SizedBox(height: 12),
              Text(
                'Vale para todas as ocorrências ainda não pagas. As já pagas e as editadas individualmente não mudam.',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final cents = parseBRLToCents(amount.text);
  if (cents == null || cents <= 0) {
    if (context.mounted) showError(context, 'Valor inválido');
    return;
  }
  try {
    await ref
        .read(repositoryProvider)
        .updateRecurring(
          rule.entityId,
          rule.id,
          scope: 'SERIES',
          changes: {'description': description.text.trim(), 'amountCents': cents, 'amountKind': kind},
        );
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) showSuccess(context, 'Série atualizada');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Detalhe de uma recorrência com todas as ocorrências (histórico e futuras).
class RecurringDetailScreen extends ConsumerWidget {
  const RecurringDetailScreen({super.key, required this.entityId, required this.ruleId});
  final String entityId;
  final String ruleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(recurringRuleProvider((entityId: entityId, id: ruleId)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e),
          data: (r) {
            final today = isoDate(DateTime.now());
            final past = r.occurrences.where((t) => t.competenceDate.compareTo(today) < 0).toList().reversed.toList();
            final future = r.occurrences.where((t) => t.competenceDate.compareTo(today) >= 0).toList();
            Widget section(String title, List<Txn> items) => HoinkCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                  const SizedBox(height: 4),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Nada por aqui.', style: HoinkText.bodyMd.copyWith(color: HoinkColors.outline)),
                    ),
                  for (final t in items) ...[
                    TransactionTile(
                      t,
                      onTap: () => context.push('/lancamentos/${t.entityId}/${t.id}'),
                      trailingExtra: t.isOpen
                          ? IconButton(
                              tooltip: t.isIn ? 'Confirmar recebimento' : 'Pagar',
                              icon: const Icon(Symbols.check_circle, color: HoinkColors.surfaceTint),
                              onPressed: () => settleDialog(context, ref, t),
                            )
                          : null,
                    ),
                    if (t != items.last) const Divider(),
                  ],
                ],
              ),
            );
            return ListView(
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
                              tooltip: 'Voltar',
                              onPressed: () => context.canPop() ? context.pop() : context.go('/recorrencias'),
                              icon: const Icon(Symbols.arrow_back),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.description,
                                    style: HoinkText.headlineLgMobile.copyWith(color: HoinkColors.primary),
                                  ),
                                  Text(
                                    '${r.frequencyLabel} desde ${formatBrDate(r.startDate)}'
                                    '${r.endDate != null ? ' até ${formatBrDate(r.endDate!)}' : ''}',
                                    style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            ruleStatusPill(r.status),
                            RuleActionsMenu(rule: r),
                          ],
                        ),
                        const SizedBox(height: 16),
                        HeroCard(
                          child: Row(
                            children: [
                              Expanded(child: _Stat('Valor previsto', formatBRL(r.amountCents))),
                              Expanded(child: _Stat('Tipo de valor', amountKindLabels[r.amountKind]!)),
                              Expanded(child: _Stat('Pagas', '${r.settledCount}')),
                              Expanded(child: _Stat('Em atraso', '${r.overdueCount}')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toque numa ocorrência para alterar só ela, desta em diante ou a série inteira.',
                          style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
                        ),
                        const SizedBox(height: 16),
                        section('Próximas', future),
                        const SizedBox(height: 16),
                        section('Histórico', past),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer)),
      const SizedBox(height: 6),
      Text(value, style: HoinkText.headlineSm.copyWith(color: Colors.white)),
    ],
  );
}
