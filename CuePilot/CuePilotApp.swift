//
//  CuePilotApp.swift
//  CuePilot
//
//  Created by Anton Danilov on 22/9/26.
//

import SwiftUI

@main
struct CuePilotApp: App {
    @StateObject private var container: AppContainer
    @StateObject private var navigator = AppNavigator()
    @StateObject private var keyboard = KeyboardObserver()

    init() {
        AppearanceSetup.apply()
        #if DEBUG
        _container = StateObject(wrappedValue: DebugScenario.makeContainer() ?? AppContainer.live())
        #else
        _container = StateObject(wrappedValue: AppContainer.live())
        #endif
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
