import Flutter
import UIKit
import Firebase
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // UNUserNotificationCenter delegate 설정
    UNUserNotificationCenter.current().delegate = self

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 부모 클래스에 선언된 메서드이므로 override 필요
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // 포그라운드에서도 알림 배너, 사운드, 배지 표시
    if #available(iOS 14.0, *) {
    completionHandler([.banner, .sound, .badge])
  } else {
    // iOS 14 미만은 .alert 사용 (banner 대신)
    completionHandler([.alert, .sound, .badge])
  }
  }
}
