import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:device_info_plus/device_info_plus.dart'; // 디바이스 정보가져오는 플러그인
import 'dart:convert'; //jsonEncode

import 'package:webview_cookie_manager/webview_cookie_manager.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:firebase_app_installations/firebase_app_installations.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

late final String serviceURL;
late final String baseURL;
//"https://www.energyus-vppc.com";
//..loadRequest(Uri.parse('http://192.168.1.53:1024'));

String? sessionCookie; // 세션 쿠키

String? fcmToken; // FCM 토큰

// 백그라운드 메시지 핸들러 (탑레벨, @pragma 필요)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.notification == null && message.data.isNotEmpty) {
    // notification 필드 없으면 직접 알림 띄움
    await _showNotification(message);
  }
}

Future<void> main() async {
  // .env 로드 시 예외 처리
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ .env 파일 로드 성공");
    // serviceURL = dotenv.env['SERVICE_URL'] ?? 'http://192.168.0.7:1024';
    serviceURL = dotenv.env['SERVICE_URL']!;
    // baseURL = dotenv.env['BASE_URL'] ?? 'http://192.168.1.45:8989';
    baseURL = dotenv.env['BASE_URL']!;
  } catch (e) {
    debugPrint("❌ .env 파일 로드 실패: $e");
  }

  WidgetsFlutterBinding.ensureInitialized();

  FlutterNativeSplash.preserve(
    widgetsBinding: WidgetsBinding.instance,
  ); // 스플래시 유지

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initLocalNotification();

  // Android 13+는 별도 권한
  if (Platform.isAndroid) {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  // 백그라운드 메시지 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final WebViewController _controller;
  late final FirebaseMessaging _messaging;

  bool _deviceInfoSent = false; // 앱최초 실행시 디바이스 정보를 1번 전달하도록 하는 state

  @override
  void initState() {
    super.initState();

    // iPhone Safari UA (예시)
    const iphoneSafariUA =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
        'Mobile/15E148 Safari/604.1';

    // WebView 설정
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(iphoneSafariUA)
      ..addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          final msg = message.message;
          debugPrint('🟢 JavaScriptChannel 메시지: $msg');

          if (msg == "LOGIN_SUCCESS") {
            await _updateSessionCookie();
            _sendDeviceInfoToServer();
            _deviceInfoSent = true; // 이후 중복 전송 방지
          }

          if (msg == "keep-alive") {
            await _updateSessionCookie();
            debugPrint('🔄 keep-alive로 세션 쿠키 갱신: $sessionCookie');
          }

          if (msg == "LOGOUT") {
            sessionCookie = null;
            debugPrint('🔄 logout으로 세션 쿠키 정보삭제: $sessionCookie');
          }
        },
      )
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            try {
              // 약간 딜레이 후 실행 (iOS WKWebView에서 SPA가 준비될 시간 확보)
              Future.delayed(Duration(milliseconds: 100), () async {
                try {
                  await _controller.runJavaScript("""
                     if(window.location.hash !== '#/solis'){
                       window.location.hash = '#/solis';
                       if(typeof window.router !== 'undefined' && window.router.push){
                         window.router.push('/solis');
                       }
                     }
                  """);
                  debugPrint("➡️ 루트 URL -> /#/solis 라우팅 완료 (iOS/Android)");
                } catch (e) {
                  debugPrint("❌ 루트 URL -> /#/solis 라우팅 실패: $e");
                }
              });
            } catch (e) {
              debugPrint("❌ Future.delayed 실행 오류: $e");
            }

            () async {
              debugPrint("✅ Loaded URL: $url");
              // #/pages/home/index로 진입시
              if (!_deviceInfoSent && url.contains('#/pages/home/index')) {
                await _updateSessionCookie();
                if (sessionCookie != null) {
                  _sendDeviceInfoToServer(); //디바이스 정보 전송함수 실행
                  _deviceInfoSent = true; // 이후 중복 전송 방지
                } else {
                  debugPrint("home에서 retry: ❌ session 쿠키가 없어 디바이스 정보 전송 불가");
                }
              }
            }();
          },
          onWebResourceError: (error) {
            debugPrint("WebView load error: ${error.description}");
          },
        ),
      )
      // 필요한 경우 원격 URL이나 asset으로 변경
      ..loadRequest(Uri.parse(serviceURL));

    FlutterNativeSplash.remove(); // 초기화 완료 후 스플래시 제거
    // FCM 설정
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    _messaging = FirebaseMessaging.instance;

    // 권한 요청 (iOS 필요, Android는 알림 권한이 Android 13 이전엔 자동)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    // FCM 토큰 요청
    try {
      String? token = await _messaging.getToken();
      if (token != null) {
        fcmToken = token; // ✅ 전역 변수 갱신
        print('📱 초기 FCM Token: $fcmToken');
      }
    } catch (e) {
      print('❌ FCM 토큰 요청 중 오류 발생: $e');
    }

    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("🔔 포그라운드 메시지 수신: ${message.notification?.title}");
      if (message.notification != null) {
        _showNotification(message);
      }
    });

    // 알림 클릭으로 앱 열림 처리
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        "📬 알림 클릭으로 앱 열림: ${message.notification?.title} / ${message.data}",
      );
    });

    // 앱 종료 상태에서 알림으로 열렸는지 확인
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
        "📥 앱 종료 상태에서 알림으로 열림: ${initialMessage.notification?.title} / ${initialMessage.data}",
      );
    }

    // ✅ 토큰 갱신 감지 및 서버 전송
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      fcmToken = newToken;
      debugPrint('🔄 갱신된 FCM Token: $fcmToken');

      await _updateSessionCookie(); //세션 갱신시키고
      if (sessionCookie != null) {
        await _sendDeviceInfoToServer(); // 갱신된 토큰과 함께 기기 정보 다시 전송
        debugPrint('📤 갱신된 FCM Token과 함께 DeviceInfo 재전송 완료');
      } else {
        debugPrint('❌ 세션 쿠키 없음: DeviceInfo 재전송 실패');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Energyus Monitoring',
      home: Scaffold(
        body: SafeArea(child: WebViewWidget(controller: _controller)),
      ),
    );
  }
}

