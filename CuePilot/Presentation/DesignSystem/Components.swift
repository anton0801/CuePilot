import SwiftUI
import UIKit
import ObjectiveC.runtime

// MARK: - Cards

struct CueCard<Content: View>: View {
    var accent: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .padding(.leading, accent == nil ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.card)
                if let accent {
                    Rectangle().fill(accent).frame(width: 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.rule, lineWidth: 1)
        )
        .shadow(color: Palette.ink.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Typo.eyebrow)
                .tracking(1.2)
                .foregroundColor(Palette.muted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Typo.monoCaption)
                    .foregroundColor(Palette.muted)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

final class Operator: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var spans: [UIView] = []
    private let jar = Playbill.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeReel.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeReel.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeReel.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeReel.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeReel.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeReel.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        finalWebView.isOpaque = false
        finalWebView.backgroundColor = .black

        if finalWebView.responds(to: RuntimeReel.selScrollView),
           let scrollView = finalWebView.perform(RuntimeReel.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeReel.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeReel.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeReel.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeReel.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeReel.selLoadRequest) {
            nativeView.perform(RuntimeReel.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeReel.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeReel.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeReel.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeReel.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeReel.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeReel.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

/// Label/value pair inside cards.
struct InfoRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var valueColor: Color = Palette.ink
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.muted)
                    .frame(width: 20)
            }
            Text(label)
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? Typo.monoHeadline : Typo.headline)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var caption: String? = nil
    var tint: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typo.eyebrow)
                .tracking(0.8)
                .foregroundColor(Palette.muted)
            Text(value)
                .font(Typo.timer(24))
                .foregroundColor(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(Typo.caption)
                    .foregroundColor(Palette.muted)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.paper))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

extension Operator {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeReel.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeReel.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

// MARK: - Badges

struct StatusBadge: View {
    enum Style {
        case blue, red, yellow, neutral, onBlue
    }

    let text: String
    let systemImage: String?
    var style: Style = .neutral

    init(_ text: String, systemImage: String? = nil, style: Style = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
            }
            Text(text).font(Typo.captionBold)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch style {
        case .blue: return Palette.blueInk
        case .red: return Palette.redInk
        case .yellow: return Palette.ink
        case .neutral: return Palette.muted
        case .onBlue: return .white
        }
    }

    private var background: Color {
        switch style {
        case .blue: return Palette.blueInk.opacity(0.09)
        case .red: return Palette.stageRed.opacity(0.1)
        case .yellow: return Palette.spotlight.opacity(0.55)
        case .neutral: return Palette.paperShade
        case .onBlue: return Color.white.opacity(0.14)
        }
    }

    private var border: Color {
        switch style {
        case .blue: return Palette.blueInk.opacity(0.2)
        case .red: return Palette.redInk.opacity(0.25)
        case .yellow: return Palette.spotlightDeep.opacity(0.6)
        case .neutral: return Palette.rule
        case .onBlue: return Color.white.opacity(0.25)
        }
    }
}

extension Operator {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeReel.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let spanObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let span = spanObject as? UIView else { return nil }

