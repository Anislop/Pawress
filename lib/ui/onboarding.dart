import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/updates.dart';
import 'app_scope.dart';
import 'login_page.dart';
import 'theme.dart';

/// The introduction: four slides whose artwork and text slide in at
/// different speeds as you swipe, ending with optional sign-in.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _notificationsAsked = false;

  static const _count = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _count - 1) {
      _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() => AppScope.read(context).completeOnboarding();

  Future<void> _askNotifications() async {
    final granted = await Notifier.requestPermission();
    if (!mounted) return;
    setState(() => _notificationsAsked = true);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can turn notifications on later in Settings.'),
        ),
      );
    }
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (signedIn == true) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final slides = <Widget>[
      const _Slide(
        art: _WelcomeArt(),
        title: 'Welcome to Pawress',
        body: 'A cozy way to browse Pawchive, the archive of Patreon, Pixiv Fanbox and Discord posts.',
      ),
      const _Slide(
        art: _FeedArt(),
        title: 'For You and Following',
        body: 'Fresh posts picked around the artists you like, and a timeline of only the ones you follow.',
      ),
      _Slide(
        art: const _ArtistsArt(),
        title: 'Never miss a post',
        body: 'Follow artists to get notified when something new is archived.',
        action: _notificationsAsked
            ? null
            : OutlinedButton.icon(
                onPressed: _askNotifications,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Allow notifications'),
              ),
      ),
      _Slide(
        art: const _AccountArt(),
        title: 'Bring your favorites',
        body: 'Sign in to sync follows with your Pawchive favorite artists, or keep them on this device.',
        action: OutlinedButton.icon(
          onPressed: _signIn,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Sign in to Pawchive'),
        ),
        footnote: 'Pawchive hosts adult content. By continuing you confirm you are 18 or older.',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Image.asset(logoAsset, height: 22),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _index < _count - 1 ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _index < _count - 1
                          ? () => _pages.animateToPage(
                              _count - 1,
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeInOutCubic,
                            )
                          : null,
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: slides.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => AnimatedBuilder(
                  animation: _pages,
                  builder: (context, child) {
                    final page =
                        _pages.hasClients && _pages.position.haveDimensions
                        ? _pages.page ?? _index.toDouble()
                        : _index.toDouble();
                    return _SlideMotion(
                      offset: page - index,
                      child: slides[index],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _index ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? pawPink : ink(.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 16,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _index == _count - 1 ? 'Get started' : 'Next',
                        key: ValueKey(_index == _count - 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exposes how far ([offset], -1 to 1) a slide is from the center to its
/// art and text, which move at different speeds.
class _SlideMotion extends InheritedWidget {
  const _SlideMotion({required this.offset, required super.child});

  final double offset;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SlideMotion>()?.offset ?? 0;

  @override
  bool updateShouldNotify(_SlideMotion oldWidget) => oldWidget.offset != offset;
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.art,
    required this.title,
    required this.body,
    this.action,
    this.footnote,
  });

  final Widget art;
  final String title;
  final String body;
  final Widget? action;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final offset = _SlideMotion.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final fade = (1 - offset.abs()).clamp(0.0, 1.0);
    // The art lags behind the page and the text leads it, for parallax.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(offset * width * .45, 0),
                child: Transform.scale(
                  scale: 1 - offset.abs() * .15,
                  child: Center(child: art),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(-offset * width * .25, 0),
            child: Opacity(
              opacity: fade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: ink(.65),
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 18), action!],
                  if (footnote != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      footnote!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: ink(.42),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    final offset = _SlideMotion.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: -offset * math.pi / 6,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(48),
              boxShadow: [
                BoxShadow(
                  color: pawPink.withValues(alpha: .35),
                  blurRadius: 60,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const BrandMark(size: 168),
          ),
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Image.asset(logoAsset),
        ),
      ],
    );
  }
}

/// Two mock posts under a For You / Following switch.
class _FeedArt extends StatelessWidget {
  const _FeedArt();

  @override
  Widget build(BuildContext context) {
    final offset = _SlideMotion.of(context);
    Widget card(Color tint, double shift) => Transform.translate(
      offset: Offset(offset * shift, 0),
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 16, backgroundColor: tint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(width: 90, color: ink(.7)),
                  const SizedBox(height: 6),
                  _Bar(width: 150, color: ink(.25)),
                  const SizedBox(height: 10),
                  Container(
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(colors: [tint, pawPlum]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: pawPink,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'For You',
                  style: TextStyle(
                    color: pawOutline,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Following',
                  style: TextStyle(color: ink(.6), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        card(pawPink, 60),
        card(pawMauve, 120),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 8,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// Artist bubbles orbiting a notification bell.
class _ArtistsArt extends StatelessWidget {
  const _ArtistsArt();

  @override
  Widget build(BuildContext context) {
    final offset = _SlideMotion.of(context);
    const colors = [
      pawPink,
      pawMauve,
      pawPinkLight,
      Color(0xFFF96854),
      Color(0xFF0096FA),
      Color(0xFF5865F2),
    ];
    return SizedBox.square(
      dimension: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < colors.length; i++)
            Transform.translate(
              offset: Offset.fromDirection(
                i * math.pi / 3 + offset * math.pi,
                100,
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: colors[i],
                child: Icon(
                  Icons.brush_rounded,
                  color: pawOutline.withValues(alpha: .7),
                ),
              ),
            ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: panel,
              shape: BoxShape.circle,
              border: Border.all(color: pawPink, width: 3),
            ),
            child: const Badge(
              label: Text('3'),
              backgroundColor: pawPink,
              textColor: pawOutline,
              offset: Offset(-18, 18),
              child: Center(
                child: Icon(
                  Icons.notifications_rounded,
                  size: 46,
                  color: pawPinkLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountArt extends StatelessWidget {
  const _AccountArt();

  @override
  Widget build(BuildContext context) {
    final offset = _SlideMotion.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: Offset(offset * 80, 0),
          child: const BrandMark(size: 92),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Transform.rotate(
            angle: offset * math.pi,
            child: const Icon(Icons.sync_alt_rounded, size: 40, color: pawPink),
          ),
        ),
        Transform.translate(
          offset: Offset(-offset * 80, 0),
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              size: 46,
              color: pawPinkLight,
            ),
          ),
        ),
      ],
    );
  }
}
