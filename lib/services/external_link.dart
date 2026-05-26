import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 외부 링크 (mailto / tel / 외부 도메인) OS handoff 처리.
///
/// WebView NavigationDelegate.onNavigationRequest 에서 호출.
class ExternalLinkService {
  ExternalLinkService._();

  /// 주어진 url 이 WebView 내에서 처리하면 안 되는(외부) 링크인지 판단.
  /// allowedHost: WebView 안에서 그대로 열어야 할 서비스 도메인 (예: serviceURL 호스트).
  static bool isExternal(String url, {required String allowedHost}) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    // mailto:, tel:, sms: 같은 special scheme 은 무조건 외부
    if (uri.scheme == 'mailto' || uri.scheme == 'tel' || uri.scheme == 'sms') {
      return true;
    }
    // http/https 인데 호스트가 다르면 외부
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.host != allowedHost) {
      return true;
    }
    return false;
  }


  /// OS 기본 앱으로 링크 열기. 실패 시 false 반환.
  static Future<bool> open(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('❌ 외부 링크 열기 실패: $e');
      return false;
    }
  }
}
