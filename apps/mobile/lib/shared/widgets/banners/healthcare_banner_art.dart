import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/banner_art_tokens.dart';

/// The visual story rendered inside an [AnimatedPageBanner].
enum BannerScene {
  careTeam,
  aiCompanion,
  doctorNetwork,
  bloodDonation,
  medicalEducation,
  healthMonitoring,
  communitySupport,
  familyCare,
  appointments,
}

/// Hand-built, transparent vector artwork for the healthcare banners.
///
/// The app ships no third-party illustration library, so the characters are
/// drawn as scalable vectors instead of loading a remote animation. That keeps
/// the art fully offline, lightweight, and deliberately diverse: the palette
/// below covers deep, dark, medium and light natural brown skin tones, and the
/// cast mixes African women and men, nurses, patients, children, caregivers,
/// specialists and a friendly AI robot.
///
/// [motion] is an optional 0..1 progress value. When it is null (reduced motion,
/// animation failure or a static fallback) the exact same illustration renders
/// in a calm resting pose.
class HealthcareBannerArt extends StatelessWidget {
  const HealthcareBannerArt({
    super.key,
    required this.scene,
    required this.accentColor,
    this.motion,
  });

  final BannerScene scene;
  final Color accentColor;
  final Animation<double>? motion;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HealthcareBannerPainter(
          scene: scene,
          accentColor: accentColor,
          motion: motion,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SkinTones {
  const _SkinTones._();

  static const Color deep = BannerArtColors.c4A2A1D;
  static const Color dark = BannerArtColors.c6A3D27;
  static const Color medium = BannerArtColors.c8D5735;
  static const Color warm = BannerArtColors.cAC7048;
  static const Color light = BannerArtColors.cC98E62;
}

class _Ink {
  const _Ink._();

  static const Color navy = BannerArtColors.c0B1F3D;
  static const Color blue = BannerArtColors.c1E5AA8;
  static const Color teal = BannerArtColors.c247C83;
  static const Color white = BannerArtColors.cF8FBFF;
  static const Color coat = BannerArtColors.cF4F8FC;
  static const Color coatShade = BannerArtColors.cDCE6F1;
  static const Color hair = BannerArtColors.c201714;
  static const Color hairSoft = BannerArtColors.c35241D;
  static const Color denim = BannerArtColors.c273A58;
  static const Color metal = BannerArtColors.cB9C9DA;
  static const Color red = BannerArtColors.cE03E50;
}

class _HealthcareBannerPainter extends CustomPainter {
  _HealthcareBannerPainter({
    required this.scene,
    required this.accentColor,
    this.motion,
  }) : super(repaint: motion);

  final BannerScene scene;
  final Color accentColor;
  final Animation<double>? motion;

  static const Size _design = Size(260, 140);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _design.width,
      size.height / _design.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - _design.width * scale) / 2,
      (size.height - _design.height * scale) / 2,
    );
    canvas.scale(scale);

    final t = motion?.value ?? 0.32;
    _paintScene(canvas, t);

