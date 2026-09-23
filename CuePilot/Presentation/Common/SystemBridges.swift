import Combine
import PDFKit
import SwiftUI
import UIKit

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
