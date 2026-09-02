import AppKit
import CoreServices
import Foundation

public enum FinderAutomationPermissionStatus: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
    case targetNotRunning
    case unavailable(OSStatus)

    public var isAuthorized: Bool {
        self == .authorized
    }
}

public enum FinderAutomationPermission {
    private static let finderBundleIdentifier = "com.apple.finder"
    private static let eventNotPermittedStatus = OSStatus(errAEEventNotPermitted)
    private static let eventWouldRequireConsentStatus = OSStatus(
        errAEEventWouldRequireUserConsent
    )
    private static let processNotFoundStatus = OSStatus(procNotFound)

    public static func status(prompt: Bool = false) -> FinderAutomationPermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: finderBundleIdentifier)
        let result = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            prompt
        )
        return status(for: result)
    }

    public static func status(for result: OSStatus) -> FinderAutomationPermissionStatus {
        switch result {
        case noErr:
            return .authorized
        case eventNotPermittedStatus:
            return .denied
        case eventWouldRequireConsentStatus:
            return .notDetermined
        case processNotFoundStatus:
            return .targetNotRunning
        default:
            return .unavailable(result)
        }
    }
}
