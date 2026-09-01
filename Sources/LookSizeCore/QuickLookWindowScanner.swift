import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct QuickLookWindowSnapshot: Equatable, Sendable {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let title: String?
    public let frame: CGRect

    public init(
        windowID: CGWindowID,
        ownerPID: pid_t,
        title: String?,
        frame: CGRect
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.title = title
        self.frame = frame
    }
}

public struct QuickLookOverlayAnchor: Equatable, Sendable {
    public let fileNameFrame: CGRect
    public let titleRightBoundary: CGFloat
    public let contentFrame: CGRect?

    public init(
        fileNameFrame: CGRect,
        titleRightBoundary: CGFloat,
        contentFrame: CGRect?
    ) {
        self.fileNameFrame = fileNameFrame
        self.titleRightBoundary = titleRightBoundary
        self.contentFrame = contentFrame
    }
}

public final class QuickLookWindowScanner {
    private static let quickLookBundleIdentifiers = Set([
        "com.apple.quicklook.QuickLookUIService",
        "com.apple.QuickLookUIService",
        "com.apple.quicklook.qlmanage"
    ])

    private static let localizedFinderQuickLookTitles = Set([
        "Quick Look",
        "快速查看",
        "快速檢視",
        "クイックルック",
        "빠른 보기"
    ])

    private var cachedWindowID: CGWindowID?
    private var cachedOwnerPID: pid_t = 0
    private var cachedTitle: String?

    public init() {}

    public func visibleWindow() -> QuickLookWindowSnapshot? {
        if let cachedWindowID {
            guard let snapshot = snapshotForCachedWindow(windowID: cachedWindowID) else {
                // 已跟踪的窗口刚消失时立即报告关闭，不在同一轮扫描残留 AX 对象。
                reset()
                return nil
            }
            return snapshot
        }

        // macOS 15 上空格预览窗口属于 Finder，稳定标识是 AXSubrole="Quick Look"。
        if AccessibilityPermission.isGranted,
           let accessibilityWindow = accessibilityQuickLookWindow() {
            cache(accessibilityWindow)
            return accessibilityWindow
        }

        // 兼容旧系统以及 qlmanage/独立 QuickLookUIService 窗口。
        if let coreGraphicsWindow = coreGraphicsQuickLookWindow() {
            cache(coreGraphicsWindow)
            return coreGraphicsWindow
        }

        return nil
    }

    public func reset() {
        cachedWindowID = nil
        cachedOwnerPID = 0
        cachedTitle = nil
    }

    public func overlayAnchor(
        fileName: String,
        in snapshot: QuickLookWindowSnapshot
    ) -> QuickLookOverlayAnchor? {
        guard AccessibilityPermission.isGranted else { return nil }

        let appElement = AXUIElementCreateApplication(snapshot.ownerPID)
        let windows = copyElementArrayAttribute(appElement, kAXWindowsAttribute as CFString)

        for window in windows {
            guard isQuickLookAccessibilityWindow(window),
                  let position = copyPointAttribute(window, kAXPositionAttribute as CFString),
                  let size = copySizeAttribute(window, kAXSizeAttribute as CFString) else {
                continue
            }

            let windowFrame = appKitFrame(fromTopLeftPosition: position, size: size)
            let frameDifference = abs(windowFrame.minX - snapshot.frame.minX)
                + abs(windowFrame.minY - snapshot.frame.minY)
                + abs(windowFrame.width - snapshot.frame.width)
                + abs(windowFrame.height - snapshot.frame.height)
            guard frameDifference <= 16,
                  let fileNameElement = findFileNameElement(
                      in: window,
                      fileName: fileName,
                      depth: 0
                  ),
                  let fileNamePosition = copyPointAttribute(
                      fileNameElement,
                      kAXPositionAttribute as CFString
                  ),
                  let fileNameSize = copySizeAttribute(
                      fileNameElement,
                      kAXSizeAttribute as CFString
                  ) else {
                continue
            }

            let fileNameFrame = appKitFrame(
                fromTopLeftPosition: fileNamePosition,
                size: fileNameSize
            )
            let children = copyElementArrayAttribute(window, kAXChildrenAttribute as CFString)
            let childFrames = children.compactMap { child -> (role: String, frame: CGRect)? in
                guard let childPosition = copyPointAttribute(
                    child,
                    kAXPositionAttribute as CFString
                ),
                      let childSize = copySizeAttribute(
                          child,
                          kAXSizeAttribute as CFString
                      ) else {
                    return nil
                }
                return (
                    copyStringAttribute(child, kAXRoleAttribute as CFString) ?? "",
                    appKitFrame(fromTopLeftPosition: childPosition, size: childSize)
                )
            }
            let titleRightBoundary = childFrames
                .filter {
                    ($0.role == (kAXGroupRole as String)
                        || $0.role == (kAXButtonRole as String))
                        && $0.frame.minX > fileNameFrame.maxX
                }
                .map(\.frame.minX)
                .min() ?? windowFrame.maxX - 12
            let contentFrame = childFrames
                .filter {
                    ($0.role == (kAXScrollAreaRole as String)
                        || $0.role == (kAXImageRole as String))
                        && $0.frame.width > 100
                        && $0.frame.height > 100
                }
                .max {
                    ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
                }?
                .frame

            return QuickLookOverlayAnchor(
                fileNameFrame: fileNameFrame,
                titleRightBoundary: titleRightBoundary,
                contentFrame: contentFrame
            )
        }

        return nil
    }

