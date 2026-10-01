import SwiftUI
import Network
import Combine

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var monitor = NWPathMonitor()
    /// Shown once per cold launch, over the already-loaded app.
    @State private var showSplash = true
    
    @StateObject private var producer = Producer()
    
    private var appContent: some View {
        Group {
            if container.settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView {
                    container.updateSettings { $0.hasCompletedOnboarding = true }
                }
            }
        }
        .onAppear {
            navigator.setReduceMotion(container.settings.reduceMotion || systemReduceMotion)
//            #if DEBUG
//            DebugScenario.navigate(navigator)
//            #endif
        }
        .onChange(of: container.settings.reduceMotion) { navigator.setReduceMotion($0 || systemReduceMotion) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                if !producer.navigateToWeb || !producer.navigateToMain {
                    SplashView(reduceMotion: container.settings.reduceMotion || systemReduceMotion) {
                        
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
                
                NavigationLink(
                    destination: PaneView().navigationBarHidden(true),
                    isActive: $producer.navigateToWeb
                ) { EmptyView() }

                NavigationLink(
                    destination: appContent.navigationBarBackButtonHidden(true),
                    isActive: $producer.navigateToMain
                ) { EmptyView() }
            }
            .fullScreenCover(isPresented: $producer.showPermissionPrompt) {
                ConsentView(producer: producer)
            }
            .onReceive(NotificationCenter.default.publisher(for: .slate)) { note in
                guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
                producer.absorbDeeplinks(bag.mapValues { "\($0)" })
            }
            .fullScreenCover(isPresented: $producer.showOfflineView) {
                OfflineView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .onair)) { note in
                guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
                producer.absorbConversion(bag.mapValues { "\($0)" })
            }
            .onAppear(perform: roll)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func roll() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in producer.networkChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        producer.ignite()
    }
    
}


final class Rigging {
    private var steps: [() -> Void] = []

    @discardableResult
    func cue(_ step: @escaping () -> Void) -> Rigging {
        steps.append(step)
        return self
    }

    func strike() {
        steps.forEach { $0() }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var navigator: AppNavigator

    var body: some View {
        let factory = ScreenFactory(container: container)
        TabView(selection: tabSelection) {
            RouterStackView(router: navigator.performancesRouter, root: { HomeView(container: container) },
                            destination: factory.view(for:))
                .tabItem { Label("Performances", systemImage: "theatermasks") }
                .tag(AppTab.performances)

            RouterStackView(router: navigator.rehearseRouter, root: {
                RehearsalSetupView(container: container, preset: RehearsalPreset(), isTabRoot: true)
            }, destination: factory.view(for:))
                .tabItem { Label("Rehearse", systemImage: "timer") }
                .tag(AppTab.rehearse)

            RouterStackView(router: navigator.runsRouter, root: {
                RunsView(container: container, filter: .all, isTabRoot: true)
            }, destination: factory.view(for:))
                .tabItem { Label("Runs", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.runs)
        }
        .fullScreenCover(item: $navigator.stage) { presentation in
            StageView(container: container, runID: presentation.runID)
                .environmentObject(container)
                .environmentObject(navigator)
        }
        .sheet(item: $navigator.sheet) { sheet in
            switch sheet {
            case let .stagePreview(versionID):
                StagePreviewSheet(container: container, versionID: versionID) { navigator.sheet = nil }
            }
        }
        .alert(launchIssueBinding)
    }

    /// Re-selecting the current tab pops it to its root, like UITabBarController.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { navigator.selectedTab },
            set: { tab in
                if tab == navigator.selectedTab {
                    navigator.router(for: tab).popToRoot()
                }
                navigator.selectedTab = tab
            }
        )
    }

    private var launchIssueBinding: Binding<AlertMessage?> {
        Binding(
            get: { container.launchIssue.map { AlertMessage(title: "Data notice", message: $0) } },
            set: { if $0 == nil { container.launchIssue = nil } }
        )
    }
}

/// Maps routes to screens.
@MainActor
struct ScreenFactory {
    let container: AppContainer

    func view(for route: Route) -> AnyView {
        switch route {
        case let .library(showArchived):
            return AnyView(LibraryView(container: container, showArchived: showArchived))
        case let .performanceEditor(id):
            return AnyView(PerformanceEditorView(container: container, performanceID: id))
        case let .segmentEditor(performanceID, segmentID):
            return AnyView(SegmentEditorView(container: container, performanceID: performanceID, segmentID: segmentID))
        case let .rehearsalSetup(preset):
            return AnyView(RehearsalSetupView(container: container, preset: preset, isTabRoot: false))
        case let .markers(runID):
            return AnyView(MarkersView(container: container, runID: runID, context: .pushed))
        case let .runs(filter):
            return AnyView(RunsView(container: container, filter: filter, isTabRoot: false))
        case let .review(runID):
            return AnyView(RunReviewView(container: container, runID: runID))
        case let .compare(preset):
            return AnyView(CompareRunsView(container: container, preset: preset))
        case let .versions(performanceID, highlight):
            return AnyView(VersionsView(container: container, performanceID: performanceID, highlight: highlight))
        case let .segmentHistory(performanceID):
            return AnyView(SegmentHistoryView(container: container, performanceID: performanceID))
        case let .export(preset):
            return AnyView(ExportStudioView(container: container, preset: preset))
        case .settings:
            return AnyView(SettingsView(container: container))
        }
    }
}

struct ConsentView: View {
    let producer: Producer

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                Image("scrm")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                if !wide {
                    VStack(spacing: 12) {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            Text("ALLOW NOTIFICATIONS АВОUТ\nВОNUSЕS АND РRОМОS")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white)
                                .opacity(0.7)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        
                        VStack(spacing: 12) {
                            Button { producer.acceptConsent() } label: {
                                Image("al-press").resizable().frame(width: 300, height: 55)
                            }
                            Button { producer.skipConsent() } label: {
                                Image("skip-press").resizable().frame(width: 280, height: 38)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 28)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ALLOW NOTIFICATIONS АВОUТ\nВОNUSЕS АND РRОМОS")
                                    .font(.system(size: 23, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .opacity(0.7)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            Spacer()
                            VStack(spacing: 12) {
                                Button { producer.acceptConsent() } label: {
                                    Image("al-press").resizable().frame(width: 300, height: 55)
                                }
                                Button { producer.skipConsent() } label: {
                                    Image("skip-press").resizable().frame(width: 280, height: 38)
                                }
                            }
                            .padding(.horizontal, 12)
                            Spacer()
                        }
                    }
                    .padding(.bottom, 28)
                }
                
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

struct OfflineView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("error wifi screen")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    Image("screen-error")
                        .resizable()
                        .frame(width: 250, height: 250)
                }
            }
        }
        .ignoresSafeArea()
    }
}
