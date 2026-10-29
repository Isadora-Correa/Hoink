import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/providers.dart';

/// Alternador de ambiente Pessoal / Pro / Total (DESIGN.md › Environment Switcher).
class ScopeSwitcher extends ConsumerWidget {
  const ScopeSwitcher({super.key, this.compact = false, this.expand = false});
  final bool compact;
  final bool expand;

  static const _labels = {Scope.personal: 'Pessoal', Scope.business: 'Pro', Scope.total: 'Total'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sem conta profissional não há o que alternar.
    if (!ref.watch(hasBusinessProvider)) return const SizedBox.shrink();
    final scope = ref.watch(scopeProvider);
    final items = Scope.values.map((s) {
      final active = s == scope;
      final pill = AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: expand ? 4 : (compact ? 12 : 14), vertical: compact ? 6 : 7),
        decoration: BoxDecoration(
          color: active ? HoinkColors.pine : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          _labels[s]!,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: HoinkText.labelMd.copyWith(color: active ? HoinkColors.ivory : HoinkColors.onSurfaceVariant),
        ),
      );
      final button = Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(scopeProvider.notifier).set(s),
          child: MouseRegion(cursor: SystemMouseCursors.click, child: pill),
        ),
      );
      return expand ? Expanded(child: button) : button;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: HoinkColors.surfaceLow, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: items),
    );
  }
}
