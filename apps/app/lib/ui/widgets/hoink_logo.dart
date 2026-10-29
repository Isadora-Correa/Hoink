import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Logotipo "hoink." baseado em `hoink-logo-principal.svg` / `hoink-logo-claro.svg`.
///
/// O SVG original posiciona textos em coordenadas fixas que dependem das métricas da fonte
/// instalada no sistema. Aqui as formas (orelhas, rosto, olhos e ponto) e proporções do vetor
/// são mantidas, mas o encadeamento "h → porquinho → ink → ." é calculado a partir da largura
/// real dos glifos da Sora embutida, para que o logo fique idêntico em qualquer plataforma.
class HoinkLogo extends StatelessWidget {
  const HoinkLogo({super.key, this.height = 32, this.onDark = false});

  final double height;

  /// Variante clara (`hoink-logo-claro.svg`) para fundos escuros.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final layout = _LogoLayout.compute();
    return Semantics(
      label: 'hoink.',
      image: true,
      child: SizedBox(
        height: height,
        width: height * layout.width / _LogoLayout.viewHeight,
        child: CustomPaint(painter: _LogoPainter(onDark ? HoinkColors.ivory : HoinkColors.pine, layout)),
      ),
    );
  }
}

/// Geometria em unidades do viewBox original (altura 240, fonte 174).
class _LogoLayout {
  _LogoLayout(this.h, this.ink, this.pigX, this.inkX, this.dotX, this.width);

  static const viewHeight = 240.0;
  static const baseline = 183.0;
  static const pigY = 122.0;
  static const pigR = 66.0;
  static const dotR = 15.0;
  static const _style = TextStyle(
    fontFamily: 'Sora',
    fontSize: 174,
    fontWeight: FontWeight.w800,
    letterSpacing: -6,
    height: 1,
  );

  final TextPainter h;
  final TextPainter ink;
  final double pigX;
  final double inkX;
  final double dotX;
  final double width;

  static _LogoLayout? _cache;

  static _LogoLayout compute() {
    if (_cache != null) return _cache!;
    TextPainter tp(String s) => TextPainter(
      text: TextSpan(text: s, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final h = tp('h');
    final ink = tp('ink');
    const left = 24.0;
    final pigX = left + h.width + 4 + pigR;
    final inkX = pigX + pigR + 8;
    final dotX = inkX + ink.width + 14 + dotR;
    return _cache = _LogoLayout(h, ink, pigX, inkX, dotX, dotX + dotR + 20);
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.ink, this.layout);
  final Color ink;
  final _LogoLayout layout;

  static const _pink = HoinkColors.pigPink;
  static const _eyes = HoinkColors.pine;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / _LogoLayout.viewHeight;
    canvas.save();
    canvas.scale(scale);

    void text(TextPainter source, double x) {
      final tp = TextPainter(
        text: TextSpan(
          text: source.plainText,
          style: _LogoLayout._style.copyWith(color: ink),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(x, _LogoLayout.baseline - baseline));
    }

    text(layout.h, 24);
    text(layout.ink, layout.inkX);

    // Rosto do porquinho no lugar do "o" — mesmas curvas do SVG (grupo transladado).
    canvas.save();
    canvas.translate(layout.pigX, _LogoLayout.pigY);
    final pink = Paint()..color = _pink;
    canvas.drawPath(
      Path()
        ..moveTo(-42, -53)
        ..quadraticBezierTo(-61, -102, -37, -104)
        ..quadraticBezierTo(-13, -101, -13, -65)
        ..close(),
      pink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(18, -65)
        ..quadraticBezierTo(31, -105, 53, -101)
        ..quadraticBezierTo(72, -94, 48, -50)
        ..close(),
      pink,
    );
    canvas.drawCircle(Offset.zero, _LogoLayout.pigR, Paint()..color = ink);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 94, height: 86), pink);
    final eye = Paint()..color = _eyes;
    canvas.drawOval(Rect.fromCenter(center: const Offset(-15, 3), width: 17, height: 24), eye);
    canvas.drawOval(Rect.fromCenter(center: const Offset(15, 3), width: 17, height: 24), eye);
    canvas.restore();

    canvas.drawCircle(Offset(layout.dotX, _LogoLayout.baseline - _LogoLayout.dotR - 3), _LogoLayout.dotR, pink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.ink != ink;
}
