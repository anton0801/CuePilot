import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private lazy var overlay = Overlay { payload in
        NotificationCenter.default.post(name: .onair, object: nil, userInfo: ["conversionData": payload])
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Rigging()
            .cue { FirebaseApp.configure() }
            .cue { [weak self] in
                guard let self = self else { return }
                let sdk = AppsFlyerLib.shared()
                sdk.appsFlyerDevKey = Playbill.relayKey
                sdk.appleAppID = Playbill.appCode
                sdk.delegate = self
                sdk.deepLinkDelegate = self
                sdk.isDebug = false
            }
            .cue { [weak self] in
                guard let self = self else { return }
                Messaging.messaging().delegate = self
                UNUserNotificationCenter.current().delegate = self
                application.registerForRemoteNotifications()
            }
            .strike()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            harvest(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(stirred), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func stirred() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Marks.att)
            }
        }
    }

    private func harvest(_ payload: [AnyHashable: Any]) {
        tally(payload)

        var found: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            found = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            found = url
        }
        guard let link = found else { return }

        UserDefaults.standard.set(link, forKey: Marks.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .standby, object: nil, userInfo: ["temp_url": link])
        }
    }

    private func tally(_ payload: [AnyHashable: Any]) {
        var raw: Any?
        if let data = payload["data"] as? [AnyHashable: Any], let value = data["message_id"] {
            raw = value
        } else if let value = payload["message_id"] {
            raw = value
        }
        guard let raw = raw else { return }
        let message = "\(raw)"
        guard message.isEmpty == false, message.count <= 128 else { return }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard message.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return }

        let af = AppsFlyerLib.shared().getAppsFlyerUID()
        guard af.isEmpty == false else { return }
        guard var comps = URLComponents(string: Playbill.interaction) else { return }
        comps.queryItems = [URLQueryItem(name: "message_id", value: message)]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["af_id": af])
        URLSession.shared.dataTask(with: request).resume()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Marks.fcm)
            UserDefaults.standard.set(token, forKey: Marks.push)
            UserDefaults(suiteName: Playbill.suite)?.set(token, forKey: Marks.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        harvest(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        harvest(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        harvest(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        overlay.base(conversionInfo)
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Marks.primed) == false else { return }
        NotificationCenter.default.post(name: .slate, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        overlay.patch(deepLink.clickEvent)
    }
}
