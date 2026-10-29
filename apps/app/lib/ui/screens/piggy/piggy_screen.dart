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
import '../../widgets/pig_avatar.dart';

final piggyBanksProvider = FutureProvider.family<List<PiggyBank>, String>((ref, entityId) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).piggyBanks(entityId);
});

final piggyBankProvider = FutureProvider.family<PiggyBank, ({String entityId, String id})>((ref, a) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).piggyBank(a.entityId, a.id);
});

final gamificationProvider = FutureProvider<GamificationProfile>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).gamification();
});

/// Ícones disponíveis para os cofrinhos (lista de desejos e metas).
const piggyIcons = <String, IconData>{
  'savings': Symbols.savings,
  'health_and_safety': Symbols.health_and_safety,
  'sports_esports': Symbols.sports_esports,
  'flight': Symbols.flight,
  'directions_car': Symbols.directions_car,
  'home': Symbols.home,
  'beach_access': Symbols.beach_access,
  'devices': Symbols.devices,
  'school': Symbols.school,
  'favorite': Symbols.favorite,
  'pets': Symbols.pets,
  'celebration': Symbols.celebration,
};

IconData piggyIcon(String name) => piggyIcons[name] ?? Symbols.savings;

const _achievementIcons = <String, IconData>{
  'savings': Symbols.savings,
  'favorite': Symbols.favorite,
  'paid': Symbols.paid,
  'flag': Symbols.flag,
  'emoji_events': Symbols.emoji_events,
  'celebration': Symbols.celebration,
  'local_fire_department': Symbols.local_fire_department,
};

/// Mostra as conquistas recém-desbloqueadas.
Future<void> celebrate(BuildContext context, List<Achievement> unlocked) async {
  if (unlocked.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Symbols.emoji_events, size: 48, color: HoinkColors.pigPink, fill: 1),
      title: Text(unlocked.length == 1 ? 'Conquista desbloqueada!' : '${unlocked.length} conquistas desbloqueadas!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in unlocked)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _AchievementBadge(a.icon, size: 40),
              title: Text(a.title, style: HoinkText.labelMd),
              subtitle: Text([a.description, ?a.piggyName].join(' • ')),
              trailing: Text('+${a.points}', style: HoinkText.labelMd.copyWith(color: HoinkColors.surfaceTint)),
            ),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Oba!'))],
    ),
  );
}

/// Meus Cofrinhos: reservas, metas e lista de desejos, com gamificação.
class PiggyScreen extends ConsumerStatefulWidget {
  const PiggyScreen({super.key});
  @override
  ConsumerState<PiggyScreen> createState() => _PiggyScreenState();
}

class _PiggyScreenState extends ConsumerState<PiggyScreen> {
  String _tab = 'ALL';