    private func snapshotForCachedWindow(windowID: CGWindowID) -> QuickLookWindowSnapshot? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowID
        ) as? [[String: Any]],
              let window = windows.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
              }),
              (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              let snapshot = snapshot(
                  fromCoreGraphicsWindow: window,
                  fallbackTitle: cachedTitle
              ),
              snapshot.ownerPID == cachedOwnerPID else {
            return nil
        }

        return snapshot
    }

    private func accessibilityQuickLookWindow() -> QuickLookWindowSnapshot? {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ) + Self.quickLookBundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }

        for application in applications where !application.isTerminated {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            let windows = copyElementArrayAttribute(
                appElement,
                kAXWindowsAttribute as CFString
            )

            for window in windows {
                let subrole = copyStringAttribute(window, kAXSubroleAttribute as CFString)
                let title = copyStringAttribute(window, kAXTitleAttribute as CFString)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isFinderQuickLook = application.bundleIdentifier == "com.apple.finder"
                    && (subrole == "Quick Look"
                        || title.map(Self.localizedFinderQuickLookTitles.contains) == true)
                let isQuickLookService = application.bundleIdentifier.map(
                    Self.quickLookBundleIdentifiers.contains
                ) == true

                guard isFinderQuickLook || isQuickLookService,
                      let position = copyPointAttribute(window, kAXPositionAttribute as CFString),
                      let size = copySizeAttribute(window, kAXSizeAttribute as CFString),
                      size.width > 200,
                      size.height > 150 else {
                    continue
                }

                let quartzFrame = CGRect(origin: position, size: size)
                if let matchedWindow = matchingCoreGraphicsWindow(
                    ownerPID: application.processIdentifier,
                    targetQuartzFrame: quartzFrame,
                    fallbackTitle: title
                ) {
                    return matchedWindow
                }

            }
        }

        return nil
    }

    private func matchingCoreGraphicsWindow(
        ownerPID: pid_t,
        targetQuartzFrame: CGRect,
        fallbackTitle: String?
    ) -> QuickLookWindowSnapshot? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        var bestMatch: (difference: CGFloat, snapshot: QuickLookWindowSnapshot)?

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
                  let bounds = quartzFrame(fromCoreGraphicsWindow: window) else {
                continue
            }

            let positionDifference = abs(bounds.minX - targetQuartzFrame.minX)
                + abs(bounds.minY - targetQuartzFrame.minY)
            let sizeDifference = abs(bounds.width - targetQuartzFrame.width)
                + abs(bounds.height - targetQuartzFrame.height)
            let difference = positionDifference + sizeDifference
            guard difference <= 12,
                  let candidate = snapshot(
                      fromCoreGraphicsWindow: window,
                      fallbackTitle: fallbackTitle
                  ) else {
                continue
            }

            if bestMatch == nil || difference < bestMatch!.difference {
                bestMatch = (difference, candidate)
            }
        }

        return bestMatch?.snapshot
    }

    private func coreGraphicsQuickLookWindow() -> QuickLookWindowSnapshot? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        var candidates: [QuickLookWindowSnapshot] = []

        for window in windows {
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let bundleIdentifier = ownerPID == 0
                ? nil
                : NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let isQuickLookOwner = ownerName.localizedCaseInsensitiveContains("quicklook")
                || ownerName.localizedCaseInsensitiveContains("qlmanage")
                || bundleIdentifier.map(Self.quickLookBundleIdentifiers.contains) == true
            let isFinderQuickLook = bundleIdentifier == "com.apple.finder"
                && title.map(Self.localizedFinderQuickLookTitles.contains) == true
            guard isQuickLookOwner || isFinderQuickLook,
                  let candidate = snapshot(
                      fromCoreGraphicsWindow: window,
                      fallbackTitle: title
                  ) else {
                continue
            }
            candidates.append(candidate)
        }

        // Quick Look 可能包含阴影或辅助窗口，主预览窗口通常面积最大。
        return candidates.max {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }
    }

    private func snapshot(
        fromCoreGraphicsWindow window: [String: Any],
        fallbackTitle: String?
    ) -> QuickLookWindowSnapshot? {
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        let isFinderWindow = ownerPID != 0
            && NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == "com.apple.finder"
        guard layer >= 0,
              (!isFinderWindow || layer > 0),
              alpha > 0.01,
              let quartzFrame = quartzFrame(fromCoreGraphicsWindow: window),
              quartzFrame.width > 200,
              quartzFrame.height > 150 else {
            return nil
        }

        let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
        let coreGraphicsTitle = (window[kCGWindowName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = coreGraphicsTitle?.isEmpty == false ? coreGraphicsTitle : fallbackTitle

        return QuickLookWindowSnapshot(
            windowID: windowID,
            ownerPID: ownerPID,
            title: title?.isEmpty == true ? nil : title,
            frame: appKitFrame(
                fromTopLeftPosition: quartzFrame.origin,
                size: quartzFrame.size
            )
        )
    }

    private func quartzFrame(fromCoreGraphicsWindow window: [String: Any]) -> CGRect? {
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private func cache(_ snapshot: QuickLookWindowSnapshot) {
        cachedWindowID = snapshot.windowID
        cachedOwnerPID = snapshot.ownerPID
        cachedTitle = snapshot.title
    }

    private func appKitFrame(fromTopLeftPosition position: CGPoint, size: CGSize) -> CGRect {
        let primaryScreenHeight = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })?
            .frame.height ?? NSScreen.main?.frame.height ?? 0

        return CGRect(
            x: position.x,
            y: primaryScreenHeight - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func isQuickLookAccessibilityWindow(_ window: AXUIElement) -> Bool {
        let subrole = copyStringAttribute(window, kAXSubroleAttribute as CFString)
        let title = copyStringAttribute(window, kAXTitleAttribute as CFString)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return subrole == "Quick Look"
            || title.map(Self.localizedFinderQuickLookTitles.contains) == true
    }

    private func findFileNameElement(
        in element: AXUIElement,
        fileName: String,
        depth: Int
    ) -> AXUIElement? {
        guard depth <= 5 else { return nil }

        let role = copyStringAttribute(element, kAXRoleAttribute as CFString)
        if role == (kAXStaticTextRole as String) {
            let candidate = copyStringAttribute(element, kAXValueAttribute as CFString)
                ?? copyStringAttribute(element, kAXTitleAttribute as CFString)
            if candidate.map({ fileNameMatches($0, target: fileName) }) == true {
                return element
            }
        }

        for child in copyElementArrayAttribute(element, kAXChildrenAttribute as CFString) {
            if let match = findFileNameElement(
                in: child,
                fileName: fileName,
                depth: depth + 1
            ) {
                return match
            }
        }

        return nil
    }

    private func fileNameMatches(_ candidate: String, target: String) -> Bool {
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        if normalizedCandidate.compare(normalizedTarget, options: options) == .orderedSame {
            return true
        }

        let targetWithoutExtension = (normalizedTarget as NSString).deletingPathExtension
        return !targetWithoutExtension.isEmpty
            && normalizedCandidate.compare(targetWithoutExtension, options: options) == .orderedSame
    }

    private func copyAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyElementArrayAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> [AXUIElement] {
        guard let value = copyAttribute(element, attribute),
              let elements = value as? [AXUIElement] else {
            return []
        }
        return elements
    }

    private func copyStringAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private func copyPointAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CGPoint? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func copySizeAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CGSize? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
