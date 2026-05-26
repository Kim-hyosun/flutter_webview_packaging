import 'package:flutter/foundation.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';

/// 세션 쿠키 캡슐화 — 전역 변수 대신 싱글톤.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  String? _cookie;

  /// 현재 메모리상 세션 쿠키 값 (없으면 null).
  String? get value => _cookie;

  /// WebView 쿠키 저장소에서 session 쿠키를 읽어 메모리에 반영.
  Future<String?> refresh(String url) async {
    final cookieManager = WebviewCookieManager();
    final cookies = await cookieManager.getCookies(url);
    final sessionCookies = cookies.where((c) => c.name == 'session');

    if (sessionCookies.isNotEmpty) {
      _cookie = sessionCookies.first.value;
      debugPrint('🍪 session 쿠키 갱신: $_cookie');
    } else {
      debugPrint('❌ session 쿠키를 찾을 수 없음');
    }
    return _cookie;
  }

  /// 로그아웃 시 메모리에서 세션 쿠키 폐기.
  void clear() {
    _cookie = null;
    debugPrint('🔄 logout으로 세션 쿠키 정보삭제');
  }
}