  @override
  Widget build(BuildContext context) {
    final entity = ref.watch(currentEntityProvider) ?? (ref.watch(entitiesProvider).value ?? const []).firstOrNull;
    if (entity == null) return const Center(child: CircularProgressIndicator());
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ModulePage(
      title: 'Meus Cofrinhos',
      subtitle: 'Separe dinheiro para cada sonho. Guardar é uma transferência do seu saldo: nada é contado duas vezes.',
      maxWidth: 1200,
      action: entity.canWrite
          ? FilledButton.icon(
              key: const Key('new-piggy'),
              onPressed: () => showPiggyForm(context, ref, entity.id),
              icon: const Icon(Symbols.add_circle, size: 18),
              label: Text(wide ? 'Novo cofrinho' : 'Novo'),
            )
          : null,
      children: [
        ref
            .watch(piggyBanksProvider(entity.id))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(piggyBanksProvider(entity.id))),
              data: (all) {
                final active = all.where((p) => !p.achieved).toList();
                final done = all.where((p) => p.achieved).toList();
                final shown = active
                    .where(
                      (p) => switch (_tab) {
                        'WISH' => p.kind == 'WISH',
                        'SAVE' => p.kind != 'WISH',
                        _ => true,
                      },
                    )
                    .toList();
                final hero = _Hero(piggies: active);
                const game = _GamificationCard();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: hero),
                            const SizedBox(width: 16),
                            const Expanded(flex: 2, child: game),
                          ],
                        ),
                      )
                    else ...[
                      hero,
                      const SizedBox(height: 16),
                      game,
                    ],
                    const SizedBox(height: 28),
                    SectionTitle(
                      'Meus objetivos',
                      eyebrow: '${active.length} ativos',
                      trailing: SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: HoinkColors.pine,
                          selectedForegroundColor: HoinkColors.ivory,
                        ),
                        segments: const [
                          ButtonSegment(value: 'ALL', label: Text('Todos')),
                          ButtonSegment(value: 'WISH', label: Text('Desejos')),
                          ButtonSegment(value: 'SAVE', label: Text('Reservas e metas')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (s) => setState(() => _tab = s.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (shown.isEmpty)
                      HoinkCard(
                        child: EmptyState(
                          title: _tab == 'WISH' ? 'Sua lista de desejos está vazia' : 'Nenhum cofrinho ainda',
                          message: 'Que tal começar? Um PS5, uma viagem, o carro novo ou a reserva de emergência.',
                          action: entity.canWrite
                              ? FilledButton(
                                  onPressed: () =>
                                      showPiggyForm(context, ref, entity.id, kind: _tab == 'WISH' ? 'WISH' : 'GOAL'),
                                  child: Text(_tab == 'WISH' ? 'Adicionar desejo' : 'Criar cofrinho'),
                                )
                              : null,
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, c) {
                          final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 620 ? 2 : 1);
                          final w = (c.maxWidth - (cols - 1) * 16) / cols;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final p in shown)
                                SizedBox(
                                  width: w,
                                  child: _PiggyCard(piggy: p),
                                ),
                            ],
                          );
                        },
                      ),
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: const Icon(Symbols.celebration, color: HoinkColors.pigPink),
                        title: Text('Desejos realizados (${done.length})', style: HoinkText.labelMd),
                        children: [
                          for (final p in done)
                            ListTile(
                              leading: IconBadge(piggyIcon(p.icon)),
                              title: Text(p.name),
                              subtitle: Text('Realizado em ${formatBrDate(p.achievedAt!)}'),
                              onTap: () => context.push('/cofrinhos/${p.entityId}/${p.id}'),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.piggies});
  final List<PiggyBank> piggies;

  @override
  Widget build(BuildContext context) {
    final total = piggies.fold<int>(0, (s, p) => s + p.balanceCents);
    final estimated = piggies.fold<int>(0, (s, p) => s + p.estimatedYieldCents);
    final effective = piggies.fold<int>(0, (s, p) => s + p.effectiveYieldCents);
    final withGoal = piggies.where((p) => p.goalCents != null && p.progressBps != null).toList()
      ..sort((a, b) => b.progressBps!.compareTo(a.progressBps!));
    final next = withGoal.where((p) => p.progressBps! > 0 && p.progressBps! < 10000).firstOrNull;
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL GUARDADO • ${piggies.length} ${piggies.length == 1 ? 'COFRINHO' : 'COFRINHOS'}',
            style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer, letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),
          MoneyText(total, style: HoinkText.displayHero.copyWith(fontSize: 40), color: Colors.white),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [_HeroStat('Rendimento confirmado', effective), _HeroStat('Rendimento estimado*', estimated)],
          ),
          if (next != null) ...[
            const SizedBox(height: 16),
            Text(
              'Mais perto de realizar: ${next.name} (${formatPercentBps(next.progressBps!)})',
              style: HoinkText.bodySm.copyWith(color: HoinkColors.mint),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '* Estimativa pela taxa atual do índice; rendimento passado não garante rendimento futuro.',
            style: HoinkText.bodySm.copyWith(color: HoinkColors.primaryFixedDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.label, this.cents);
  final String label;
  final int cents;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: HoinkText.labelSm.copyWith(color: HoinkColors.onPrimaryContainer)),
      MoneyText(cents, signed: true, style: HoinkText.headlineSm, color: HoinkColors.mint),
    ],
  );
}

