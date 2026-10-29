import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/api_client.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../shell/app_shell.dart';
import '../../widgets/common.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final entitiesAsync = ref.watch(entitiesProvider);
    final scope = ref.watch(effectiveScopeProvider);
    final current = ref.watch(currentEntityProvider);

    return entitiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(entitiesProvider)),
      data: (entities) {
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
                                'Minhas Contas',
                                style: (wide ? HoinkText.headlineLg : HoinkText.headlineLgMobile).copyWith(
                                  color: HoinkColors.primary,
                                ),
                              ),
                              Text(
                                'Saldos calculados a partir do saldo inicial e das movimentações liquidadas.',
                                style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    for (final e in shown) ...[_EntityAccounts(entity: e), const SizedBox(height: 24)],
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

class _EntityAccounts extends ConsumerWidget {
  const _EntityAccounts({required this.entity});
  final FinancialEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider(entity.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(entity.isPersonal ? Symbols.person : Symbols.business_center, color: HoinkColors.pine),
            const SizedBox(width: 8),
            Expanded(
              child: Text(entity.name, style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary)),
            ),
            if (entity.canWrite)
              FilledButton.icon(
                onPressed: () => showAccountForm(context, ref, entity.id),
                icon: const Icon(Symbols.add, size: 18),
                label: const Text('Nova conta'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        accounts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(accountsProvider(entity.id))),
          data: (list) {
            final active = list.where((a) => !a.archived).toList();
            final archived = list.where((a) => a.archived).toList();
            if (list.isEmpty) {
              return HoinkCard(
                child: EmptyState(
                  title: 'Nenhuma conta cadastrada',
                  message: 'Cadastre sua conta corrente, carteira ou corretora com o saldo de hoje.',
                  action: FilledButton(
                    onPressed: () => showAccountForm(context, ref, entity.id),
                    child: const Text('Cadastrar conta'),
                  ),
                ),
              );
            }
            final total = active.fold<int>(0, (s, a) => s + a.balanceCents);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
                    final w = (c.maxWidth - (cols - 1) * 16) / cols;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final a in active)
                          SizedBox(
                            width: w,
                            child: _AccountCard(account: a, entity: entity),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Total em ${entity.name}: ${formatBRL(total)}',
                  style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Arquivadas (${archived.length})', style: HoinkText.labelMd),
                    children: [
                      for (final a in archived)
                        ListTile(
                          title: Text(a.name),
                          subtitle: Text(a.institution ?? accountTypeLabels[a.type]!),
                          trailing: TextButton(
                            onPressed: () => _run(
                              context,
                              ref,
                              () => ref.read(repositoryProvider).setAccountArchived(entity.id, a.id, false),
                              'Conta reativada',
                            ),
                            child: const Text('Reativar'),
                          ),
                        ),
                    ],
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

Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String success) async {
  try {
    await action();
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) showSuccess(context, success);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account, required this.entity});
  final Account account;
  final FinancialEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = account;
    return HoinkCard(
      padding: const EdgeInsets.all(20),
      onTap: () => context.go('/contas/${entity.id}/${a.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(switch (a.type) {
                'WALLET' => Symbols.account_balance_wallet,
                'BROKERAGE' => Symbols.candlestick_chart,
                'SAVINGS' => Symbols.savings,
                _ => Symbols.account_balance,
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: HoinkText.headlineSm, overflow: TextOverflow.ellipsis),
                    Text(
                      '${a.institution ?? ''}${a.institution != null ? ' • ' : ''}${accountTypeLabels[a.type]}',
                      style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (entity.canWrite)
                PopupMenuButton<String>(
                  tooltip: 'Ações',
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        showAccountForm(context, ref, entity.id, account: a);
                      case 'reconcile':
                        _reconcile(context, ref, entity.id, a);
                      case 'archive':
                        _run(
                          context,
                          ref,
                          () => ref.read(repositoryProvider).setAccountArchived(entity.id, a.id, true),
                          'Conta arquivada',
                        );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'reconcile', child: Text('Conciliar saldo')),
                    PopupMenuItem(value: 'archive', child: Text('Arquivar')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Saldo atual', style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
          MoneyText(a.balanceCents, style: HoinkText.currencyDisplayMobile),
          const SizedBox(height: 6),
          Text(
            'Saldo inicial ${formatBRL(a.initialBalanceCents)} em ${formatBrDate(a.referenceDate)}',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
          ),
        ],
      ),
    );
  }
}

