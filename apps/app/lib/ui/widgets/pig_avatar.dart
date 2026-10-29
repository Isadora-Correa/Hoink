import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// O porquinho da marca (mascote), usado como rosto da Costelinha.
class PigAvatar extends StatelessWidget {
  const PigAvatar({super.key, this.size = 40, this.background = true});
  final double size;

  /// Com fundo rosa claro arredondado (avatar) ou só o porquinho (ícone do menu).
  final bool background;

  @override
  Widget build(BuildContext context) {
    final pig = SvgPicture.asset(
      'assets/brand/hoink-mascote.svg',
      width: background ? size * 0.8 : size,
      height: background ? size * 0.8 : size,
      semanticsLabel: 'Costelinha',
    );
    if (!background) return pig;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFFFFE9EE), borderRadius: BorderRadius.circular(size * 0.3)),
      alignment: Alignment.center,
      child: pig,
    );
  }
}