class _GamificationCard extends ConsumerWidget {
  const _GamificationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(gamificationProvider)
        .when(
          loading: () => const HoinkCard(child: Center(child: CircularProgressIndicator())),
          error: (e, _) => HoinkCard(child: ErrorState(e)),
          data: (g) => HoinkCard(
            key: const Key('gamification'),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PigAvatar(size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NÍVEL ${g.level}',
                            style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant),
                          ),
                          Text(g.levelName, style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                        ],
                      ),
                    ),
                    Text('${g.points} pts', style: HoinkText.labelMd.copyWith(color: HoinkColors.surfaceTint)),
                  ],
                ),
                const SizedBox(height: 12),
                ProgressRail(value: g.progressBps / 10000, color: HoinkColors.pigPink),
                const SizedBox(height: 4),
                Text(
                  g.nextLevelName == null ? 'Nível máximo!' : 'Faltam ${g.pointsToNext} pts para ${g.nextLevelName}',
                  style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Symbols.local_fire_department,
                      fill: g.streakCurrent > 0 ? 1 : 0,
                      color: g.streakCurrent > 0 ? HoinkColors.pigPink : HoinkColors.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        g.streakCurrent == 0
                            ? 'Guarde algo esta semana para começar uma sequência'
                            : '${g.streakCurrent} ${g.streakCurrent == 1 ? 'semana' : 'semanas'} seguidas guardando'
                                  '${g.depositedThisWeek ? '' : ' • guarde esta semana para manter!'}',
                        style: HoinkText.bodySm,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in g.unlocked.take(6))
                      Tooltip(
                        message: '${a.title}${a.piggyName == null ? '' : ' • ${a.piggyName}'}',
                        child: _AchievementBadge(a.icon, size: 32),
                      ),
                    for (final a in g.locked.take(3))
                      Tooltip(
                        message: 'Bloqueada: ${a.description}',
                        child: const IconBadge(Symbols.lock, size: 32, radius: 16, foreground: HoinkColors.outline),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
  }
}

