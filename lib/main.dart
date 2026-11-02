import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'core/updates.dart';
import 'ui/app_scope.dart';
import 'ui/home.dart';
import 'ui/onboarding.dart';
import 'ui/splash.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = AppState();
  runApp(PawressApp(state: state));
  // Notifications are optional; a failure here must not hold the app on
  // the splash screen.
  try {
    await Notifier.init();
  } catch (e) {
    debugPrint('Notifications unavailable: $e');
  }
  await state.init();
}

class PawressApp extends StatefulWidget {
  const PawressApp({super.key, required this.state});

  final AppState state;

  @override
  State<PawressApp> createState() => _PawressAppState();
}

class _PawressAppState extends State<PawressApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) => AppScope(
    state: widget.state,
    child: ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        setPalette(state.settings.theme);
        final Widget screen = !_splashDone || !state.initialized
            ? SplashScreen(
                ready: state.initialized,
                onFinished: () => setState(() => _splashDone = true),
              )
            : !state.onboarded
            ? const OnboardingScreen(key: ValueKey('onboarding'))
            : const HomeScreen(key: ValueKey('home'));
        return MaterialApp(
          title: 'Pawress',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          // As the splash logo rises, the first screen is revealed from the
          // bottom edge, following it up.
          home: AnimatedSwitcher(
            duration: SplashScreen.exitDuration,
            switchInCurve: SplashScreen.exitCurve,
            switchOutCurve: SplashScreen.exitCurve,
            transitionBuilder: revealFromBottom,
            child: screen,
          ),
        );
      },
    ),
  );
}
