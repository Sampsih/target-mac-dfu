import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if DownloadManager.shared.phase == .downloading {
            DownloadManager.shared.prepareForTermination {
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }
}

@main
struct TargetMacDFUApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 690)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 820)
    }
}