class _PiggyCard extends ConsumerWidget {
  const _PiggyCard({required this.piggy});
  final PiggyBank piggy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = piggy;
    final wish = p.kind == 'WISH';
    final pct = p.progressBps;
    return HoinkCard(
      padding: const EdgeInsets.all(20),
      onTap: () => context.push('/cofrinhos/${p.entityId}/${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                piggyIcon(p.icon),
                background: wish ? HoinkColors.tertiaryFixed : HoinkColors.surfaceContainer,
                foreground: wish ? HoinkColors.tertiaryContainer : HoinkColors.pine,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [piggyKindLabels[p.kind]!.toUpperCase(), if (wish && p.priority == 1) 'PRIORIDADE'].join(' • '),
                      style: HoinkText.labelSm.copyWith(color: HoinkColors.surfaceTint),
                    ),
                    Text(p.name, style: HoinkText.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (pct != null && pct >= 5000 && pct < 10000)
                const Pill('Metade superada!', background: HoinkColors.tertiaryFixed),
              if (pct != null && pct >= 10000) const Pill('Meta batida!', icon: Symbols.emoji_events),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Guardado', style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
              const Spacer(),
              if (p.goalCents != null)
                Text(
                  'Meta: ${formatBRL(p.goalCents!)}',
                  style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(child: MoneyText(p.balanceCents, style: HoinkText.headlineMd)),
              if (pct != null) Pill(formatPercentBps(pct), background: HoinkColors.primaryFixed),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 10),
            ProgressRail(value: pct / 10000, color: wish ? HoinkColors.pigPink : HoinkColors.pine, height: 8),
            const SizedBox(height: 6),
            Text(
              [
                if ((p.missingCents ?? 0) > 0) 'Faltam ${formatBRL(p.missingCents!)}',
                if (p.monthlyNeededCents != null && (p.missingCents ?? 0) > 0)
                  '${formatBRL(p.monthlyNeededCents!)}/mês até ${formatBrDate(p.targetDate!)}',
              ].join(' • '),
              style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
            ),
          ],
          if (p.yieldKind != 'NONE') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HoinkColors.surfaceLow,
                borderRadius: BorderRadius.circular(HoinkRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Symbols.trending_up, size: 18, color: HoinkColors.surfaceTint),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.yieldLabel, style: HoinkText.bodySm)),
                  if (p.estimatedYieldCents > 0)
                    Text(
                      '+${formatBRL(p.estimatedYieldCents)} est.',
                      style: HoinkText.labelSm.copyWith(color: HoinkColors.surfaceTint),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: Key('deposit-${p.id}'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => showPiggyMove(context, ref, p, deposit: true),
                icon: const Icon(Symbols.add, size: 18),
                label: const Text('Guardar'),
              ),
              if (p.balanceCents > 0)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => showPiggyMove(context, ref, p, deposit: false),
                  icon: const Icon(Symbols.move_up, size: 18),
                  label: const Text('Resgatar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cadastro/edição de cofrinho ou desejo.
Future<void> showPiggyForm(
  BuildContext context,
  WidgetRef ref,
  String entityId, {
  PiggyBank? piggy,
  String kind = 'WISH',
}) async {
  final name = TextEditingController(text: piggy?.name);
  final goal = TextEditingController(text: piggy?.goalCents == null ? '' : formatAmount(piggy!.goalCents!));
  final link = TextEditingController(text: piggy?.link);
  final institution = TextEditingController(text: piggy?.institution);
  final rate = TextEditingController(
    text: piggy == null || piggy.yieldRateBps == 0 ? '' : (piggy.yieldRateBps / 100).toString().replaceAll('.', ','),
  );
  var k = piggy?.kind ?? kind;
  var icon = piggy?.icon ?? (k == 'RESERVE' ? 'health_and_safety' : 'favorite');
  var priority = piggy?.priority ?? 3;
  var yieldKind = piggy?.yieldKind ?? 'NONE';
  DateTime? target = piggy?.targetDate == null ? null : parseIso(piggy!.targetDate!);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(piggy == null ? 'Novo cofrinho' : 'Editar cofrinho'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'WISH', label: Text('Desejo'), icon: Icon(Symbols.favorite, size: 16)),
                    ButtonSegment(value: 'GOAL', label: Text('Meta'), icon: Icon(Symbols.flag, size: 16)),
                    ButtonSegment(value: 'RESERVE', label: Text('Reserva'), icon: Icon(Symbols.shield, size: 16)),
                  ],
                  selected: {k},
                  onSelectionChanged: (s) => setState(() => k = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('piggy-name'),
                  controller: name,
                  decoration: InputDecoration(
                    labelText: k == 'WISH' ? 'O que você quer comprar?' : 'Nome do cofrinho',
                    hintText: k == 'WISH' ? 'Ex.: PS5 para o namorado' : 'Ex.: Viagem, carro, casa',
                  ),
                ),
                const SizedBox(height: 12),
                MoneyField(
                  controller: goal,
                  label: k == 'WISH' ? 'Quanto custa?' : 'Meta (opcional)',
                  fieldKey: const Key('piggy-goal'),
                ),
                if (k == 'WISH') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Link do produto (opcional)', hintText: 'https://...'),
                  ),
                  const SizedBox(height: 12),
                  Text('Prioridade', style: HoinkText.labelMd),
                  Slider(
                    value: (6 - priority).toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: priority == 1 ? 'Muito alta' : (priority >= 4 ? 'Baixa' : 'Média'),
                    onChanged: (v) => setState(() => priority = 6 - v.round()),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Symbols.event, size: 18),
                  label: Text(target == null ? 'Data-alvo (opcional)' : 'Quero até ${formatBrDate(isoDate(target!))}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: target ?? DateTime.now().add(const Duration(days: 180)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => target = d);
                  },
                ),
                const SizedBox(height: 12),
                Text('Ícone', style: HoinkText.labelMd),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in piggyIcons.entries)
                      ChoiceChip(
                        label: Icon(e.value, size: 18),
                        selected: icon == e.key,
                        onSelected: (_) => setState(() => icon = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: yieldKind,
                  decoration: const InputDecoration(labelText: 'Onde o dinheiro rende'),
                  items: const [
                    DropdownMenuItem(value: 'NONE', child: Text('Não rende')),
                    DropdownMenuItem(value: 'CDI_PERCENT', child: Text('% do CDI')),
                    DropdownMenuItem(value: 'SELIC_PERCENT', child: Text('% da Selic')),
                    DropdownMenuItem(value: 'PREFIXED', child: Text('Prefixado (% ao ano)')),
                    DropdownMenuItem(value: 'MANUAL', child: Text('Informo o saldo do banco')),
                  ],
                  onChanged: (v) => setState(() => yieldKind = v!),
                ),
                if (yieldKind == 'CDI_PERCENT' || yieldKind == 'SELIC_PERCENT' || yieldKind == 'PREFIXED') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: yieldKind == 'PREFIXED' ? 'Taxa ao ano' : 'Percentual do índice',
                      suffixText: yieldKind == 'PREFIXED' ? '% a.a.' : '%',
                      hintText: yieldKind == 'PREFIXED' ? '12' : '115',
                      helperText: 'Taxa contratada no banco — não é garantia de rendimento futuro.',
                    ),
                  ),
                ],
                if (yieldKind != 'NONE') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: institution,
                    decoration: const InputDecoration(labelText: 'Banco (opcional)'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('save-piggy'),
            onPressed: () async {
              final goalCents = goal.text.trim().isEmpty ? null : parseBRLToCents(goal.text);
              final rateBps = rate.text.trim().isEmpty
                  ? 0
                  : ((double.tryParse(rate.text.replaceAll(',', '.')) ?? -1) * 100).round();
              if (name.text.trim().isEmpty) return showError(ctx, 'Dê um nome ao cofrinho');
              if (k == 'WISH' && (goalCents == null || goalCents <= 0)) return showError(ctx, 'Informe quanto custa');
              if (rateBps < 0) return showError(ctx, 'Taxa inválida');
              final body = {
                'kind': k,
                'name': name.text.trim(),
                'goalCents': goalCents,
                'link': k == 'WISH' && link.text.trim().isNotEmpty ? link.text.trim() : null,
                'priority': priority,
                'icon': icon,
                'targetDate': target == null ? null : isoDate(target!),
                'yieldKind': yieldKind,
                'yieldRateBps': rateBps,
                'institution': institution.text.trim().isEmpty ? null : institution.text.trim(),
              };
              try {
                final r = await ref.read(repositoryProvider).savePiggy(entityId, body, id: piggy?.id);
                ref.read(dataVersionProvider.notifier).bump();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (context.mounted) {
                  showSuccess(context, piggy == null ? 'Cofrinho criado' : 'Cofrinho atualizado');
                  await celebrate(context, r.unlocked);
                }
              } catch (e) {
                if (ctx.mounted) showError(ctx, e);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

/// Guardar (da conta para o cofrinho) ou resgatar (do cofrinho para a conta).
Future<void> showPiggyMove(BuildContext context, WidgetRef ref, PiggyBank p, {required bool deposit}) async {
  final accounts = (await ref.read(accountsProvider(p.entityId).future)).where((a) => !a.archived).toList();
  if (!context.mounted) return;
  final amount = TextEditingController();
  var accountId = accounts.firstOrNull?.id;
  var date = DateTime.now();
  final quick = deposit ? [5000, 10000, 20000, 50000] : <int>[];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(deposit ? 'Guardar em ${p.name}' : 'Resgatar de ${p.name}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!deposit) Text('Saldo do cofrinho: ${formatBRL(p.balanceCents)}', style: HoinkText.bodyMd),
              if (deposit && p.missingCents != null && p.missingCents! > 0)
                Text('Faltam ${formatBRL(p.missingCents!)} para a meta', style: HoinkText.bodyMd),
              const SizedBox(height: 12),
              MoneyField(controller: amount, label: 'Valor', fieldKey: const Key('piggy-amount')),
              if (quick.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in quick)
                      ActionChip(
                        label: Text(formatBRL(c)),
                        onPressed: () => setState(() => amount.text = formatAmount(c)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: accountId,
                decoration: InputDecoration(labelText: deposit ? 'Tirar da conta' : 'Mandar para a conta'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${formatBRL(a.balanceCents)})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => accountId = v),
              ),
              const SizedBox(height: 12),
              DateField(label: 'Data', value: date, onChanged: (d) => setState(() => date = d)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirm-piggy-move'),
            onPressed: () async {
              final cents = parseBRLToCents(amount.text);
              if (accountId == null || cents == null || cents <= 0) return showError(ctx, 'Informe o valor e a conta');
              try {
                final r = await ref.read(repositoryProvider).piggyAction(
                  p.entityId,
                  p.id,
                  deposit ? 'deposit' : 'withdraw',
                  {'accountId': accountId, 'amountCents': cents, 'date': isoDate(date)},
                );
                ref.read(dataVersionProvider.notifier).bump();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (context.mounted) {
                  showSuccess(context, deposit ? 'Guardado! 🐷' : 'Resgate registrado');
                  await celebrate(context, r.unlocked);
                }
              } catch (e) {
                if (ctx.mounted) showError(ctx, e);
              }
            },
            child: Text(deposit ? 'Guardar' : 'Resgatar'),
          ),
        ],
      ),
    ),
  );
}

