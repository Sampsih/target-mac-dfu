import SwiftUI
import AppKit

private let previewWidth = Double(ProcessInfo.processInfo.environment["TARGET_MAC_DFU_SCREENSHOT_WIDTH"] ?? "1360") ?? 1360
private let previewLight = ProcessInfo.processInfo.environment["TARGET_MAC_DFU_SCREENSHOT_LIGHT"] == "1"

private struct ScreenshotShell<Content: View>: View {
    @ObservedObject var model: AppModel
    let content: Content

    init(model: AppModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                selection: Binding(
                    get: { model.selection },
                    set: { model.selection = $0 }
                ),
                settings: model.settings
            )
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: 660, alignment: .top)
                        .padding(InterfaceMetrics.pagePadding)
                }
                StatusBar(model: model)
            }
        }
        .frame(width: previewWidth, height: 820)
        .background { AppBackdrop() }
        .preferredColorScheme(previewLight ? .light : .dark)
    }
}

@main
struct RenderScreenshots {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw AppError.message("Usage: RenderScreenshots <output-directory>")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.appearance = NSAppearance(named: previewLight ? .aqua : .darkAqua)

        let previewLanguage = ProcessInfo.processInfo.environment["TARGET_MAC_DFU_SCREENSHOT_LANGUAGE"]
            .flatMap(AppLanguage.init(rawValue:)) ?? .russian
        let originalLanguage = AppSettings.shared.language
        let originalDemoMode = AppSettings.shared.demoMode
        defer {
            AppSettings.shared.language = originalLanguage
            AppSettings.shared.demoMode = originalDemoMode
        }
        AppSettings.shared.language = previewLanguage
        AppSettings.shared.demoMode = true
        let model = AppModel()
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        model.selection = .overview
        try render(
            ScreenshotShell(model: model) { OverviewView(model: model) },
            to: output.appendingPathComponent("overview.png")
        )
        model.selection = .dfu
        try render(
            ScreenshotShell(model: model) { DFUGuideView(model: model) },
            to: output.appendingPathComponent("dfu.png")
        )
        model.selection = .settings
        try render(
            ScreenshotShell(model: model) { SettingsView(model: model) },
            to: output.appendingPathComponent("settings.png")
        )
    }

    @MainActor
    private static func render<V: View>(_ root: V, to destination: URL) throws {
        let view = NSHostingView(rootView: root)
        view.appearance = NSAppearance(named: previewLight ? .aqua : .darkAqua)
        view.frame = NSRect(x: 0, y: 0, width: previewWidth, height: 820)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw AppError.message("Could not create screenshot bitmap.")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppError.message("Could not encode screenshot PNG.")
        }
        try png.write(to: destination, options: .atomic)
    }
}
