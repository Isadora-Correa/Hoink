import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/providers.dart';

/// Foto de perfil do usuário logado; mostra as iniciais quando não há foto.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, this.radius = 18});
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final bytes = ref.watch(avatarProvider).value;
    return CircleAvatar(
      radius: radius,
      backgroundColor: HoinkColors.pine,
      foregroundImage: bytes == null ? null : MemoryImage(bytes),
      child: Text(
        user?.initials ?? '',
        style: HoinkText.labelMd.copyWith(color: HoinkColors.ivory, fontSize: radius * 0.7),
      ),
    );
  }
}