/// Detalhe do cofrinho: rendimento (confirmado × estimado × líquido), simulação e movimentações.
class PiggyDetailScreen extends ConsumerStatefulWidget {
  const PiggyDetailScreen({super.key, required this.entityId, required this.piggyId});
  final String entityId;
  final String piggyId;
  @override
  ConsumerState<PiggyDetailScreen> createState() => _PiggyDetailScreenState();
}

class _PiggyDetailScreenState extends ConsumerState<PiggyDetailScreen> {
  final _monthly = TextEditingController(text: '200,00');
  PiggySimulation? _sim;

  Future<void> _simulate(PiggyBank p) async {
    final cents = parseBRLToCents(_monthly.text) ?? 0;
    try {
      final s = await ref.read(repositoryProvider).simulatePiggy(p.entityId, p.id, cents, 24);
      setState(() => _sim = s);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(piggyBankProvider((entityId: widget.entityId, id: widget.piggyId)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e),
          data: (p) {
            final sim = _sim;
            return ModulePage(
              title: p.name,
              subtitle: [piggyKindLabels[p.kind]!, p.yieldLabel, ?p.institution].join(' • '),
              leading: IconButton(onPressed: () => context.go('/cofrinhos'), icon: const Icon(Symbols.arrow_back)),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    KpiTile('Guardado', p.balanceCents, icon: Symbols.savings),
                    KpiTile('Principal aportado', p.principalCents, icon: Symbols.payments),
                    KpiTile('Rendimento confirmado', p.effectiveYieldCents, icon: Symbols.verified),
                    if (p.goalCents != null) KpiTile('Meta', p.goalCents!, icon: Symbols.flag),
                  ],
                ),
                const SizedBox(height: 16),
                if (p.yieldKind != 'NONE')
                  HoinkCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Rendimento', style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                        const SizedBox(height: 8),
                        ValueRow('Saldo confirmado', p.balanceCents),
                        ValueRow('Rendimento estimado desde a última confirmação', p.estimatedYieldCents),
                        ValueRow('Saldo bruto estimado', p.grossEstimatedCents, bold: true),
                        ValueRow('IR/IOF estimados no resgate', -p.taxEstimatedCents),
                        ValueRow('Saldo líquido estimado', p.netEstimatedCents, bold: true),
                        const SizedBox(height: 8),
                        Text(
                          p.estimateAvailable == false
                              ? 'Sem dados do índice para estimar. Confirme o saldo pelo extrato do banco.'
                              : 'Estimativa com a taxa do índice${p.ratesUpTo == null ? '' : ' até ${formatBrDate(p.ratesUpTo!)}'} '
                                    '(Banco Central). Não é garantia de rendimento.',
                          style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const Key('confirm-yield'),
                            onPressed: () => _confirmYield(p),
                            icon: const Icon(Symbols.fact_check, size: 18),
                            label: const Text('Confirmar saldo do banco'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!p.achieved) ...[
                      FilledButton.icon(
                        onPressed: () => showPiggyMove(context, ref, p, deposit: true),
                        icon: const Icon(Symbols.add, size: 18),
                        label: const Text('Guardar'),
                      ),
                      if (p.balanceCents > 0)
                        OutlinedButton.icon(
                          onPressed: () => showPiggyMove(context, ref, p, deposit: false),
                          icon: const Icon(Symbols.move_up, size: 18),
                          label: const Text('Resgatar'),
                        ),
                      if (p.kind == 'WISH' || p.kind == 'GOAL')
                        OutlinedButton.icon(
                          key: const Key('achieve-piggy'),
                          onPressed: () => _achieve(p),
                          icon: const Icon(Symbols.celebration, size: 18),
                          label: Text(p.kind == 'WISH' ? 'Comprei!' : 'Realizei!'),
                        ),
                    ],
                    TextButton.icon(
                      onPressed: () => showPiggyForm(context, ref, p.entityId, piggy: p),
                      icon: const Icon(Symbols.edit, size: 18),
                      label: const Text('Editar'),
                    ),
                    if (p.balanceCents == 0)
                      TextButton(
                        onPressed: () async {
                          final ok = await runAction(
                            context,
                            ref,
                            () => ref.read(repositoryProvider).archivePiggy(p.entityId, p.id),
                            'Cofrinho arquivado',
                          );
                          if (ok && context.mounted) context.go('/cofrinhos');
                        },
                        child: const Text('Arquivar'),
                      ),
                  ],
                ),
                if (p.link != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'Produto: ${p.link}',
                    style: HoinkText.bodySm.copyWith(color: HoinkColors.surfaceTint),
                  ),
                ],
                if (!p.achieved) ...[
                  const SizedBox(height: 24),
                  const SectionTitle('Simular', eyebrow: 'Estimativa'),
                  const SizedBox(height: 8),
                  HoinkCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: MoneyField(controller: _monthly, label: 'Guardando por mês'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(onPressed: () => _simulate(p), child: const Text('Simular')),
                          ],
                        ),
                        if (sim != null) ...[
                          const SizedBox(height: 12),
                          if (sim.monthsToGoal != null)
                            Text(
                              sim.monthsToGoal == 0
                                  ? 'Você já tem o valor da meta!'
                                  : 'Você chega na meta em ${sim.monthsToGoal} ${sim.monthsToGoal == 1 ? 'mês' : 'meses'}',
                              style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary),
                            ),
                          ValueRow('Em 12 meses', sim.points[11].balanceCents),
                          ValueRow('Em 24 meses', sim.points.last.balanceCents),
                          Text(
                            sim.rateAvailable
                                ? 'Considera ${(sim.annualRatePct ?? 0).toStringAsFixed(2).replaceAll('.', ',')}% a.a. (taxa atual, sem garantia) e não desconta impostos.'
                                : 'Sem taxa disponível: simulação sem rendimento.',
                            style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const SectionTitle('Movimentações'),
                const SizedBox(height: 8),
                HoinkCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: p.movements.isEmpty
                      ? const EmptyState(title: 'Nada guardado ainda', message: 'Use "Guardar" para começar.')
                      : Column(
                          children: [
                            for (final m in p.movements)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: IconBadge(switch (m.kind) {
                                  'DEPOSIT' => Symbols.add,
                                  'WITHDRAWAL' => Symbols.move_up,
                                  'YIELD' => Symbols.trending_up,
                                  _ => Symbols.tune,
                                }),
                                title: Text(switch (m.kind) {
                                  'DEPOSIT' => 'Guardado',
                                  'WITHDRAWAL' => 'Resgatado',
                                  'YIELD' => 'Rendimento',
                                  _ => 'Ajuste',
                                }),
                                subtitle: Text(formatBrDate(m.date)),
                                trailing: MoneyText(
                                  m.cents,
                                  signed: true,
                                  style: HoinkText.labelMd,
                                  color: m.cents >= 0 ? HoinkColors.surfaceTint : HoinkColors.onSurface,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
  }

  Future<void> _confirmYield(PiggyBank p) async {
    final amount = TextEditingController(text: formatAmount(p.grossEstimatedCents));
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Confirmar saldo do banco'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Informe o saldo que aparece no app do banco. A diferença vira o rendimento confirmado.'),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Saldo no banco'),
                const SizedBox(height: 12),
                DateField(label: 'Data', value: date, onChanged: (d) => setState(() => date = d)),
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
    if (ok != true || cents == null || !mounted) return;
    try {
      final r = await ref.read(repositoryProvider).piggyAction(p.entityId, p.id, 'yield', {
        'date': isoDate(date),
        'balanceCents': cents,
      });
      ref.read(dataVersionProvider.notifier).bump();
      if (mounted) {
        showSuccess(context, 'Saldo confirmado');
        await celebrate(context, r.unlocked);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _achieve(PiggyBank p) async {
    final accounts = (await ref.read(accountsProvider(p.entityId).future)).where((a) => !a.archived).toList();
    if (!mounted) return;
    final price = TextEditingController(text: formatAmount(p.goalCents ?? p.balanceCents));
    var accountId = accounts.firstOrNull?.id;
    var registerPurchase = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Symbols.celebration, size: 40, color: HoinkColors.pigPink),
          title: Text(p.kind == 'WISH' ? 'Comprou ${p.name}?' : 'Realizou ${p.name}?'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('O saldo de ${formatBRL(p.balanceCents)} volta para a conta escolhida.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Conta'),
                  items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                  onChanged: (v) => setState(() => accountId = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: registerPurchase,
                  onChanged: (v) => setState(() => registerPurchase = v),
                  title: const Text('Lançar a compra como despesa'),
                  subtitle: const Text('Guardar não foi despesa; a compra é.'),
                ),
                if (registerPurchase) MoneyField(controller: price, label: 'Valor pago'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ainda não')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sim! 🎉')),
          ],
        ),
      ),
    );
    if (ok != true || accountId == null || !mounted) return;
    try {
      final r = await ref.read(repositoryProvider).piggyAction(p.entityId, p.id, 'achieve', {
        'accountId': accountId,
        'date': isoDate(DateTime.now()),
        if (registerPurchase) 'purchaseCents': parseBRLToCents(price.text),
        'description': p.name,
      });
      ref.read(dataVersionProvider.notifier).bump();
      if (mounted) await celebrate(context, r.unlocked);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}

/// Medalha de conquista: as de cofrinho usam o porquinho da marca; as demais, um ícone.
class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge(this.icon, {required this.size});
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (icon == 'savings') {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: HoinkColors.tertiaryFixed, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: PigAvatar(size: size * 0.72, background: false),
      );
    }
    return IconBadge(
      _achievementIcons[icon] ?? Symbols.star,
      size: size,
      radius: size / 2,
      background: HoinkColors.tertiaryFixed,
      foreground: HoinkColors.tertiaryContainer,
    );
  }
}
