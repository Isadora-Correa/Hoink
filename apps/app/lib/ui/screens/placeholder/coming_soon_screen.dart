import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme.dart';
import '../../widgets/common.dart';

/// Módulos ainda não implementados. Mostrados de forma explícita, sem dados simulados.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.phase,
    required this.description,
  });
  final String title;
  final IconData icon;
  final String phase;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: HoinkCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  SvgPicture.asset('assets/brand/hoink-mascote.svg', height: 140, semanticsLabel: 'Mascote hoink.'),
                  const SizedBox(height: 20),
                  Pill(
                    'Em construção • $phase',
                    background: HoinkColors.tertiaryFixed,
                    foreground: HoinkColors.onTertiaryFixed,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: HoinkColors.pine),
                      const SizedBox(width: 8),
                      Text(title, style: HoinkText.headlineLg.copyWith(color: HoinkColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: HoinkText.bodyLg.copyWith(color: HoinkColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
