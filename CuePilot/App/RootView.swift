import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
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
            #if DEBUG
            DebugScenario.navigate(navigator)
            #endif
        }
        .onChange(of: container.settings.reduceMotion) { navigator.setReduceMotion($0 || systemReduceMotion) }
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
        case let .export(preset):
            return AnyView(ExportStudioView(container: container, preset: preset))
        case .settings:
            return AnyView(SettingsView(container: container))
        }
    }
}