/* 로컬 알림 초기화 함수 */
Future<void> _initLocalNotification() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@drawable/pushicon');

  // iOS 초기화 설정 추가
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    // 필요한 경우 onDidReceiveLocalNotification 콜백 추가 가능
  );

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      debugPrint('로컬 알림 클릭됨: ${response.payload}');
      // 앱 내부 처리 (예: 웹뷰에 메시지 전달)
    },
  );
}

/* 로컬 알림 실제 표시 */
Future<void> _showNotification(RemoteMessage message) async {
  final notification = message.notification;
  final android = message.notification?.android;

  final String? imageUrl = message.data['image'];
  var largeIcon;

  if (imageUrl != null) {
    final String localPath = await _downloadAndSaveFile(
      imageUrl,
      'largeIcon.png',
    );
    largeIcon = FilePathAndroidBitmap(localPath);
  } else {
    largeIcon = DrawableResourceAndroidBitmap('pushicon');
  }

  if (notification != null) {
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      largeIcon: largeIcon as AndroidBitmap<Object>?,
      icon: '@drawable/pushicon',
    );

    DarwinNotificationDetails iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
    );
  }
}

Future<String> _downloadAndSaveFile(String url, String fileName) async {
  // 서버에서 내려온 image파일을 다운로드
  final Directory directory = await getApplicationDocumentsDirectory();
  final String filePath = '${directory.path}/$fileName';

  final http.Response response = await http.get(Uri.parse(url));
  final File file = File(filePath);
  await file.writeAsBytes(response.bodyBytes);
  return filePath;
}

Future<Map<String, dynamic>> _getDeviceInfo() async {
  // 디바이스 정보 가져오기
  final deviceInfo = DeviceInfoPlugin();
  final deviceId = await getFID();

  if (Platform.isAndroid) {
    final info = await deviceInfo.androidInfo;
    return {
      'os': 'android',
      'brand': info.brand,
      'model': info.model,
      'version': info.version.release,
      'manufacturer': info.manufacturer,
      'device_id': deviceId, //info.id,
    };
  } else if (Platform.isIOS) {
    final info = await deviceInfo.iosInfo;
    return {
      'os': 'ios',
      'brand': 'Apple',
      'model': info.utsname.machine,
      'version': info.systemVersion,
      'manufacturer': 'Apple',
      'device_id': deviceId, //info.identifierForVendor,
    };
  } else {
    return {'platform': 'unknown'};
  }
}

Future<void> _sendDeviceInfoToServer() async {
  final deviceData = await _getDeviceInfo();

  final packageInfo = await PackageInfo.fromPlatform();
  String appVersion = packageInfo.version; // 1.0.0

  final payload = {
    'fcm_token': fcmToken,
    'device_info': deviceData,
    'app_version': appVersion,
  };
  debugPrint('📤 Device 정보: ${deviceData}');

  final uri = Uri.parse('$baseURL/tws/ctx/regdevice'); // 기기정보를 보낼 서버api주소
  try {
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (sessionCookie != null) 'Cookie': 'session=$sessionCookie',
      },
      body: jsonEncode(payload),
    );
    debugPrint('📤 Device info sent ${uri}: ${res.statusCode} / ${res.body}');
  } catch (e) {
    debugPrint('❌ Error sending device info: $e');
  }
}

Future<void> _updateSessionCookie() async {
  final cookieManager = WebviewCookieManager();
  final cookies = await cookieManager.getCookies(serviceURL);

  // 조건에 맞는 쿠키가 있는지 확인
  final sessionCookies = cookies.where((c) => c.name == "session");

  if (sessionCookies.isNotEmpty) {
    final session = sessionCookies.first;
    sessionCookie = session.value; // 전역 변수 갱신
    debugPrint("🍪 session 쿠키 갱신: $sessionCookie");
  } else {
    debugPrint("❌ session 쿠키를 찾을 수 없음");
  }
}

// 기기 아이디로 사용
Future<String?> getFID() async {
  try {
    // Firebase Installations ID(FID) 가져오기
    final fid = await FirebaseInstallations.instance.getId();
    print('Firebase FID: $fid');
    return fid;
  } catch (e) {
    print('FID를 가져오지 못했습니다: $e');
    return null;
  }
}
