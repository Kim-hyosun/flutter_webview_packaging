import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'device_info.dart';
import 'notifications.dart';
import 'session.dart';

/// FCM 권한 요청 + 토큰 관리 + 메시지 핸들러.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _token;

  String? get token => _token;

  /// 초기 셋업 — 권한 + 토큰 + 메시지 리스너 등록.
  /// baseUrl: device info 전송용. 토큰 갱신 시 재전송.
  Future<void> setup({required String baseUrl}) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    try {
      _token = await _messaging.getToken();
      debugPrint('📱 초기 FCM Token: $_token');
    } catch (e) {
      debugPrint('❌ FCM 토큰 요청 중 오류 발생: $e');
    }

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('🔔 포그라운드 메시지 수신: ${message.notification?.title}');
      if (message.notification != null) {
        NotificationService.instance.show(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint(
        '📬 알림 클릭으로 앱 열림: ${message.notification?.title} / ${message.data}',
      );
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
        '📥 앱 종료 상태에서 알림으로 열림: ${initialMessage.notification?.title} / ${initialMessage.data}',
      );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      _token = newToken;
      debugPrint('🔄 갱신된 FCM Token: $_token');

      if (SessionService.instance.value != null) {
        await DeviceInfoService.instance.sendToServer(
          baseUrl: baseUrl,
          fcmToken: _token,
        );
        debugPrint('📤 갱신된 FCM Token과 함께 DeviceInfo 재전송 완료');
      } else {
        debugPrint('❌ 세션 쿠키 없음: DeviceInfo 재전송 실패');
      }
    });
  }
}
