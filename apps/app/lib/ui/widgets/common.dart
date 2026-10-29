import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../state/providers.dart';

/// Cartão nível 1 (superfície branca sobre o fundo).
class HoinkCard extends StatelessWidget {
  const HoinkCard({super.key, required this.child, this.padding = const EdgeInsets.all(24), this.color, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    // A superfície é um Material (e não um Container pintado) para que ListTiles e InkWells
    // internos mostrem fundo e ondas de toque corretamente.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(HoinkRadius.lg), boxShadow: HoinkShadows.level1),
      child: Material(
        color: color ?? HoinkColors.surfaceLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HoinkRadius.lg),
          side: const BorderSide(color: Color(0x0F103E37)),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Cartão "herói" verde-pinho com gradiente sutil (DESIGN.md › Hero Surface Tier).
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HoinkColors.pine,
        borderRadius: BorderRadius.circular(HoinkRadius.xl),
        boxShadow: HoinkShadows.level2,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            bottom: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x26B9E9CF), Color(0x00B9E9CF)]),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Valor em reais com o prefixo "R$" menor (80%), números tabulares.
class MoneyText extends StatelessWidget {
  const MoneyText(this.cents, {super.key, required this.style, this.color, this.signed = false, this.hidden = false});
  final int cents;
  final TextStyle style;
  final Color? color;
  final bool signed;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final hidden = this.hidden || Privacy.hidden;
    final c = color ?? style.color ?? HoinkColors.onSurface;
    final base = style.copyWith(color: c, fontFeatures: const [FontFeature.tabularFigures()]);
    final sign = hidden ? '' : (cents < 0 ? '-' : (signed && cents > 0 ? '+' : ''));
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${sign.isEmpty ? '' : '$sign '}R\$ ',
            style: base.copyWith(fontSize: (base.fontSize ?? 14) * 0.8, fontWeight: FontWeight.w500),
          ),
          TextSpan(text: hidden ? '••••••' : formatAmount(cents)),
        ],
      ),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: hidden ? 'Valor oculto' : formatBRL(cents, signed: signed),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.background = HoinkColors.surfaceContainer,
    this.foreground = HoinkColors.pine,
    this.size = 40,
    this.radius = 12,
  });
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius)),
    alignment: Alignment.center,
    child: Icon(icon, size: size * 0.5, color: foreground),
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.background = HoinkColors.surfaceContainer,
    this.foreground = HoinkColors.pine,
    this.icon,
    this.dot,
  });
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 4)],
        Text(label, style: HoinkText.labelSm.copyWith(color: foreground)),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'SETTLED' => const Pill('Liquidado', icon: Symbols.check, background: HoinkColors.surfaceContainer),
      'PARTIAL' => const Pill('Parcial', dot: HoinkColors.surfaceTint, background: HoinkColors.primaryFixed),
      'PENDING' => const Pill(
        'Pendente',
        dot: HoinkColors.tertiaryContainer,
        background: HoinkColors.tertiaryFixed,
        foreground: HoinkColors.onTertiaryFixed,
      ),
      'PLANNED' => const Pill(
        'Previsto',
        icon: Symbols.schedule,
        background: HoinkColors.surfaceLow,
        foreground: HoinkColors.onSurfaceVariant,
      ),
      'OVERDUE' => const Pill(
        'Atrasado',
        dot: HoinkColors.error,
        background: HoinkColors.errorContainer,
        foreground: HoinkColors.onErrorContainer,
      ),
      'CANCELED' => const Pill('Cancelado', background: HoinkColors.surfaceHigh, foreground: HoinkColors.outline),
      _ => Pill(status),
    };
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.eyebrow, this.trailing});
  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Text(
            eyebrow!.toUpperCase(),
            style: HoinkText.labelSm.copyWith(color: HoinkColors.onSurfaceVariant, letterSpacing: 1),
          ),
        Text(title, style: HoinkText.headlineMd.copyWith(color: HoinkColors.primary)),
      ],
    );
    if (trailing == null) return heading;
    // Em telas estreitas o controle vai para baixo do título, para o título não ser espremido.
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 640
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 10), trailing!],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: heading),
                trailing!,
              ],
            ),
    );
  }
}

class ProgressRail extends StatelessWidget {
  const ProgressRail({
    super.key,
    required this.value,
    this.color = HoinkColors.pine,
    this.track = HoinkColors.surfaceLow,
    this.height = 6,
  });
  final double value;
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: height, color: color, backgroundColor: track),
  );
}

/// Estado de erro com opção de tentar de novo.
class ErrorState extends StatelessWidget {
  const ErrorState(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.cloud_off, size: 40, color: HoinkColors.outline),
          const SizedBox(height: 12),
          Text(
            error is ApiException ? error.toString() : 'Algo deu errado ao carregar os dados.',
            textAlign: TextAlign.center,
            style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Tentar novamente')),
          ],
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.action});
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        const IconBadge(
          Symbols.savings,
          background: HoinkColors.tertiaryFixed,
          foreground: HoinkColors.tertiaryContainer,
          size: 56,
          radius: 28,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: HoinkText.headlineSm.copyWith(color: HoinkColors.primary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

void showError(BuildContext context, Object e) {
  final message = e is ApiException ? e.message : (e is String ? e : 'Erro inesperado: $e');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Esconde gráficos no modo privacidade: a altura das barras e linhas também revela valores.
class PrivacyBlur extends ConsumerWidget {
  const PrivacyBlur({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hideValuesProvider)) return child;
    return Semantics(
      label: 'Gráfico oculto',
      excludeSemantics: true,
      child: IgnorePointer(
        child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: child),
      ),
    );
  }
}

/// Botão do olhinho: mostra/esconde todos os valores do app.
class PrivacyToggle extends ConsumerWidget {
  const PrivacyToggle({super.key, this.color = HoinkColors.onSurfaceVariant, this.size = 20});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideValuesProvider);
    return IconButton(
      key: const Key('privacy-toggle'),
      tooltip: hidden ? 'Mostrar valores' : 'Ocultar valores',
      onPressed: () => ref.read(hideValuesProvider.notifier).toggle(),
      icon: Icon(hidden ? Symbols.visibility_off : Symbols.visibility, size: size, color: color),
    );
  }
}