Future<void> showAccountForm(BuildContext context, WidgetRef ref, String entityId, {Account? account}) async {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(text: account?.name);
  final institution = TextEditingController(text: account?.institution);
  final initial = TextEditingController(
    text: account == null
        ? ''
        : (account.initialBalanceCents < 0 ? '-' : '') + formatAmount(account.initialBalanceCents),
  );
  var type = account?.type ?? 'CHECKING';
  var refDate = account == null ? DateTime.now() : parseIso(account.referenceDate);
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                account == null ? 'Nova conta' : 'Editar conta',
                style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                Text(error!, style: HoinkText.bodySm.copyWith(color: HoinkColors.error)),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: name,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                decoration: const InputDecoration(labelText: 'Nome (ex.: Nubank Ultravioleta)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: institution,
                decoration: const InputDecoration(labelText: 'Instituição'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final e in accountTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => type = v!,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: initial,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: (v) => (v ?? '').trim().isEmpty || parseBRLToCents(v!) != null ? null : 'Valor inválido',
                decoration: const InputDecoration(labelText: 'Saldo na data de referência', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Symbols.calendar_today, size: 18),
                label: Text('Data de referência: ${formatBrDate(isoDate(refDate))}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: refDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => refDate = d);
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Movimentações liquidadas antes desta data já estão incluídas no saldo informado.',
                style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    await ref.read(repositoryProvider).saveAccount(entityId, {
                      'name': name.text.trim(),
                      'institution': institution.text.trim().isEmpty ? null : institution.text.trim(),
                      'type': type,
                      'initialBalanceCents': parseBRLToCents(initial.text.trim().isEmpty ? '0' : initial.text) ?? 0,
                      'referenceDate': isoDate(refDate),
                    }, id: account?.id);
                    ref.read(dataVersionProvider.notifier).bump();
                    if (ctx.mounted) Navigator.pop(ctx);
                  } on ApiException catch (e) {
                    setState(() => error = e.message);
                  }
                },
                child: Text(account == null ? 'Cadastrar conta' : 'Salvar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _reconcile(BuildContext context, WidgetRef ref, String entityId, Account a) async {
  final ctrl = TextEditingController();
  var date = DateTime.now();
  Map<String, dynamic>? result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Conciliar saldo'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Informe o saldo que aparece no aplicativo do banco para ${a.name}.', style: HoinkText.bodyMd),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Saldo no banco', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: parseIso(a.referenceDate),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => date = d);
                },
                child: Text('Em ${formatBrDate(isoDate(date))}'),
              ),
              if (result != null) ...[
                const SizedBox(height: 16),
                Text('Saldo calculado: ${formatBRL(result!['computedBalanceCents'] as int)}', style: HoinkText.bodyMd),
                Text(
                  result!['differenceCents'] == 0
                      ? 'Tudo certo: os saldos conferem.'
                      : 'Diferença: ${formatBRL(result!['differenceCents'] as int, signed: true)}',
                  style: HoinkText.headlineSm.copyWith(
                    color: result!['differenceCents'] == 0 ? HoinkColors.surfaceTint : HoinkColors.tertiaryContainer,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          OutlinedButton(
            onPressed: () async {
              final cents = parseBRLToCents(ctrl.text);
              if (cents == null) return;
              try {
                final r = await ref.read(repositoryProvider).reconcile(entityId, a.id, cents, isoDate(date), false);
                setState(() => result = r);
              } catch (e) {
                if (ctx.mounted) showError(ctx, e);
              }
            },
            child: const Text('Comparar'),
          ),
          if (result != null && result!['differenceCents'] != 0)
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(repositoryProvider)
                      .reconcile(entityId, a.id, parseBRLToCents(ctrl.text)!, isoDate(date), true);
                  ref.read(dataVersionProvider.notifier).bump();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) showSuccess(context, 'Ajuste de conciliação registrado');
                } catch (e) {
                  if (ctx.mounted) showError(ctx, e);
                }
              },
              child: const Text('Lançar ajuste'),
            ),
        ],
      ),
    ),
  );
}