    canvas.restore();
  }

  void _paintScene(Canvas canvas, double t) {
    switch (scene) {
      case BannerScene.careTeam:
        _drawPlus(canvas, const Offset(28, 28), 5, _softAccent(0.5));
        _drawHeart(canvas, const Offset(160, 24), 8, _softAccent(0.55));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 45,
            y: 130,
            scale: 1.18,
            skin: _SkinTones.deep,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.wrap,
            fabric: BannerArtColors.c2F6FB2,
            stethoscope: true,
            phase: 0.1,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 96,
            y: 130,
            scale: 1.12,
            skin: _SkinTones.dark,
            outfit: _Ink.teal,
            hairColor: _Ink.hair,
            style: _HairStyle.short,
            outfitStyle: _Outfit.scrubs,
            stethoscope: true,
            phase: 1.8,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 137,
            y: 132,
            scale: 0.78,
            skin: _SkinTones.medium,
            outfit: BannerArtColors.cE9C65D,
            hairColor: _Ink.hair,
            style: _HairStyle.childAfro,
            outfitStyle: _Outfit.casual,
            child: true,
            phase: 3.2,
            accessory: _Accessory.heart,
          ),
        );
        _paintRobot(
          canvas,
          t,
          const _Robot(x: 190, y: 130, scale: 0.94, phase: 4.2),
        );
      case BannerScene.aiCompanion:
        _drawPulse(canvas, const Offset(24, 34), 64, _softAccent(0.45));
        _drawPlus(canvas, const Offset(121, 24), 5, _softAccent(0.5));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 72,
            y: 130,
            scale: 1.14,
            skin: _SkinTones.dark,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.bun,
            stethoscope: true,
            phase: 0.8,
            accessory: _Accessory.tablet,
          ),
        );
        _paintRobot(
          canvas,
          t,
          const _Robot(x: 180, y: 130, scale: 1.28, phase: 2.9),
        );
      case BannerScene.doctorNetwork:
        _drawPlus(canvas, const Offset(34, 25), 5, _softAccent(0.5));
        _drawPlus(canvas, const Offset(218, 34), 4, _softAccent(0.4));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 48,
            y: 130,
            scale: 1.08,
            skin: _SkinTones.deep,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.wrap,
            fabric: BannerArtColors.cC23B4B,
            stethoscope: true,
            phase: 0.2,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 104,
            y: 130,
            scale: 1.17,
            skin: _SkinTones.dark,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.short,
            glasses: true,
            stethoscope: true,
            phase: 2.0,
            accessory: _Accessory.clipboard,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 162,
            y: 130,
            scale: 1.12,
            skin: _SkinTones.warm,
            outfit: BannerArtColors.c2A7D88,
            hairColor: _Ink.hairSoft,
            style: _HairStyle.hijab,
            fabric: BannerArtColors.c3A7E9E,
            outfitStyle: _Outfit.scrubs,
            phase: 3.7,
          ),
        );
      case BannerScene.bloodDonation:
        _drawBloodDrop(canvas, const Offset(183, 26), 10, _softAccent(0.75));
        _drawHeart(canvas, const Offset(216, 25), 7, _softAccent(0.5));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 55,
            y: 130,
            scale: 1.1,
            skin: _SkinTones.medium,
            outfit: BannerArtColors.cF4F8FC,
            hairColor: _Ink.hair,
            style: _HairStyle.short,
            outfitStyle: _Outfit.casual,
            phase: 0.6,
            accessory: _Accessory.bandage,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 112,
            y: 130,
            scale: 1.16,
            skin: _SkinTones.deep,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.braids,
            stethoscope: true,
            phase: 2.4,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 151,
            y: 132,
            scale: 0.78,
            skin: _SkinTones.light,
            outfit: BannerArtColors.c4C8FD1,
            hairColor: _Ink.hairSoft,
            style: _HairStyle.childAfro,
            outfitStyle: _Outfit.casual,
            child: true,
            phase: 3.9,
            accessory: _Accessory.heart,
          ),
        );
      case BannerScene.medicalEducation:
        _drawBook(canvas, const Offset(191, 29), 16, _softAccent(0.7));
        _drawPlus(canvas, const Offset(230, 52), 4, _softAccent(0.45));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 62,
            y: 130,
            scale: 1.12,
            skin: _SkinTones.dark,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.bun,
            stethoscope: true,
            phase: 0.3,
            accessory: _Accessory.book,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 124,
            y: 130,
            scale: 1.02,
            skin: _SkinTones.warm,
            outfit: BannerArtColors.cE0705A,
            hairColor: _Ink.hairSoft,
            style: _HairStyle.braids,
            outfitStyle: _Outfit.casual,
            phase: 2.2,
          ),
        );
        _drawPlus(canvas, const Offset(177, 98), 6, _softAccent(0.55));
      case BannerScene.healthMonitoring:
        _drawPulse(canvas, const Offset(169, 28), 70, _softAccent(0.75));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 61,
            y: 130,
            scale: 1.1,
            skin: _SkinTones.deep,
            outfit: _Ink.teal,
            hairColor: _Ink.hair,
            style: _HairStyle.short,
            outfitStyle: _Outfit.scrubs,
            stethoscope: true,
            phase: 0.5,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 118,
            y: 130,
            scale: 1.05,
            skin: _SkinTones.medium,
            outfit: BannerArtColors.c7C63B8,
            hairColor: _Ink.hair,
            style: _HairStyle.braids,
            outfitStyle: _Outfit.casual,
            phase: 2.6,
            accessory: _Accessory.tablet,
          ),
        );
        _drawHeart(canvas, const Offset(182, 59), 8, _softAccent(0.65));
      case BannerScene.communitySupport:
        _drawHeart(canvas, const Offset(209, 28), 11, _softAccent(0.7));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 48,
            y: 130,
            scale: 1.02,
            skin: _SkinTones.dark,
            outfit: BannerArtColors.c3E8B8F,
            hairColor: _Ink.hair,
            style: _HairStyle.wrap,
            fabric: BannerArtColors.cD59B3A,
            outfitStyle: _Outfit.casual,
            phase: 0.4,
            accessory: _Accessory.heart,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 98,
            y: 130,
            scale: 1.12,
            skin: _SkinTones.deep,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.hijab,
            fabric: BannerArtColors.c2F6FB2,
            stethoscope: true,
            phase: 2.1,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 154,
            y: 130,
            scale: 1.0,
            skin: _SkinTones.light,
            outfit: BannerArtColors.cD45A68,
            hairColor: _Ink.hairSoft,
            style: _HairStyle.bun,
            outfitStyle: _Outfit.casual,
            phase: 3.8,
          ),
        );
        _drawPlus(canvas, const Offset(31, 57), 4, _softAccent(0.4));
      case BannerScene.familyCare:
        _drawHeart(canvas, const Offset(203, 25), 9, _softAccent(0.65));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 40,
            y: 130,
            scale: 1.04,
            skin: _SkinTones.dark,
            outfit: BannerArtColors.c345F92,
            hairColor: _Ink.hair,
            style: _HairStyle.short,
            outfitStyle: _Outfit.casual,
            phase: 0.7,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 86,
            y: 130,
            scale: 1.0,
            skin: _SkinTones.medium,
            outfit: BannerArtColors.c8B5BA6,
            hairColor: _Ink.hair,
            style: _HairStyle.braids,
            outfitStyle: _Outfit.dress,
            phase: 2.3,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 119,
            y: 132,
            scale: 0.7,
            skin: _SkinTones.warm,
            outfit: BannerArtColors.cE9C65D,
            hairColor: _Ink.hairSoft,
            style: _HairStyle.childAfro,
            outfitStyle: _Outfit.casual,
            child: true,
            phase: 3.4,
            accessory: _Accessory.heart,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 166,
            y: 130,
            scale: 0.94,
            skin: _SkinTones.deep,
            outfit: BannerArtColors.c4A8072,
            hairColor: BannerArtColors.cB7B7B7,
            style: _HairStyle.wrap,
            fabric: BannerArtColors.cB44A59,
            outfitStyle: _Outfit.dress,
            phase: 4.7,
          ),
        );
      case BannerScene.appointments:
        _drawCalendar(canvas, const Offset(187, 26), 18, _softAccent(0.7));
        _drawPulse(canvas, const Offset(31, 30), 52, _softAccent(0.4));
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 62,
            y: 130,
            scale: 1.12,
            skin: _SkinTones.deep,
            outfit: _Ink.coat,
            hairColor: _Ink.hair,
            style: _HairStyle.wrap,
            fabric: BannerArtColors.c2F6FB2,
            stethoscope: true,
            phase: 0.5,
            accessory: _Accessory.clipboard,
          ),
        );
        _paintPerson(
          canvas,
          t,
          const _Person(
            x: 124,
            y: 130,
            scale: 1.0,
            skin: _SkinTones.medium,
            outfit: BannerArtColors.cE0705A,
            hairColor: _Ink.hair,
            style: _HairStyle.short,
            outfitStyle: _Outfit.casual,
            phase: 2.5,
          ),
        );
        _drawPlus(canvas, const Offset(166, 100), 5, _softAccent(0.55));
    }
  }

  Color _softAccent(double opacity) => accentColor.withValues(alpha: opacity);

  void _paintPerson(Canvas canvas, double t, _Person p) {
    final bob = math.sin(t * math.pi * 6 + p.phase) * 0.9;
    canvas.save();
    canvas.translate(p.x, p.y + bob);
    canvas.scale(p.scale);

    final skin = Paint()..color = p.skin;
    final skinShade = Paint()..color = _darken(p.skin, 0.16);
    final outfit = Paint()..color = p.outfit;
    final outfitShade = Paint()..color = _darken(p.outfit, 0.18);
    final hair = Paint()..color = p.hairColor;
    final ink = Paint()
      ..color = _Ink.navy
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 1), width: 34, height: 6),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    if (p.outfitStyle != _Outfit.dress) {
      final legWidth = p.child ? 7.0 : 8.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-legWidth - 1, -20, legWidth, 20),
          BannerArtRadii.r4,
        ),
        Paint()..color = p.child ? BannerArtColors.c38527A : _Ink.denim,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, -20, legWidth, 20),
          BannerArtRadii.r4,
        ),
        Paint()..color = p.child ? BannerArtColors.c38527A : _Ink.denim,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(-5, 0),
          width: legWidth + 3,
          height: 5,
        ),
        Paint()..color = _Ink.navy,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(5, 0),
          width: legWidth + 3,
          height: 5,
        ),
        Paint()..color = _Ink.navy,
      );
    } else {
      final skirt = Path()
        ..moveTo(-12, -21)
        ..lineTo(12, -21)
        ..lineTo(16, -1)
        ..lineTo(-16, -1)
        ..close();
      canvas.drawPath(skirt, outfit);
      canvas.drawPath(
        skirt,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    final torsoHeight = p.child ? 25.0 : 29.0;
    final torsoTop = -46.0;
    final torso = RRect.fromRectAndRadius(
      Rect.fromLTWH(-15, torsoTop, 30, torsoHeight),
      BannerArtRadii.r9,
    );
    canvas.drawRRect(torso, outfit);

    if (p.outfitStyle == _Outfit.coat) {
      final lapel = Path()
        ..moveTo(-6, torsoTop)
        ..lineTo(-1, torsoTop + 9)
        ..lineTo(1, torsoTop)
        ..close();
      canvas.drawPath(lapel, Paint()..color = p.skin);
      canvas.drawPath(
        Path()
          ..moveTo(0, torsoTop + 10)
          ..lineTo(0, -18),
        Paint()
          ..color = _Ink.coatShade
          ..strokeWidth = 1.1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-10, -36, 7, 9),
          BannerArtRadii.r1_6,
        ),
        Paint()..color = _Ink.coatShade,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(5, -38, 5.5, 7),
          BannerArtRadii.r1_4,
        ),
        Paint()..color = accentColor,
      );
      _drawPlus(canvas, const Offset(7.7, -34.5), 1.7, _Ink.white);
    } else if (p.outfitStyle == _Outfit.scrubs) {
      final vNeck = Path()
        ..moveTo(-6, torsoTop)
        ..lineTo(0, torsoTop + 7)
        ..lineTo(6, torsoTop)
        ..close();
      canvas.drawPath(vNeck, Paint()..color = _darken(p.outfit, 0.24));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-10, -34, 7, 10),
          BannerArtRadii.r1_5,
        ),
        Paint()..color = outfitShade.color,
      );
      canvas.drawRect(
        Rect.fromLTWH(-2, -29, 4, 1.5),
        Paint()..color = _Ink.white.withValues(alpha: 0.7),
      );
    } else {
      final collar = Path()
        ..moveTo(-6, torsoTop)
        ..lineTo(0, torsoTop + 6)
        ..lineTo(6, torsoTop)
        ..close();
      canvas.drawPath(collar, Paint()..color = outfitShade.color);
    }

    final wave = math.sin(t * math.pi * 6 + p.phase) * 0.06;
    _drawArm(canvas, -13, torsoTop + 3, -0.16 - wave, outfit, skin, p);
    _drawArm(canvas, 13, torsoTop + 3, 0.16 + wave, outfit, skin, p);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-5, -53, 10, 9), BannerArtRadii.r3),
      skin,
    );

    final headRect = Rect.fromCenter(
      center: Offset(0, p.child ? -60 : -62),
      width: p.child ? 23 : 22,
      height: p.child ? 25 : 24,
    );
    _drawHairBack(canvas, p, headRect, hair);
    canvas.drawOval(headRect, skin);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-11.5, p.child ? -60 : -62),
        width: 3.2,
        height: 4.6,
      ),
      skinShade,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(11.5, p.child ? -60 : -62),
        width: 3.2,
        height: 4.6,
      ),
      skinShade,
    );
    _drawHairFront(canvas, p, headRect, hair, outfitShade);

    final eyeY = p.child ? -61.0 : -63.0;
    final eyePaint = Paint()..color = _Ink.hair;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-4.2, eyeY), width: 2.2, height: 2.3),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(4.2, eyeY), width: 2.2, height: 2.3),
      eyePaint,
    );
    canvas.drawLine(
      Offset(-6.6, eyeY - 4.4),
      Offset(-2.4, eyeY - 5.0),
      Paint()
        ..color = p.hairColor
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(2.4, eyeY - 5.0),
      Offset(6.6, eyeY - 4.4),
      Paint()
        ..color = p.hairColor
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(0, eyeY + 6.6), width: 8.5, height: 5.4),
      0.12,
      math.pi - 0.24,
      false,
      ink
        ..strokeWidth = 1.05
        ..color = _darken(p.skin, 0.42),
    );

    if (p.glasses) {
      final frame = Paint()
        ..color = _Ink.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.drawCircle(Offset(-4.4, eyeY), 4.2, frame);
      canvas.drawCircle(Offset(4.4, eyeY), 4.2, frame);
      canvas.drawLine(Offset(-0.4, eyeY), Offset(0.4, eyeY), frame);
    }

    if (p.stethoscope) {
      final tube = Path()
        ..moveTo(-6.5, torsoTop + 1)
        ..cubicTo(-10, -38, -8, -30, -1, -34)
        ..cubicTo(3, -36.5, 5, -43, 6.5, -47);
      canvas.drawPath(
        tube,
        Paint()
          ..color = _Ink.navy.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        const Offset(6.5, -34),
        2.3,
        Paint()..color = _Ink.metal,
      );
      canvas.drawCircle(
        const Offset(6.5, -34),
        1.15,
        Paint()..color = _Ink.navy,
      );
    }

    _drawAccessory(canvas, p, outfitShade, skin);

    canvas.restore();
  }

  void _drawArm(
    Canvas canvas,
    double x,
    double y,
    double angle,
    Paint outfit,
    Paint skin,
    _Person p,
  ) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-3.4, 0, 6.8, p.child ? 16 : 19),
        BannerArtRadii.r3_4,
      ),
      outfit,
    );
    canvas.drawCircle(Offset(0, p.child ? 18 : 21), 2.9, skin);
    canvas.restore();
  }

  void _drawHairBack(Canvas canvas, _Person p, Rect head, Paint hair) {
    switch (p.style) {
      case _HairStyle.bun:
        canvas.drawCircle(Offset(head.center.dx, head.top - 3), 5.6, hair);
      case _HairStyle.braids:
        for (final dx in [-12.0, 12.0]) {
          canvas.drawCircle(Offset(dx, head.top + 7), 4.4, hair);
          canvas.drawCircle(Offset(dx * 1.08, head.top + 14), 3.8, hair);
        }
      case _HairStyle.wrap:
        canvas.drawOval(
          Rect.fromCenter(
            center: head.center,
            width: head.width + 10,
            height: head.height + 8,
          ),
          Paint()..color = p.fabric,
        );
      case _HairStyle.hijab:
        final drape = Path()
          ..moveTo(-16, -46)
          ..cubicTo(-20, -58, -17, -76, 0, -77)
          ..cubicTo(17, -76, 20, -58, 16, -46)
          ..lineTo(10, -40)
          ..lineTo(-10, -40)
          ..close();
        canvas.drawPath(drape, Paint()..color = p.fabric);
      case _HairStyle.childAfro:
        for (var i = 0; i < 7; i++) {
          final angle = math.pi + (math.pi / 6) * i;
          canvas.drawCircle(
            Offset(
              math.cos(angle) * 11.5,
              head.center.dy + math.sin(angle) * 11.5,
            ),
            5.2,
            hair,
          );
        }
      case _HairStyle.short:
        break;
    }
  }

  void _drawHairFront(
    Canvas canvas,
    _Person p,
    Rect head,
    Paint hair,
    Paint outfitShade,
  ) {
    switch (p.style) {
      case _HairStyle.short:
        canvas.save();
        canvas.clipPath(Path()..addOval(head.inflate(0.6)));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, head.top + 5.2),
            width: head.width + 1,
            height: 15,
          ),
          hair,
        );
        canvas.restore();
      case _HairStyle.bun:
        canvas.save();
        canvas.clipPath(Path()..addOval(head.inflate(0.6)));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, head.top + 4.8),
            width: head.width + 1,
            height: 14,
          ),
          hair,
        );
        canvas.restore();
        canvas.drawCircle(Offset(head.center.dx, head.top - 3), 5.6, hair);
      case _HairStyle.braids:
        canvas.save();
        canvas.clipPath(Path()..addOval(head.inflate(0.6)));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, head.top + 4.8),
            width: head.width + 1,
            height: 14,
          ),
          hair,
        );
        canvas.restore();
        for (final dx in [-11.0, 11.0]) {
          canvas.drawCircle(Offset(dx, head.top + 10), 3.4, hair);
        }
      case _HairStyle.wrap:
        canvas.save();
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCenter(
              center: Offset(head.center.dx, head.center.dy - 2),
              width: head.width + 6,
              height: head.height + 3,
            ),
          ),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, head.top + 5.0),
            width: head.width + 7,
            height: 20,
          ),
          Paint()..color = _lighten(p.fabric, 0.14),
        );
        canvas.restore();
        canvas.drawCircle(
          Offset(-12, head.top + 6),
          3.2,
          Paint()..color = _lighten(p.fabric, 0.10),
        );
        canvas.drawCircle(
          Offset(-12, head.top + 6),
          1.3,
          Paint()..color = _darken(p.fabric, 0.18),
        );
      case _HairStyle.hijab:
        final band = Path()
          ..moveTo(-15, head.top + 7)
          ..cubicTo(-10, head.top - 4, 10, head.top - 4, 15, head.top + 7)
          ..lineTo(12, head.top + 11)
          ..cubicTo(7, head.top + 2, -7, head.top + 2, -12, head.top + 11)
          ..close();
        canvas.drawPath(band, Paint()..color = _lighten(p.fabric, 0.12));
      case _HairStyle.childAfro:
        canvas.save();
        canvas.clipPath(Path()..addOval(head.inflate(0.6)));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, head.top + 5),
            width: head.width,
            height: 14,
          ),
          hair,
        );
        canvas.restore();
    }
  }

  void _drawAccessory(Canvas canvas, _Person p, Paint shade, Paint skin) {
    switch (p.accessory) {
      case _Accessory.tablet:
        canvas.save();
        canvas.translate(9, -37);
        canvas.rotate(-0.08);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 15, 20),
            BannerArtRadii.r2_2,
          ),
          Paint()..color = _Ink.navy,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1.6, 1.8, 11.8, 15),
            BannerArtRadii.r1_2,
          ),
          Paint()..color = BannerArtColors.cD7ECFF,
        );
        _drawPlus(canvas, const Offset(7.6, 9.3), 2.8, accentColor);
        canvas.restore();
      case _Accessory.book:
        canvas.save();
        canvas.translate(-10, -35);
        canvas.rotate(0.08);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 12, 15),
            BannerArtRadii.r1_5,
          ),
          Paint()..color = _Ink.navy,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1.2, 1.2, 9.6, 12.6),
            BannerArtRadii.r1,
          ),
          Paint()..color = BannerArtColors.cEDF6FF,
        );
        canvas.drawLine(
          const Offset(3, 4.6),
          const Offset(9, 4.6),
          Paint()
            ..color = _Ink.blue
            ..strokeWidth = 1,
        );
        canvas.drawLine(
          const Offset(3, 7.2),
          const Offset(8.2, 7.2),
          Paint()
            ..color = _Ink.blue.withValues(alpha: 0.7)
            ..strokeWidth = 1,
        );
        canvas.restore();
      case _Accessory.clipboard:
        canvas.save();
        canvas.translate(8, -38);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 13, 17),
            BannerArtRadii.r1_8,
          ),
          Paint()..color = BannerArtColors.cE8EEF5,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.4, -1.2, 6.2, 3),
            BannerArtRadii.r1,
          ),
          Paint()..color = _Ink.navy,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(2.4, 5 + i * 3.4),
            Offset(10.4, 5 + i * 3.4),
            Paint()
              ..color = _Ink.navy.withValues(alpha: 0.36)
              ..strokeWidth = 0.8,
          );
        }
        canvas.restore();
      case _Accessory.heart:
        canvas.save();
        canvas.translate(3, -35);
        _drawHeart(canvas, Offset.zero, 6.5, accentColor);
        canvas.restore();
      case _Accessory.bandage:
        canvas.save();
        canvas.translate(7, -28);
        canvas.rotate(-0.25);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 14, 5),
            BannerArtRadii.r2_4,
          ),
          Paint()..color = BannerArtColors.cF2D6C8,
        );
        canvas.drawCircle(
          const Offset(4.2, 2.5),
          0.7,
          Paint()..color = _Ink.red,
        );
        canvas.drawCircle(const Offset(7, 2.5), 0.7, Paint()..color = _Ink.red);
        canvas.drawCircle(
          const Offset(9.8, 2.5),
          0.7,
          Paint()..color = _Ink.red,
        );
        canvas.restore();
      case _Accessory.none:
        break;
    }
  }

  void _paintRobot(Canvas canvas, double t, _Robot r) {
    final bob = math.sin(t * math.pi * 6 + r.phase) * 1.1;
    canvas.save();
    canvas.translate(r.x, r.y + bob);
    canvas.scale(r.scale);

    final shell = Paint()..color = BannerArtColors.cECF5FF;
    final shellShade = Paint()..color = BannerArtColors.cC9DDF1;
    final blue = Paint()..color = accentColor;
    final navy = Paint()..color = _Ink.navy;

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 1), width: 36, height: 6),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-13, -43, 26, 35),
        BannerArtRadii.r8,
      ),
      shell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -37, 18, 14),
        BannerArtRadii.r4,
      ),
      Paint()..color = _Ink.navy,
    );
    _drawHeart(canvas, const Offset(0, -30), 5.2, accentColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -21, 20, 4),
        BannerArtRadii.r2,
      ),
      shellShade,
    );
    canvas.drawCircle(const Offset(-7, -8), 4.6, shellShade);
    canvas.drawCircle(const Offset(7, -8), 4.6, shellShade);

    final armWave = math.sin(t * math.pi * 6 + r.phase) * 0.24;
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(13.5 * side, -37);
      canvas.rotate(side * (0.12 + (side > 0 ? armWave : -armWave)));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3.2, 0, 6.4, 17),
          BannerArtRadii.r3_2,
        ),
        shell,
      );
      canvas.drawCircle(const Offset(0, 18), 3.3, blue);
      canvas.restore();
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, -50, 8, 8),
        BannerArtRadii.r2,
      ),
      shellShade,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-15, -73, 30, 25),
        BannerArtRadii.r8,
      ),
      shell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-11, -69.5, 22, 16),
        BannerArtRadii.r5,
      ),
      navy,
    );
    final eyePaint = Paint()..color = BannerArtColors.c9BE7FF;
    canvas.drawCircle(const Offset(-4.4, -63), 2.1, eyePaint);
    canvas.drawCircle(const Offset(4.4, -63), 2.1, eyePaint);
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(0, -57.2), width: 9, height: 5),
      0.2,
      math.pi - 0.4,
      false,
      Paint()
        ..color = BannerArtColors.c9BE7FF
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(-16.4, -61), 2.6, blue);
    canvas.drawCircle(const Offset(16.4, -61), 2.6, blue);
    final antennaSway = math.sin(t * math.pi * 6 + r.phase) * 1.3;
    canvas.drawLine(
      const Offset(0, -73),
      Offset(antennaSway, -82),
      Paint()
        ..color = _Ink.navy
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(antennaSway, -83.4),
      2.7,
      Paint()..color = accentColor,
    );
    _drawPlus(canvas, const Offset(11.5, -47), 2.4, _Ink.white);

    canvas.restore();
  }

  void _drawPlus(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()..color = color;
    final thickness = size * 0.38;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size * 2, height: thickness),
        Radius.circular(thickness / 2),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: thickness, height: size * 2),
        Radius.circular(thickness / 2),
      ),
      paint,
    );
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy + size * 0.82)
      ..cubicTo(
        center.dx - size * 1.24,
        center.dy + size * 0.06,
        center.dx - size * 0.82,
        center.dy - size * 0.84,
        center.dx,
        center.dy - size * 0.36,
      )
      ..cubicTo(
        center.dx + size * 0.82,
        center.dy - size * 0.84,
        center.dx + size * 1.24,
        center.dy + size * 0.06,
        center.dx,
        center.dy + size * 0.82,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawBloodDrop(Canvas canvas, Offset center, double size, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..cubicTo(
        center.dx - size * 0.9,
        center.dy - size * 0.15,
        center.dx - size * 0.9,
        center.dy + size * 0.75,
        center.dx,
        center.dy + size * 0.75,
      )
      ..cubicTo(
        center.dx + size * 0.9,
        center.dy + size * 0.75,
        center.dx + size * 0.9,
        center.dy - size * 0.15,
        center.dx,
        center.dy - size,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    _drawPlus(
      canvas,
      Offset(center.dx, center.dy + size * 0.05),
      size * 0.34,
      _Ink.white.withValues(alpha: 0.85),
    );
  }

  void _drawPulse(Canvas canvas, Offset origin, double width, Color color) {
    final path = Path()
      ..moveTo(origin.dx, origin.dy)
      ..lineTo(origin.dx + width * 0.25, origin.dy)
      ..lineTo(origin.dx + width * 0.34, origin.dy - 7)
      ..lineTo(origin.dx + width * 0.45, origin.dy + 7)
      ..lineTo(origin.dx + width * 0.56, origin.dy - 4)
      ..lineTo(origin.dx + width * 0.65, origin.dy)
      ..lineTo(origin.dx + width, origin.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawBook(Canvas canvas, Offset center, double size, Color color) {
    final left = Path()
      ..moveTo(center.dx, center.dy - size * 0.55)
      ..cubicTo(
        center.dx - size * 0.45,
        center.dy - size * 0.8,
        center.dx - size * 0.95,
        center.dy - size * 0.75,
        center.dx - size,
        center.dy - size * 0.55,
      )
      ..lineTo(center.dx - size * 0.9, center.dy + size * 0.65)
      ..cubicTo(
        center.dx - size * 0.45,
        center.dy + size * 0.48,
        center.dx - size * 0.18,
        center.dy + size * 0.55,
        center.dx,
        center.dy + size * 0.75,
      )
      ..close();
    final right = Path()
      ..moveTo(center.dx, center.dy - size * 0.55)
      ..cubicTo(
        center.dx + size * 0.45,
        center.dy - size * 0.8,
        center.dx + size * 0.95,
        center.dy - size * 0.75,
        center.dx + size,
        center.dy - size * 0.55,
      )
      ..lineTo(center.dx + size * 0.9, center.dy + size * 0.65)
      ..cubicTo(
        center.dx + size * 0.45,
        center.dy + size * 0.48,
        center.dx + size * 0.18,
        center.dy + size * 0.55,
        center.dx,
        center.dy + size * 0.75,
      )
      ..close();
    canvas.drawPath(left, Paint()..color = color);
    canvas.drawPath(right, Paint()..color = _lighten(color, 0.14));
    canvas.drawLine(
      Offset(center.dx, center.dy - size * 0.55),
      Offset(center.dx, center.dy + size * 0.75),
      Paint()
        ..color = _Ink.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.2,
    );
  }

  void _drawCalendar(Canvas canvas, Offset center, double size, Color color) {
    final rect = Rect.fromCenter(
      center: center,
      width: size * 2,
      height: size * 1.6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, BannerArtRadii.r3),
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, BannerArtRadii.r3),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 5),
      Paint()..color = color,
    );
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawCircle(
          Offset(rect.left + 6 + i * 8, rect.top + 11 + j * 7),
          1.3,
          Paint()..color = _Ink.white.withValues(alpha: 0.8),
        );
      }
    }
    canvas.drawCircle(
      Offset(rect.left + 14, rect.top + 18),
      2.8,
      Paint()..color = _Ink.white,
    );
    canvas.drawLine(
      Offset(rect.left + 12.6, rect.top + 18),
      Offset(rect.left + 13.6, rect.top + 19.2),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(rect.left + 13.6, rect.top + 19.2),
      Offset(rect.left + 15.5, rect.top + 16.7),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthcareBannerPainter old) =>
      old.scene != scene ||
      old.accentColor != accentColor ||
      old.motion != motion;
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

Color _lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

enum _HairStyle { short, bun, braids, wrap, hijab, childAfro }

enum _Outfit { coat, scrubs, casual, dress }

enum _Accessory { none, tablet, book, clipboard, heart, bandage }

class _Person {
  const _Person({
    required this.x,
    required this.y,
    required this.scale,
    required this.skin,
    required this.outfit,
    required this.hairColor,
    required this.style,
    this.outfitStyle = _Outfit.coat,
    this.fabric = _Ink.blue,
    this.glasses = false,
    this.stethoscope = false,
    this.child = false,
    this.phase = 0,
    this.accessory = _Accessory.none,
  });

  final double x;
  final double y;
  final double scale;
  final Color skin;
  final Color outfit;
  final Color hairColor;
  final _HairStyle style;
  final _Outfit outfitStyle;
  final Color fabric;
  final bool glasses;
  final bool stethoscope;
  final bool child;
  final double phase;
  final _Accessory accessory;
}

class _Robot {
  const _Robot({
    required this.x,
    required this.y,
    required this.scale,
    this.phase = 0,
  });

  final double x;
  final double y;
  final double scale;
  final double phase;
}