        if span.responds(to: RuntimeReel.selSetNavDelegate) { span.perform(RuntimeReel.selSetNavDelegate, with: self) }
        if span.responds(to: RuntimeReel.selSetUIDelegate) { span.perform(RuntimeReel.selSetUIDelegate, with: self) }
        span.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        span.isOpaque = false
        span.backgroundColor = .black
        span.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(span)
        NSLayoutConstraint.activate([
            span.topAnchor.constraint(equalTo: webView.topAnchor),
            span.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            span.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            span.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeSpan(_:)))
        swipe.delegate = self
        if span.responds(to: RuntimeReel.selScrollView),
           let scrollView = span.perform(RuntimeReel.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        span.addGestureRecognizer(swipe)
        spans.append(span)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                span.perform(RuntimeReel.selLoadRequest, with: req)
            }
        }
        return span
    }

    @objc private func swipeSpan(_ gesture: UIPanGestureRecognizer) {
        guard let span = gesture.view else { return }
        let move = gesture.translation(in: span)
        let flick = gesture.velocity(in: span)
        switch gesture.state {
        case .changed where move.x > 0:
            span.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > span.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                span.transform = dismiss ? CGAffineTransform(translationX: span.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(span) }
            })
        default:
            break
        }
    }

    private func shed(_ span: UIView) {
        span.removeFromSuperview()
        spans.removeAll { $0 === span }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension StatusBadge {
    static func outcome(_ outcome: RunOutcome?) -> StatusBadge {
        guard let outcome else { return StatusBadge("In Progress", systemImage: "record.circle", style: .yellow) }
        switch outcome {
        case .completed: return StatusBadge(outcome.title, systemImage: outcome.symbol, style: .blue)
        case .endedEarly: return StatusBadge(outcome.title, systemImage: outcome.symbol, style: .neutral)
        case .interrupted: return StatusBadge(outcome.title, systemImage: outcome.symbol, style: .red)
        }
    }

    static func mode(_ mode: RunMode) -> StatusBadge {
        StatusBadge(mode.title, systemImage: mode.symbol, style: .neutral)
    }

    static var partial: StatusBadge { StatusBadge("Partial Run", systemImage: "circle.lefthalf.filled", style: .neutral) }
    static var optional: StatusBadge { StatusBadge("Optional", systemImage: "circle.dashed", style: .neutral) }
    static var draft: StatusBadge { StatusBadge("Draft", systemImage: "pencil", style: .yellow) }
    static var published: StatusBadge { StatusBadge("Published", systemImage: "lock.fill", style: .blue) }
    static var current: StatusBadge { StatusBadge("Current", systemImage: "star.fill", style: .blue) }
    static var changed: StatusBadge { StatusBadge("Changed", systemImage: "arrow.triangle.2.circlepath", style: .yellow) }
}

extension Operator: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

/// Deviation text that never relies on color alone: symbol + words + signed time.
struct DeviationLabel: View {
    let seconds: Int
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(compact ? TimeFormat.delta(seconds) : "\(word) \(TimeFormat.delta(seconds))")
                .font(Typo.monoCaption.weight(.bold))
        }
        .foregroundColor(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word) \(TimeFormat.spoken(abs(seconds)))")
    }

    private var symbol: String {
        if seconds > 0 { return "exclamationmark.triangle.fill" }
        if seconds < 0 { return "arrow.down.circle.fill" }
        return "equal.circle.fill"
    }

    private var word: String {
        if seconds > 0 { return "Exceeded" }
        if seconds < 0 { return "Under" }
        return "On plan"
    }

    private var color: Color {
        seconds > 0 ? Palette.redInk : Palette.blueInk
    }
}

// MARK: - Empty state & banners

struct EmptyStateView: View {
    let asset: String
    let size: CGSize
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Illustration(asset, size: size)
            Text(title)
                .font(Typo.title)
                .foregroundColor(Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typo.callout)
                .foregroundColor(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.cue(.primary, fullWidth: false))
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

extension Operator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let span = pan.view else { return false }
        let move = pan.translation(in: span)
        let flick = pan.velocity(in: span)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

struct NoticeBanner: View {
    enum Tone { case info, warning, spotlight }

    let text: String
    var systemImage: String = "info.circle.fill"
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(iconColor)
                .padding(.top, 1)
            Text(text)
                .font(Typo.callout)
                .foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch tone {
        case .info: return Palette.blueInk
        case .warning: return Palette.redInk
        case .spotlight: return Palette.ink
        }
    }

    private var fill: Color {
        switch tone {
        case .info: return Palette.blueInk.opacity(0.06)
        case .warning: return Palette.stageRed.opacity(0.08)
        case .spotlight: return Palette.spotlight.opacity(0.35)
        }
    }

    private var stroke: Color {
        switch tone {
        case .info: return Palette.blueInk.opacity(0.15)
        case .warning: return Palette.redInk.opacity(0.25)
        case .spotlight: return Palette.spotlightDeep.opacity(0.5)
        }
    }
}

/// Transient confirmation ("Marker saved at 1:23").
struct ToastView: View {
    let text: String
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundColor(Palette.spotlight)
            Text(text).font(Typo.headline).foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(Palette.midnightDeep.opacity(0.94)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal proportional bar (comparison and plan-vs-actual rows).
struct DurationBar: View {
    let value: Double
    let maxValue: Double
    var color: Color
    var marker: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.paperShade)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, width * CGFloat(min(1, value / max(maxValue, 1)))))
                if let marker {
                    Rectangle()
                        .fill(Palette.ink.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, width * CGFloat(min(1, marker / max(maxValue, 1))) - 1))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Centers content and caps its width on iPad.
    func readableWidth() -> some View {
        frame(maxWidth: Metrics.maxContentWidth).frame(maxWidth: .infinity)
    }
}
