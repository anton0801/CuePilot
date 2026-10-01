import SwiftUI

@main
struct CuePilotApp: App {
    @StateObject private var container: AppContainer
    @StateObject private var navigator = AppNavigator()
    @StateObject private var keyboard = KeyboardObserver()
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegateApp

    init() {
        AppearanceSetup.apply()
        _container = StateObject(wrappedValue: AppContainer.live())
//        #if DEBUG
//        _container = StateObject(wrappedValue: DebugScenario.makeContainer() ?? AppContainer.live())
//        #else
//        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(navigator)
                .environmentObject(keyboard)
                .preferredColorScheme(.light)
        }
    }
}
