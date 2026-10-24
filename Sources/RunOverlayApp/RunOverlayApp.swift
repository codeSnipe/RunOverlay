import SwiftUI

@main
struct RunOverlayApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 1_080, minHeight: 680)
                .onOpenURL { url in
                    appModel.openProject(at: url)
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(AppStrings.text("ui.project.new")) {
                    appModel.createNewProject()
                }
                .keyboardShortcut("n")
                .disabled(appModel.exportBatchHasStarted)

                Button(AppStrings.text("ui.project.open")) {
                    appModel.presentOpenProjectPanel()
                }
                .keyboardShortcut("o")
                .disabled(appModel.exportBatchHasStarted)

                Button(AppStrings.text("ui.project.save")) {
                    appModel.presentSaveProjectPanel()
                }
                .keyboardShortcut("s")

                Divider()

                Button(AppStrings.text("ui.project.package")) {
                    appModel.packageProject()
                }
                .disabled(
                    appModel.project.videos.isEmpty ||
                    appModel.isPackagingProject ||
                    appModel.exportBatchHasStarted
                )

                Button(AppStrings.text("ui.project.relink")) {
                    appModel.presentRelinkMissingResourcesPanel()
                }
                .disabled(
                    appModel.exportBatchHasStarted ||
                    (appModel.missingResourceVideoIDs.isEmpty &&
                        !appModel.isActivityResourceMissing)
                )
            }

            CommandGroup(after: .pasteboard) {
                Button(AppStrings.text("ui.deleteVideo")) {
                    appModel.removeSelectedVideo()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(
                    !appModel.canDeleteSelectedVideo ||
                        appModel.exportBatchHasStarted
                )
            }
        }
    }
}
