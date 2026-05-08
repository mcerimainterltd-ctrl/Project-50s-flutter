import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications
import CallKit
import AVFoundation
import PushKit

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate, PKPushRegistryDelegate {

    var callChannel: FlutterMethodChannel?
    let callKitService = CallKitService.shared

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        GeneratedPluginRegistrant.register(with: self)

        // Setup method channel
        if let controller = window?.rootViewController as? FlutterViewController {
            callChannel = FlutterMethodChannel(
                name: "com.xamepage.app/call",
                binaryMessenger: controller.binaryMessenger
            )
            callChannel?.setMethodCallHandler { [weak self] call, result in
                switch call.method {
                case "startCallService":
                    let callerName = call.arguments as? [String: Any]
                    let name = callerName?["callerName"] as? String ?? "Unknown"
                    let type = callerName?["callType"] as? String ?? "voice"
                    self?.callKitService.reportIncomingCall(callerName: name, callType: type)
                    result(nil)
                case "stopCallService":
                    self?.callKitService.endCall()
                    result(nil)
                case "dismissIncomingCall":
                    self?.callKitService.endCall()
                    result(nil)
                case "keepScreenOn":
                    UIApplication.shared.isIdleTimerDisabled = true
                    result(nil)
                case "releaseScreen":
                    UIApplication.shared.isIdleTimerDisabled = false
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        // Request notification permissions
        UNUserNotificationCenter.current().delegate = self
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in }
        application.registerForRemoteNotifications()

        // FCM delegate
        Messaging.messaging().delegate = self

        // VoIP push registry
        let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - FCM Token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: ["token": token]
        )
    }

    // MARK: - VoIP Push (PKPushRegistryDelegate)
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("[VoIP] Token: \(token)")
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let data = payload.dictionaryPayload
        let callerName = data["callerName"] as? String ?? "Unknown"
        let callType = data["callType"] as? String ?? "voice"
        callKitService.reportIncomingCall(callerName: callerName, callType: callType)
        completion()
    }

    // MARK: - Remote notifications
    override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
}
