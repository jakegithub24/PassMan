import 'dart:ui';
import 'package:flutter/material.dart';

/// PassMan Theme and Glassmorphic Styling Design System
/// Derived from UI-UX/UI/desktop_login_sign_up.html & desktop.html
class AppColors {
  // Brand Gradients & Accents
  static const Color navy = Color(0xFF0C447C);
  static const Color navyDark = Color(0xFF08325D);
  static const Color navySoft = Color(0xFFE8EEF5);
  static const Color tint1 = Color(0xFFDBE9F6);
  static const Color tint2 = Color(0xFFE4EEFA);
  static const Color frameBg = Color(0xFFEEF3F1);
  static const Color contentBg = Color(0xFFF4F6F5);

  // Typography & Inks
  static const Color ink = Color(0xFF14161A);
  static const Color inkSoft = Color(0xFF5B6169); // #5b6169 from html design
  static const Color inkLight = Color(0xFF98A2B3);

  // Glassmorphic Borders & Backgrounds
  static const Color glassWhite = Color(0x8CFFFFFF); // rgba(255, 255, 255, 0.55)
  static const Color glassWhiteStrong = Color(0xB8FFFFFF); // rgba(255, 255, 255, 0.72)
  static const Color glassBorder = Color(0x99FFFFFF); // rgba(255, 255, 255, 0.60)
  static const Color glassBorderStrong = Color(0xA6FFFFFF); // rgba(255, 255, 255, 0.65)
  static const Color inputBg = Color(0xA6FFFFFF); // rgba(255, 255, 255, 0.65)
  static const Color inputBorder = Color(0xBFFFFFFF); // rgba(255, 255, 255, 0.75)
  static const Color hairline = Color(0x1414161A); // rgba(20, 22, 26, 0.08)
  static const Color dividerHairline = Color(0x1414161A);

  // Visual Hero Glass Card Colors
  static const Color cardHeroBg = Color(0x29FFFFFF); // rgba(255, 255, 255, 0.16)
  static const Color cardHeroBorder = Color(0x4DFFFFFF); // rgba(255, 255, 255, 0.30)
  static const Color cardHeroIconBg = Color(0x3DFFFFFF); // rgba(255, 255, 255, 0.24)

  // Status & Utility Colors
  static const Color red = Color(0xFFE0483F);
  static const Color pillGreen = Color(0xFF12A37F);
  static const Color pillGray = Color(0xFFC9CDD1);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment(-0.7, -0.7),
    end: Alignment(0.7, 0.7),
    colors: [navy, navyDark],
  );

  static const LinearGradient visualHeroGradient = LinearGradient(
    begin: Alignment(-0.6, -0.8),
    end: Alignment(0.6, 0.8),
    colors: [navy, navyDark],
  );
}

/// Frosted Glass Container with adjustable blur, background tint, and border
class AppGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double blurSigma;
  final List<BoxShadow>? boxShadow;

  const AppGlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(32),
    this.width,
    this.height,
    this.backgroundColor = AppColors.glassWhite,
    this.borderColor = AppColors.glassBorderStrong,
    this.borderWidth = 1.0,
    this.blurSigma = 24.0,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: boxShadow ??
                const [
                  BoxShadow(
                    color: Color(0x1A14161A),
                    blurRadius: 48,
                    offset: Offset(0, 24),
                  ),
                ],
          ),
          child: child,
        ),
      ),
    );
  }
}
