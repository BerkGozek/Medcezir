import SwiftUI

@main
struct MedcezirApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Clone Repository…") {
                    NotificationCenter.default.post(name: .showCloneSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let showCloneSheet = Notification.Name("Medcezir.showCloneSheet")
}

extension URL {
    /// Opens this folder or file in the Files app (`shareddocuments://` is the Files app's scheme).
    var filesAppURL: URL? {
        URL(string: "shareddocuments://" + path(percentEncoded: true))
    }
}

/// "iPhone" or "iPad", for UI text that names the device (e.g. "Delete from This iPhone").
@MainActor var deviceModel: String { UIDevice.current.localizedModel }
