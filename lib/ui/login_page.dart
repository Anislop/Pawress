import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/api.dart';
import '../core/config.dart';
import 'app_scope.dart';

/// Signs in on Pawchive's own login page and keeps its `session` cookie.
/// The API has no login endpoint, so this is the only way in; the password
/// never passes through the app, only the username for display.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _cookies = WebViewCookieManager();
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.transparent)
    ..addJavaScriptChannel(
      'PawressLogin',
      onMessageReceived: (message) => _username = message.message,
    )
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress / 100);
        },
        onPageFinished: _check,
        onUrlChange: (change) => _check(change.url),
      ),
    )
    ..loadRequest(Uri.parse(loginUrl));

  String? _username;
  double _progress = 0;
  bool _busy = false;

  // Reports the username field when the login form is submitted.
  static const _captureUsername = '''
(function () {
  var form = document.querySelector('form');
  if (!form || form.dataset.pawress) return;
  form.dataset.pawress = '1';
  form.addEventListener('submit', function () {
    var field = form.querySelector('input[name="username"]');
    if (field) PawressLogin.postMessage(field.value);
  });
})();
''';

  Future<void> _check(String? url) async {
    final uri = url == null ? null : Uri.tryParse(url);
    if (_busy || uri == null || uri.host != siteHost) return;
    if (uri.path.startsWith('/account/login') ||
        uri.path.startsWith('/account/register')) {
      await _web.runJavaScript(_captureUsername);
      return;
    }
    final cookies = await _cookies.getCookies(domain: Uri.parse(siteUrl));
    final session = cookies
        .where((c) => c.name.trim() == sessionCookie)
        .firstOrNull
        ?.value;
    if (session == null || session.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Confirm the cookie works before keeping it.
    final probe = PawchiveApi(session: session);
    try {
      await probe.favoriteCreators();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.unauthorized
                ? 'Signed in on the website, but Pawress could not use the session. Try again.'
                : e.message,
          ),
        ),
      );
      return;
    }
    await state.signIn(session, _username);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Sign in to Pawchive',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      bottom: _progress < 1 || _busy
          ? PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: LinearProgressIndicator(
                value: _busy ? null : _progress,
                minHeight: 2,
              ),
            )
          : null,
    ),
    body: WebViewWidget(controller: _web),
  );
}
