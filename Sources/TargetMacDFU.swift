import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        if model.operations.protectsTermination {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.text("Дождитесь завершения операции", "Wait for the operation to finish", model.language)
            alert.informativeText = L10n.text(
                "Сейчас выполняется DFU или Restore. Приложение останется открытым. Не отключайте кабель и питание и не закрывайте крышку Host Mac.",
                "DFU or Restore is running. The app will stay open. Keep cable and power connected and leave the host Mac lid open.",
                model.language
            )
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return .terminateCancel
        }
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
        Window("Target Mac DFU", id: "main") {
            ContentView()
                .frame(minWidth: 1080, minHeight: 690)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 820)
    }
}
