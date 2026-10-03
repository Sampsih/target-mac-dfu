import Foundation

enum AppOperation: Equatable {
    case checking
    case enteringDFU
    case preflight
    case importingIPSW
    case restoring

    var protectsTermination: Bool { self == .enteringDFU || self == .restoring }
}

@MainActor
protocol ActivityHolding: AnyObject {
    func begin() -> NSObjectProtocol
    func end(_ token: NSObjectProtocol)
}

@MainActor
final class HostActivity: ActivityHolding {
    func begin() -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Target Mac DFU: keep the host awake during DFU or Restore"
        )
    }

    func end(_ token: NSObjectProtocol) { ProcessInfo.processInfo.endActivity(token) }
}

/// One gate for every operation that can change the target or its selected IPSW.
@MainActor
final class OperationCoordinator {
    private(set) var current: AppOperation?
    private let activity: ActivityHolding
    private var activityToken: NSObjectProtocol?

    init(activity: ActivityHolding? = nil) { self.activity = activity ?? HostActivity() }

    var protectsTermination: Bool { current?.protectsTermination == true }

    @discardableResult
    func begin(_ operation: AppOperation) -> Bool {
        guard current == nil else { return false }
        current = operation
        updateActivity()
        return true
    }

    func transition(to operation: AppOperation) {
        precondition(current != nil, "An operation must already own the gate")
        current = operation
        updateActivity()
    }

    func finish() {
        current = nil
        updateActivity()
    }

    private func updateActivity() {
        if protectsTermination, activityToken == nil {
            activityToken = activity.begin()
        } else if !protectsTermination, let token = activityToken {
            activity.end(token)
            activityToken = nil
        }
    }
}
