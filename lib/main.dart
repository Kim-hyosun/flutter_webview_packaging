import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/fcm.dart';
import 'services/notifications.dart';

/// 백그라운드 메시지 핸들러 (탑레벨, @pragma 필요).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.notification == null && message.data.isNotEmpty) {
    await NotificationService.instance.show(message);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsBinding.instance);

  // .env 로드 — 실패 시 fatal stop (URL 없으면 앱 자체가 무의미)
  String serviceUrl;
  String baseUrl;
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env 파일 로드 성공');
    final svc = dotenv.env['SERVICE_URL'];
    final base = dotenv.env['BASE_URL'];
    if (svc == null || svc.isEmpty) {
      throw StateError('SERVICE_URL 가 .env 에 없습니다');
    }
    if (base == null || base.isEmpty) {
      throw StateError('BASE_URL 가 .env 에 없습니다');
    }
    serviceUrl = svc;
    baseUrl = base;
  } catch (e) {
    debugPrint('❌ .env 파일 로드 실패: $e');
    rethrow;
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();

  // Android 13+ 알림 권한 별도
  if (Platform.isAndroid) {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  // 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // FCM setup (권한 + 토큰 + 리스너)
  await FcmService.instance.setup(baseUrl: baseUrl);

  FlutterNativeSplash.remove();

  runApp(MyApp(serviceUrl: serviceUrl, baseUrl: baseUrl));
}
