import 'dart:async';
import 'package:pure_live/exports/package_export.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/platforms/douyin/douyin_search.dart';
import 'package:pure_live/platforms/douyin/douyin_login_cookie.dart';
import 'package:pure_live/services/cookie_manager/cookie_controller.dart';

/// Signs in to Douyin by scanning its own web login page.
///
/// Douyin's QR endpoint answers plain HTTP clients with the login page and its
/// security scripts, so the page runs in a real WebView, and this screen only
/// watches for the session cookie the scan leaves behind. The desktop user
/// agent is the one search requests use, because the mobile site has no QR.
class DouyinQrLoginPage extends ConsumerStatefulWidget {
  const DouyinQrLoginPage({super.key});

  @override
  ConsumerState<DouyinQrLoginPage> createState() => _DouyinQrLoginPageState();
}

class _DouyinQrLoginPageState extends ConsumerState<DouyinQrLoginPage> {
  static final WebUri _loginUrl = WebUri('https://sso.douyin.com/login/?service=https%3A%2F%2Fwww.douyin.com%2F');
  static final WebUri _cookieUrl = WebUri('https://www.douyin.com/');
  static const Duration _pollInterval = Duration(seconds: 2);

  final CookieManager _cookies = CookieManager.instance();
  Timer? _pollTimer;
  bool _ready = false;
  bool _finished = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// Clears the WebView's own session first: it outlives "clear" on the cookie
  /// page, and would otherwise sign the old account straight back in.
  Future<void> _start() async {
    try {
      await _cookies.deleteCookies(url: _cookieUrl, domain: '.douyin.com');
    } catch (e) {
      CoreLog.error(e);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_checkLogin()));
  }

  Future<void> _checkLogin() async {
    if (_finished) return;
    try {
      final List<Cookie> cookies = await _cookies.getCookies(url: _cookieUrl);
      final String? cookie = douyinLoginCookie({for (final item in cookies) item.name: '${item.value}'});
      if (cookie == null || _finished || !mounted) return;

      _finished = true;
      _pollTimer?.cancel();
      ref.read(cookieControllerProvider.notifier).setDouyinCookie(cookie);
      Navigator.of(context).pop(true);
    } catch (e) {
      CoreLog.error(e);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.black,
            padding: EdgeInsets.symmetric(horizontal: 24.ts(context), vertical: 12.ts(context)),
            child: Text(
              _error.isEmpty ? i18n('douyin_qr_login_hint') : i18n('douyin_qr_login_failed', args: {'error': _error}),
              textAlign: TextAlign.center,
              style: AppTextStyles.t18.copyWith(color: Colors.white),
            ),
          ),
          Expanded(
            child: !_ready
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: _loginUrl),
                    initialSettings: InAppWebViewSettings(
                      userAgent: DouyinSearch.userAgent,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      useWideViewPort: true,
                      loadWithOverviewMode: true,
                    ),
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame != true || !mounted) return;
                      setState(() => _error = error.description);
                    },
                    onLoadStop: (controller, url) => unawaited(_checkLogin()),
                  ),
          ),
        ],
      ),
    );
  }
}
