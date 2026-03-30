import SwiftUI

@main
struct OpenMeowApp: App {
    @State private var appState = AppState()

    init() {
        // Register defaults (CORS enabled with local origins on first launch)
        UserDefaults.standard.register(defaults: [
            AppConstants.corsEnabledKey: true,
        ])

        // Apply stored language preference before UI loads
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if lang != "system" {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        MenuBarExtra("OpenMeow", image: "MenuBarIcon") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("OpenMeow", id: "dashboard") {
            MainContentView()
                .environment(appState)
        }
        .defaultSize(width: 780, height: 520)
    }
}
