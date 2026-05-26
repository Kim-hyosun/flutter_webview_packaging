import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 로컬 알림 초기화 + 표시. FCM remote message → 로컬 알림 변환.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@drawable/pushicon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('로컬 알림 클릭됨: ${response.payload}');
      },
    );
  }

  Future<void> show(RemoteMessage message) async {
    final notification = message.notification;
    final String? imageUrl = message.data['image'];

    AndroidBitmap<Object> largeIcon;
    if (imageUrl != null) {
      final localPath = await _downloadAndSaveFile(imageUrl, 'largeIcon.png');
      largeIcon = FilePathAndroidBitmap(localPath);
    } else {
      largeIcon = const DrawableResourceAndroidBitmap('pushicon');
    }

    if (notification != null) {
      final androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        largeIcon: largeIcon,
        icon: '@drawable/pushicon',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        details,
      );
    }
  }

  Future<String> _downloadAndSaveFile(String url, String fileName) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String filePath = '${directory.path}/$fileName';
    final response = await http.get(Uri.parse(url));
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }
}
