import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/theme.dart';
import '../../../core/api_client.dart';
import '../../../core/config.dart';
import '../../../core/money.dart';
import '../../../data/models.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/icons.dart';
import '../../widgets/user_avatar.dart';
import '../auth/auth_screens.dart' show PasswordField, validatePassword;

final _sessionsProvider = FutureProvider.autoDispose<List<SessionInfo>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(repositoryProvider).sessions();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const gap = SizedBox(height: 20);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Configurações', style: HoinkText.headlineLg.copyWith(color: HoinkColors.primary)),
                gap,
                const _ProfileCard(),
                gap,
                const _PasswordCard(),
                gap,
                const _EntitiesCard(),
                gap,
                const _CategoriesCard(),
                gap,
                const _SessionsCard(),
                gap,
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: HoinkColors.error),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                  icon: const Icon(Symbols.logout),
                  label: const Text('Sair desta sessão'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'hoink. v$appVersion • $gitSha',
                    style: HoinkText.bodySm.copyWith(color: HoinkColors.outline),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => HoinkCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(icon, size: 36, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary)),
                  if (subtitle != null)
                    Text(subtitle!, style: HoinkText.bodySm.copyWith(color: HoinkColors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard();
  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final _name = TextEditingController(text: ref.read(authProvider).value?.name);
  bool _uploading = false;

  Future<void> _pickPhoto() async {
    // Reduz no próprio aparelho para não enviar fotos enormes (limite da API: 2 MB).
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      final user = await ref.read(repositoryProvider).uploadAvatar(bytes, mime);
      ref.read(authProvider.notifier).updateUser(user);
      if (mounted) showSuccess(context, 'Foto de perfil atualizada');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      final user = await ref.read(repositoryProvider).removeAvatar();
      ref.read(authProvider.notifier).updateUser(user);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    return _Section(
      title: 'Perfil',
      subtitle: user?.email,
      icon: Symbols.person,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  const UserAvatar(radius: 40),
                  if (_uploading)
                    const Positioned.fill(child: CircularProgressIndicator(strokeWidth: 3, color: HoinkColors.pigPink)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('pick-avatar'),
                      onPressed: _uploading ? null : _pickPhoto,
                      icon: const Icon(Symbols.photo_camera, size: 18),
                      label: Text(user?.hasAvatar == true ? 'Trocar foto' : 'Adicionar foto'),
                    ),
                    if (user?.hasAvatar == true)
                      TextButton.icon(
                        onPressed: _uploading ? null : _removePhoto,
                        icon: const Icon(Symbols.delete, size: 18),
                        label: const Text('Remover'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('PNG, JPEG ou WebP, até 2 MB.', style: HoinkText.bodySm.copyWith(color: HoinkColors.outline)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () async {
                  try {
                    final u = await ref.read(repositoryProvider).updateProfile(_name.text.trim());
                    ref.read(authProvider.notifier).updateUser(u);
                    if (context.mounted) showSuccess(context, 'Perfil atualizado');
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PasswordCard extends ConsumerStatefulWidget {
  const _PasswordCard();
  @override
  ConsumerState<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends ConsumerState<_PasswordCard> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Alterar senha',
    subtitle: 'Ao trocar a senha, suas outras sessões são encerradas.',
    icon: Symbols.lock,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PasswordField(controller: _current, label: 'Senha atual'),
          const SizedBox(height: 12),
          PasswordField(controller: _next, label: 'Nova senha', validator: validatePassword),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                try {
                  await ref.read(repositoryProvider).changePassword(_current.text, _next.text);
                  _current.clear();
                  _next.clear();
                  ref.read(dataVersionProvider.notifier).bump();
                  if (context.mounted) showSuccess(context, 'Senha alterada');
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: const Text('Alterar senha'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EntitiesCard extends ConsumerWidget {
  const _EntitiesCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entitiesProvider).value ?? const [];
    final hasBusiness = ref.watch(hasBusinessProvider);
    return _Section(
      title: 'Ambientes financeiros',
      subtitle: 'A participação define quanto de cada ambiente entra na visão Consolidada (Total).',
      icon: Symbols.business_center,
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('business-toggle'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Symbols.business_center, color: HoinkColors.pine),
            title: Text('Conta profissional (PJ)', style: HoinkText.labelMd),
            subtitle: const Text('Separe as finanças da sua empresa das pessoais.'),
            value: hasBusiness,
            onChanged: (on) => on ? _enableBusiness(context, ref) : _disableBusiness(context, ref, entities),
          ),
          const Divider(),
          for (final e in entities)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.isPersonal ? Symbols.person : Symbols.business_center, color: HoinkColors.pine),
              title: Text(e.name, style: HoinkText.labelMd),
              subtitle: Text(
                '${e.isPersonal ? 'Pessoal' : 'Profissional'} • participação ${formatPercentBps(e.ownershipShareBps)}',
              ),
              trailing: e.isPersonal || e.role != 'OWNER'
                  ? null
                  : TextButton(onPressed: () => _editShare(context, ref, e), child: const Text('Editar')),
            ),
        ],
      ),
    );
  }

  Future<void> _enableBusiness(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(repositoryProvider).enableBusiness();
      ref.read(dataVersionProvider.notifier).bump();
      if (context.mounted) showSuccess(context, 'Conta profissional ativada. Use "Pro" no topo para acessá-la.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _disableBusiness(BuildContext context, WidgetRef ref, List<FinancialEntity> entities) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar conta profissional?'),
        content: const Text(
          'O ambiente PJ some do app e da visão Total, mas nada é apagado: '
          'ao reativar, contas e lançamentos voltam como estavam.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      for (final e in entities.where((e) => !e.isPersonal && e.role == 'OWNER')) {
        await ref.read(repositoryProvider).archiveEntity(e.id);
      }
      ref.read(scopeProvider.notifier).set(Scope.personal);
      ref.read(dataVersionProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _editShare(BuildContext context, WidgetRef ref, FinancialEntity e) async {
    final name = TextEditingController(text: e.name);
    final share = TextEditingController(
      text: (e.ownershipShareBps / 100).toStringAsFixed(e.ownershipShareBps % 100 == 0 ? 0 : 2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ambiente profissional'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome da empresa'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: share,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Sua participação', suffixText: '%'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final pct = double.tryParse(share.text.replaceAll(',', '.'));
    if (pct == null || pct < 0 || pct > 100) {
      if (context.mounted) {
        showError(context, ApiException(400, 'VALIDATION', 'Participação deve estar entre 0% e 100%'));
      }
      return;
    }
    try {
      await ref.read(repositoryProvider).updateEntity(e.id, {
        'name': name.text.trim(),
        'ownershipShareBps': (pct * 100).round(),
      });
      ref.read(dataVersionProvider.notifier).bump();
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }
}

class _CategoriesCard extends ConsumerWidget {
  const _CategoriesCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = ref.watch(currentEntityProvider) ?? (ref.watch(entitiesProvider).value ?? const []).firstOrNull;
    if (entity == null) return const SizedBox.shrink();
    final cats = ref.watch(categoriesProvider(entity.id)).value ?? const <Category>[];
    Widget group(String kind, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: HoinkText.labelMd.copyWith(color: HoinkColors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cats.where((c) => c.kind == kind))
              InputChip(
                avatar: Icon(categoryIcon(c.icon), size: 16, color: HoinkColors.pine),
                label: Text(c.name),
                backgroundColor: HoinkColors.surfaceLow,
                side: BorderSide.none,
                onDeleted: () async {
                  try {
                    await ref.read(repositoryProvider).archiveCategory(entity.id, c.id);
                    ref.read(dataVersionProvider.notifier).bump();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                deleteButtonTooltipMessage: 'Arquivar categoria',
              ),
            ActionChip(
              avatar: const Icon(Symbols.add, size: 16),
              label: const Text('Nova'),
              onPressed: () => _newCategory(context, ref, entity.id, kind),
            ),
          ],
        ),
      ],
    );
    return _Section(
      title: 'Categorias • ${entity.name}',
      subtitle: 'Categorias arquivadas continuam nos lançamentos antigos.',
      icon: Symbols.category,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [group('EXPENSE', 'Despesas'), const SizedBox(height: 16), group('INCOME', 'Receitas')],
      ),
    );
  }

  Future<void> _newCategory(BuildContext context, WidgetRef ref, String entityId, String kind) async {
    final name = TextEditingController();
    var icon = 'category';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(kind == 'INCOME' ? 'Nova categoria de receita' : 'Nova categoria de despesa'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final n in categoryIconNames)
                      IconButton(
                        isSelected: n == icon,
                        style: IconButton.styleFrom(
                          backgroundColor: n == icon ? HoinkColors.pine : HoinkColors.surfaceLow,
                        ),
                        color: n == icon ? HoinkColors.ivory : HoinkColors.pine,
                        icon: Icon(categoryIcon(n), size: 18),
                        onPressed: () => setState(() => icon = n),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(repositoryProvider).createCategory(entityId, {
        'name': name.text.trim(),
        'kind': kind,
        'icon': icon,
      });
      ref.read(dataVersionProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _SessionsCard extends ConsumerWidget {
  const _SessionsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(_sessionsProvider);
    final fmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    return _Section(
      title: 'Sessões ativas',
      subtitle: 'Dispositivos conectados à sua conta.',
      icon: Symbols.devices,
      child: sessions.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => ErrorState(e),
        data: (list) => Column(
          children: [
            for (final s in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(s.current ? Symbols.smartphone : Symbols.devices_other, color: HoinkColors.pine),
                title: Text(_device(s.userAgent), style: HoinkText.labelMd),
                subtitle: Text('Último uso: ${fmt.format(s.lastUsedAt.toLocal())}'),
                trailing: s.current
                    ? const Pill('Esta sessão')
                    : TextButton(
                        onPressed: () async {
                          await ref.read(repositoryProvider).revokeSession(s.id);
                          ref.invalidate(_sessionsProvider);
                        },
                        child: const Text('Encerrar'),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  String _device(String? ua) {
    if (ua == null) return 'Dispositivo';
    if (ua.contains('Dart')) return 'App hoink.';
    for (final b in ['Edg', 'Chrome', 'Firefox', 'Safari']) {
      if (ua.contains(b)) return 'Navegador ${b == 'Edg' ? 'Edge' : b}';
    }
    return 'Dispositivo';
  }
}
