import AppKit
import RunOverlayCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isPreviewFullscreen = false
    @State private var previewWindow: NSWindow?
    @State private var shouldRestoreWindowSize = false
    @State private var coverEditorWindowManager = CoverEditorWindowManager()
    @State private var smartEditWindowManager = SmartEditWindowManager()
    @State private var isShowingReleaseHistory = false
    @State private var smartEditExportQueue: SmartEditBackgroundExportQueue?

    var body: some View {
        Group {
            if isPreviewFullscreen, let video = appModel.selectedVideo {
                FullscreenPreviewView(video: video, onExit: exitFullscreenPreview)
            } else {
                editor
            }
        }
        .preferredColorScheme(.dark)
        .tint(EditorTheme.accent)
        .background {
            PlaybackKeyboardMonitor(
                isEnabled: appModel.selectedVideo != nil &&
                    appModel.player.currentItem != nil,
                isPreviewFullscreen: isPreviewFullscreen,
                onTogglePlayback: { appModel.togglePlayback() },
                onSkipPlayback: { appModel.skipPlayback(by: $0) },
                onExitFullscreen: exitFullscreenPreview
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window === previewWindow else {
                return
            }
            isPreviewFullscreen = false
            previewWindow = nil
            shouldRestoreWindowSize = false
        }
        .onChange(of: appModel.selectedVideoID) { _, selectedVideoID in
            if selectedVideoID == nil && isPreviewFullscreen {
                exitFullscreenPreview()
            }
        }
        .onChange(of: appModel.isCoverEditorPresented) { _, presented in
            if presented, let videoID = appModel.coverEditorVideoID {
                coverEditorWindowManager.present(videoID: videoID, appModel: appModel)
            } else {
                coverEditorWindowManager.close()
            }
        }
        .onChange(of: appModel.coverEditorVideoID) { _, videoID in
            guard appModel.isCoverEditorPresented, let videoID else { return }
            coverEditorWindowManager.present(videoID: videoID, appModel: appModel)
        }
        .onChange(of: appModel.exportBatchHasStarted) { _, started in
            if started {
                appModel.isCoverEditorPresented = false
            }
        }
        .onDisappear {
            coverEditorWindowManager.close()
            smartEditWindowManager.close()
            appModel.isCoverEditorPresented = false
            appModel.coverEditorVideoID = nil
            appModel.clearCoverEditorFrameTime()
        }
        .sheet(isPresented: $appModel.isExportQueuePresented, onDismiss: {
            appModel.dismissExportQueue()
        }) {
            ExportQueueView()
                .environmentObject(appModel)
                .frame(minWidth: 620, minHeight: 420)
        }
        .sheet(isPresented: $isShowingReleaseHistory) {
            ReleaseHistoryView()
        }
        .alert(item: $appModel.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text(AppStrings.text("ui.common.ok")))
            )
        }
    }

    private var editor: some View {
        NavigationSplitView {
            ProjectSidebar(onShowReleaseHistory: {
                isShowingReleaseHistory = true
            })
                .navigationSplitViewColumnWidth(min: 236, ideal: 286, max: 340)
        } content: {
            EditorWorkspace(
                onEnterFullscreen: enterFullscreenPreview,
                onShowSmartEdit: showSmartEdit,
                smartEditExportQueue: smartEditExportQueue
            )
                .navigationSplitViewColumnWidth(min: 560, ideal: 800)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 370)
        }
        .navigationTitle(appModel.project.name)
        .id(appModel.selectedLanguage)
        .environment(
            \.locale,
            appModel.selectedLanguage == .system
                ? .current
                : Locale(identifier: appModel.selectedLanguage.rawValue)
        )
    }

    private func enterFullscreenPreview() {
        guard appModel.selectedVideo != nil,
              let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }
        previewWindow = window
        shouldRestoreWindowSize = !window.styleMask.contains(.fullScreen)
        isPreviewFullscreen = true
        if shouldRestoreWindowSize {
            window.toggleFullScreen(nil)
        }
    }

    private func exitFullscreenPreview() {
        guard isPreviewFullscreen else {
            return
        }
        isPreviewFullscreen = false
        if shouldRestoreWindowSize,
           let previewWindow,
           previewWindow.styleMask.contains(.fullScreen) {
            previewWindow.toggleFullScreen(nil)
        }
        previewWindow = nil
        shouldRestoreWindowSize = false
    }

    private func showSmartEdit() {
        smartEditWindowManager.present(
            appModel: appModel,
            backgroundExportQueue: $smartEditExportQueue
        )
    }
}

