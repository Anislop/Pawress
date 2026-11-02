import 'package:flutter/material.dart';

import 'theme.dart';

/// The paw and wordmark fade in, wait until the app is [ready], then rise
/// off the top while the first screen is revealed from the bottom edge (see
/// [revealFromBottom]). Same choreography as BooruPlus's launch.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.ready,
    required this.onFinished,
  });

  final bool ready;

  /// Called as the logo starts rising, so the next screen can be revealed
  /// underneath over [exitDuration].
  final VoidCallback onFinished;

  static const exitDuration = Duration(milliseconds: 660);
  static const exitCurve = Curves.easeInOutCubic;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Where the controller holds between fading in and rising.
  static const _hold = .45;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashScreen.exitDuration * (1 / (1 - _hold)),
  );
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller.animateTo(_hold).whenCompleteOrCancel(_exit);
  }

  @override
  void didUpdateWidget(SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) {
      // Not during build: finishing rebuilds the app.
      WidgetsBinding.instance.addPostFrameCallback((_) => _exit());
    }
  }

  void _exit() {
    if (!mounted || _exiting || !widget.ready || _controller.value < _hold) {
      return;
    }
    _exiting = true;
    widget.onFinished();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: canvas,
    body: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final enter = Curves.easeOutBack.transform((t / _hold).clamp(0.0, 1.0));
        final exit = SplashScreen.exitCurve.transform(
          ((t - _hold) / (1 - _hold)).clamp(0.0, 1.0),
        );
        final height = MediaQuery.sizeOf(context).height;
        return Opacity(
          opacity: (t / _hold).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - enter) - height * .65 * exit),
            child: Transform.scale(scale: .9 + .1 * enter, child: child),
          ),
        );
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 112),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Image.asset(logoAsset, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Reveals an incoming screen from the bottom edge up, rising slightly.
/// Once revealed nothing is clipped.
Widget revealFromBottom(Widget child, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final revealing = animation.status == AnimationStatus.forward;
        final value = revealing ? animation.value : 1.0;
        return ClipRect(
          clipper: _BottomReveal(value),
          clipBehavior: revealing ? Clip.hardEdge : Clip.none,
          child: Transform.translate(
            offset: Offset(0, 32 * (1 - value)),
            child: child,
          ),
        );
      },
    );

class _BottomReveal extends CustomClipper<Rect> {
  const _BottomReveal(this.fraction);

  /// The share of the height shown, measured from the bottom.
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    size.height * (1 - fraction.clamp(0.0, 1.0)),
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_BottomReveal oldClipper) =>
      oldClipper.fraction != fraction;
}
