import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'session.dart';

/// 디바이스 정보 수집 + 서버 전송.
class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  bool _sent = false;

  /// 앱 최초 실행 시 1회만 전송하기 위한 플래그.
  bool get sent => _sent;

  /// 디바이스 정보 수집 (OS/브랜드/모델/version/manufacturer/device_id).
  Future<Map<String, dynamic>> collect() async {
    final deviceInfo = DeviceInfoPlugin();
    final deviceId = await _getFID();

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return {
        'os': 'android',
        'brand': info.brand,
        'model': info.model,
        'version': info.version.release,
        'manufacturer': info.manufacturer,
        'device_id': deviceId,
      };
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return {
        'os': 'ios',
        'brand': 'Apple',
        'model': info.utsname.machine,
        'version': info.systemVersion,
        'manufacturer': 'Apple',
        'device_id': deviceId,
      };
    } else {
      return {'platform': 'unknown'};
    }
  }

  /// 디바이스 정보 + FCM 토큰을 서버에 POST.
  Future<void> sendToServer({
    required String baseUrl,
    required String? fcmToken,
  }) async {
    final deviceData = await collect();
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.version;

    final payload = {
      'fcm_token': fcmToken,
      'device_info': deviceData,
      'app_version': appVersion,
    };
    debugPrint('📤 Device 정보: $deviceData');

    final uri = Uri.parse('$baseUrl/tws/ctx/regdevice');
    final sessionCookie = SessionService.instance.value;
    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (sessionCookie != null) 'Cookie': 'session=$sessionCookie',
        },
        body: jsonEncode(payload),
      );
      _sent = true;
      debugPrint('📤 Device info sent $uri: ${res.statusCode} / ${res.body}');
    } catch (e) {
      debugPrint('❌ Error sending device info: $e');
    }
  }

  Future<String?> _getFID() async {
    try {
      final fid = await FirebaseInstallations.instance.getId();
      debugPrint('Firebase FID: $fid');
      return fid;
    } catch (e) {
      debugPrint('FID를 가져오지 못했습니다: $e');
      return null;
    }
  }
}
