import 'package:flutter/material.dart';

import '../theme.dart';

/// Reusable Motion-style chrome (v1.18.0 reskin) — the shared
/// building blocks of the user-approved Motion Graphics skin:
/// glassy cards, glowing gradient buttons, gradient/glass
/// chips and dock bars. Pure styling: every widget here renders
/// exactly the child/callback it is given and adds no behaviour
/// of its own, so swapping a surface to one of these never
/// changes what a screen does.
///
/// Performance rule (user-approved skin, low-end phones): the
/// glass look is a translucent gradient + hairline border —
/// NO BackdropFilter / backdrop blur anywhere in this file.

/// The mockups' full-screen background: the vertical navy
/// gradient wrapped around [child].
class MotionBackground extends StatelessWidget {
  const MotionBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: TjProTheme.motionBackgroundGradient,
      ),
      child: child,
    );
  }
}

/// A glassy card: [TjProTheme.motionGlass] decoration around
/// padded content.
class MotionGlassCard extends StatelessWidget {
  const MotionGlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(16),
    this.glow = false,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool glow;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: TjProTheme.motionGlass(
        radius: radius,
        glow: glow,
        borderColor: borderColor,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A glowing gradient button (the mockups' Export / Create
/// buttons). Renders [child] centred on the gradient pill;
/// taps go through a real InkWell so ripples, semantics and
/// disabled state behave like a normal button.
class MotionGradientButton extends StatelessWidget {
  const MotionGradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.radius = 16,
    this.gradient = TjProTheme.motionGradient,
    this.glowColor = TjProTheme.motionCyan,
    this.padding =
        const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double radius;
  final LinearGradient gradient;
  final Color glowColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        decoration: TjProTheme.motionGlowButton(
          radius: radius,
          gradient: gradient,
          glowColor: glowColor,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            child: Padding(
              padding: padding,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Motion chip: gradient fill + glow when [selected], glass
/// fill when not — the mockups' category/preset chips.
class MotionChip extends StatelessWidget {
  const MotionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: TjProTheme.chipPadding,
        decoration: selected
            ? TjProTheme.motionGlowButton(
                radius: TjProTheme.chipRadius,
                glowColor: TjProTheme.motionBlue,
              )
            : BoxDecoration(
                color: TjProTheme.motionChipFill,
                borderRadius:
                    BorderRadius.circular(TjProTheme.chipRadius),
                border: Border.all(color: TjProTheme.motionBorder),
              ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : TjProTheme.motionTextSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A dock/tool bar surface: the glass gradient with a hairline
/// top border, wrapping the bar's existing row of tools. The
/// tools themselves are untouched — this is only the plate
/// they sit on.
class MotionDockBar extends StatelessWidget {
  const MotionDockBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0x6B284696), Color(0xB8090E22)],
        ),
        border: Border(
          top: BorderSide(color: TjProTheme.motionBorder),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}