private final class PlaybackKeyboardView: NSView {
    var isEnabled = false
    var isPreviewFullscreen = false
    var onTogglePlayback: (() -> Void)?
    var onSkipPlayback: ((TimeInterval) -> Void)?
    var onExitFullscreen: (() -> Void)?
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window,
                  window.isKeyWindow,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil
            else {
                return event
            }
            let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.intersection(modifiers).isEmpty else {
                return event
            }
            if event.keyCode == 53 && self.isPreviewFullscreen {
                if !event.isARepeat {
                    self.onExitFullscreen?()
                }
                return nil
            }
            guard self.isEnabled, !Self.isEditingText(in: window) else {
                return event
            }

            switch event.keyCode {
            case 49:
                if !event.isARepeat {
                    self.onTogglePlayback?()
                }
            case 123:
                self.onSkipPlayback?(-5)
            case 124:
                self.onSkipPlayback?(5)
            default:
                return event
            }
            return nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private static func isEditingText(in window: NSWindow) -> Bool {
        window.firstResponder is NSTextInputClient
    }

    func stopMonitoring() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

/// 封面编辑独立窗口：标题栏可来回拖动、边角可拖拽缩放，尺寸与位置自动记忆。
@MainActor
private final class CoverEditorWindowManager: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hosting: NSHostingView<AnyView>?
    private var currentVideoID: UUID?
    private weak var appModel: AppModel?

    func present(videoID: UUID, appModel: AppModel) {
        self.appModel = appModel
        let root = AnyView(
            CoverEditorWindowRoot(videoID: videoID)
                .environmentObject(appModel)
        )
        if let window, let hosting {
            if currentVideoID != videoID {
                hosting.rootView = root
                currentVideoID = videoID
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_120, height: 780),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = AppStrings.text("ui.cover.title")
        window.contentMinSize = NSSize(width: 850, height: 610)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("RunOverlayCoverEditorWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.hosting = hosting
        currentVideoID = videoID
    }

    func close() {
        guard let window else { return }
        self.window = nil
        self.hosting = nil
        currentVideoID = nil
        window.delegate = nil
        appModel?.flushCoverAutoSave()
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
        currentVideoID = nil
        appModel?.flushCoverAutoSave()
        appModel?.isCoverEditorPresented = false
        appModel?.coverEditorVideoID = nil
        appModel?.clearCoverEditorFrameTime()
    }
}

private struct CoverEditorWindowRoot: View {
    let videoID: UUID

    var body: some View {
        CoverEditorView(videoID: videoID)
            .frame(minWidth: 850, minHeight: 610)
    }
}

/// 智能成片使用独立窗口，避免系统 sheet 限制全屏切换。
@MainActor
private final class SmartEditWindowManager: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hosting: NSHostingView<AnyView>?

    func present(
        appModel: AppModel,
        backgroundExportQueue: Binding<SmartEditBackgroundExportQueue?>
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = AnyView(
            SmartEditWorkspaceView(
                initialAspectRatio: appModel.project.exportSettings.aspectRatio,
                initialResolution: appModel.project.exportSettings.maximumHeight,
                backgroundExportQueue: backgroundExportQueue,
                onClose: { [weak self] in self?.close() },
                onToggleFullscreen: { [weak self] in self?.toggleFullscreen() }
            )
            .environmentObject(appModel)
            .frame(minWidth: 1_000, minHeight: 680)
        )
        let hosting = NSHostingView(rootView: root)
        let window = SmartEditWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = AppStrings.text("smartEdit.title")
        window.contentMinSize = NSSize(width: 1_000, height: 680)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("RunOverlaySmartEditWindow")
        self.window = window
        self.hosting = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
    }
}

private final class SmartEditWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        // 系统标题栏在用户设置为“双击缩放”时也改为全屏；避开左侧红黄绿窗口按钮。
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           event.locationInWindow.x > 110,
           event.locationInWindow.y > contentRect(forFrameRect: frame).height {
            toggleFullScreen(nil)
            return
        }
        super.sendEvent(event)
    }
}

private struct PlaybackKeyboardMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let isPreviewFullscreen: Bool
    let onTogglePlayback: () -> Void
    let onSkipPlayback: (TimeInterval) -> Void
    let onExitFullscreen: () -> Void

    func makeNSView(context: Context) -> PlaybackKeyboardView {
        let view = PlaybackKeyboardView()
        configure(view)
        return view
    }

    func updateNSView(_ view: PlaybackKeyboardView, context: Context) {
        configure(view)
    }

    static func dismantleNSView(_ view: PlaybackKeyboardView, coordinator: ()) {
        view.stopMonitoring()
    }

    private func configure(_ view: PlaybackKeyboardView) {
        view.isEnabled = isEnabled
        view.isPreviewFullscreen = isPreviewFullscreen
        view.onTogglePlayback = onTogglePlayback
        view.onSkipPlayback = onSkipPlayback
        view.onExitFullscreen = onExitFullscreen
    }
}
