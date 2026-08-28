import 'package:flutter/material.dart';

/// Sanjeevani motion tokens and the three widgets that cover every animated
/// surface in the patient app. Sits alongside theme.dart; add
/// `SanjeevaniMotion.pageTransitions` to both ThemeData objects in theme.dart.
class SanjeevaniMotion {
  const SanjeevaniMotion._();

  static const Duration press = Duration(milliseconds: 120);
  static const Duration ui = Duration(milliseconds: 200);
  static const Duration step = Duration(milliseconds: 250);
  static const Duration sheet = Duration(milliseconds: 300);

  /// Strong ease-out for entrances and exits. Never ease-in on UI.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Strong ease-in-out for movement across the screen (profile-setup steps).
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like drawer curve, for sheets and pushed routes.
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static const PageTransitionsTheme pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: _SlidePageTransitionsBuilder(),
      TargetPlatform.iOS: _SlidePageTransitionsBuilder(),
    },
  );
}

class _SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (SanjeevaniMotion.reduced(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: SanjeevaniMotion.drawer,
      reverseCurve: SanjeevaniMotion.drawer.flipped,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}

/// Press feedback. Wrap keypad keys, send buttons, list rows — anything with a
/// tap target. 120ms is deliberately at the floor: these are pressed dozens of
/// times per session and must not feel gated.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final target =
        _down && !SanjeevaniMotion.reduced(context) ? widget.scale : 1.0;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: target,
        duration: SanjeevaniMotion.press,
        curve: SanjeevaniMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Entrance for content that arrives: a new message, a report card, the issued
/// token, each row of a list. `delay` carries the stagger — 40ms apart, never
/// more than ~5 items deep.
class RiseIn extends StatelessWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 8,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final reduce = SanjeevaniMotion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SanjeevaniMotion.ui,
      curve: Interval(
        delay.inMilliseconds /
            (delay.inMilliseconds + SanjeevaniMotion.ui.inMilliseconds),
        1,
        curve: SanjeevaniMotion.easeOut,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: reduce
            ? child
            : Transform.translate(
                offset: Offset(0, (1 - t) * offset),
                child: child,
              ),
      ),
      child: child,
    );
  }
}

/// Only exists because TweenAnimationBuilder is not const-friendly in a list
/// builder; keeps the stagger arithmetic in one place.
Duration staggerAt(int index, {int stepMs = 40, int maxSteps = 5}) =>
    Duration(milliseconds: stepMs * (index < maxSteps ? index : maxSteps));
