import Combine
import PDFKit
import SwiftUI
import UIKit
import Foundation
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging

/// Tracks keyboard visibility so headers can offer a "hide keyboard" button (no keyboard toolbar on iOS 15 without NavigationView).
final class KeyboardObserver: ObservableObject {
    @Published private(set) var isVisible = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let center = NotificationCenter.default
        center.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { _ in true }
            .merge(with: center.publisher(for: UIResponder.keyboardWillHideNotification).map { _ in false })
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isVisible = $0 }
            .store(in: &cancellables)
    }
}

/// System share sheet (ShareLink is iOS 16+).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// PDF preview via PDFKit.
struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Palette.paperShade)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
        }
    }
}

final class Broadcaster: Feed {

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func deliver(_ body: [String: String]) async -> Verdict {
        let request = await slate(body)
        var takes = Array(Playbill.gaps.dropLast()).makeIterator()
        while true {
            do {
                return .bearing(try await roll(request))
            } catch let fumble as Fumble {
                if fumble.sealed { return .shuttered }
                let wait = fumble.cool ?? takes.next()
                guard let gap = wait else { return .shuttered }
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            } catch {
                guard let gap = takes.next() else { return .shuttered }
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
        }
    }

    private func roll(_ request: URLRequest) async throws -> String {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw Fumble.dropped }
        if http.statusCode == 404 { throw Fumble.dark404 }
        if http.statusCode == 429 {
            throw Fumble.cooldown(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw Fumble.dropped }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Fumble.static_ }
        guard let ok = json["ok"] as? Bool else { throw Fumble.static_ }
        guard ok else { throw Fumble.cancelled }
        guard let url = json["url"] as? String, url.isEmpty == false else { throw Fumble.static_ }
        return url
    }

    @MainActor
    private func slate(_ body: [String: String]) -> URLRequest {
        var payload: [String: Any] = body
        payload["os"] = "iOS"
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["store_id"] = Playbill.store
        payload["push_token"] = UserDefaults.standard.string(forKey: Marks.push) ?? Messaging.messaging().fcmToken
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: URL(string: Playbill.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}


enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Holds the idle-timer override only while a run is on screen in the foreground.
enum ScreenAwake {
    static func set(_ awake: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != awake {
            UIApplication.shared.isIdleTimerDisabled = awake
        }
    }
}

/// Error alert payload.
struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "Something went wrong", _ error: Error) {
        self.title = title
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

extension View {
    func alert(_ item: Binding<AlertMessage?>) -> some View {
        alert(item: item) { message in
            Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("OK")))
        }
    }

    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
