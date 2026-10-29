import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'common.dart';

final notificationsProvider = FutureProvider<({int unread, List<AppNotification> items})>((ref) async {
  ref.watch(dataVersionProvider);
  await ref.watch(entitiesProvider.future);
  return ref.read(repositoryProvider).notifications();
});

/// Sino de notificações (contas vencendo, orçamentos, saldo negativo previsto).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    return IconButton(
      key: const Key('notifications'),
      tooltip: unread == 0 ? 'Notificações' : '$unread notificações não lidas',
      onPressed: () => _open(context, ref),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: HoinkColors.pigPink,
        textColor: HoinkColors.onTertiaryFixed,
        child: const Icon(Symbols.notifications, color: HoinkColors.onSurfaceVariant),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final data = ref.watch(notificationsProvider);
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Notificações')),
                TextButton(
                  onPressed: () async {
                    await repo.markAllNotificationsRead();
                    ref.invalidate(notificationsProvider);
                  },
                  child: const Text('Marcar todas como lidas'),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 420,
              child: data.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(e),
                data: (d) => d.items.isEmpty
                    ? const EmptyState(
                        title: 'Tudo em dia',
                        message: 'Avisos de contas, orçamentos e saldo aparecem aqui.',
                      )
                    : ListView.separated(
                        itemCount: d.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = d.items[i];
                          final color = switch (n.severity) {
                            'danger' => HoinkColors.error,
                            'warning' => HoinkColors.tertiaryContainer,
                            'success' => HoinkColors.surfaceTint,
                            _ => HoinkColors.pine,
                          };
                          return ListTile(
                            leading: Icon(
                              n.severity == 'danger' ? Symbols.error : Symbols.notifications_active,
                              color: color,
                              fill: n.read ? 0 : 1,
                            ),
                            title: Text(n.title, style: n.read ? HoinkText.bodyMd : HoinkText.labelMd),
                            subtitle: Text(n.body),
                            onTap: () async {
                              await repo.markNotificationRead(n.id);
                              ref.invalidate(notificationsProvider);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (n.link != null && context.mounted) context.push(n.link!);
                            },
                          );
                        },
                      ),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
          );
        },
      ),
    );
  }
}
