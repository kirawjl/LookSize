import AppKit
import ApplicationServices
import Foundation
import OSLog

public final class FinderSelectionReader {
    private static let logger = Logger(
        subsystem: "com.wangke.LookSize",
        category: "finder-selection"
    )

    private let queue = DispatchQueue(
        label: "com.wangke.LookSize.finder-selection",
        qos: .userInteractive
    )

    public init() {}

    public func selectedFileURLs(completion: @escaping ([URL]) -> Void) {
        queue.async {
            let urls = Self.readSelectedFileURLs()
            DispatchQueue.main.async {
                completion(urls)
            }
        }
    }

    private static func readSelectedFileURLs() -> [URL] {
        guard AccessibilityPermission.isGranted,
              let finder = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.finder")
                .first else {
            return []
        }

        let appElement = AXUIElementCreateApplication(finder.processIdentifier)
        let focusedWindow = copyElementAttribute(
            appElement,
            kAXFocusedWindowAttribute as CFString
        ) ?? copyElementAttribute(
            appElement,
            kAXMainWindowAttribute as CFString
        )
        let currentDirectory = focusedWindow.flatMap(currentFinderDirectory)

        var selectedElements: [AXUIElement] = []
        if let focusedWindow {
            selectedElements = copyElementArrayAttribute(
                focusedWindow,
                kAXSelectedChildrenAttribute as CFString
            )
        }

        if selectedElements.isEmpty,
           let focusedElement = copyElementAttribute(
               appElement,
               kAXFocusedUIElementAttribute as CFString
           ) {
            selectedElements = copyElementArrayAttribute(
                focusedElement,
                kAXSelectedChildrenAttribute as CFString
            )
        }

        var seen = Set<String>()
        var urls: [URL] = []

        for element in selectedElements {
            guard let url = fileURL(
                from: element,
                currentDirectory: currentDirectory,
                depth: 0
            ) else {
                continue
            }

            let standardizedURL = url.standardizedFileURL
            guard seen.insert(standardizedURL.path).inserted else { continue }
            urls.append(standardizedURL)
        }

        if !urls.isEmpty {
            return urls
        }

        // Quick Look 打开后 Finder 的 AXFocusedWindow 会切换到预览窗口，
        // 且标准 Finder 窗口不公开完整目录 URL，因此用 Apple Event 读取 selection 兜底。
        return readSelectedFileURLsUsingAppleScript()
    }

    private static func readSelectedFileURLsUsingAppleScript() -> [URL] {
        let source = """
        tell application "Finder"
            set selectedItems to selection
            set selectedPaths to {}
            repeat with selectedItem in selectedItems
                try
                    set end of selectedPaths to POSIX path of (selectedItem as alias)
                end try
            end repeat
            return selectedPaths
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return [] }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "未知错误"
            logger.error("读取 Finder selection 失败：\(message, privacy: .public)")
            return []
        }

        var urls: [URL] = []
        if descriptor.numberOfItems > 0 {
            for index in 1...descriptor.numberOfItems {
                guard let path = descriptor.atIndex(index)?.stringValue,
                      !path.isEmpty else {
                    continue
                }
                urls.append(URL(fileURLWithPath: path).standardizedFileURL)
            }
        } else if let path = descriptor.stringValue, !path.isEmpty {
            urls.append(URL(fileURLWithPath: path).standardizedFileURL)
        }

        return urls
    }

    private static func fileURL(
        from element: AXUIElement,
        currentDirectory: URL?,
        depth: Int
    ) -> URL? {
        let attributes = [
            kAXURLAttribute as String,
            kAXDocumentAttribute as String,
            "AXFilename",
            kAXValueAttribute as String,
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String
        ]

        for attribute in attributes {
            if let value = copyAttribute(element, attribute as CFString),
               let url = url(from: value, currentDirectory: currentDirectory) {
                return url
            }
        }

        // Finder 的列表视图经常把 URL 放在选中行的子元素中。
        if depth < 2 {
            let children = copyElementArrayAttribute(
                element,
                kAXChildrenAttribute as CFString
            )
            for child in children.prefix(12) {
                if let url = fileURL(
                    from: child,
                    currentDirectory: currentDirectory,
                    depth: depth + 1
                ) {
                    return url
                }
            }
        }

        if depth == 0,
           let parent = copyElementAttribute(element, kAXParentAttribute as CFString),
           let value = copyAttribute(parent, kAXURLAttribute as CFString),
           let url = url(from: value, currentDirectory: currentDirectory) {
            return url
        }

        return nil
    }

    private static func url(from value: CFTypeRef, currentDirectory: URL?) -> URL? {
        if let url = value as? URL, url.isFileURL {
            return url
        }

        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://"),
           let url = URL(string: trimmed),
           url.isFileURL {
            return url
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        guard let currentDirectory else { return nil }
        let candidate = currentDirectory.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private static func currentFinderDirectory(from window: AXUIElement) -> URL? {
        for attribute in [kAXDocumentAttribute as String, kAXURLAttribute as String] {
            guard let value = copyAttribute(window, attribute as CFString) else { continue }

            if let url = value as? URL, url.isFileURL {
                return url
            }

            if let string = value as? String {
                if string.hasPrefix("file://"), let url = URL(string: string) {
                    return url
                }
                if string.hasPrefix("/") {
                    return URL(fileURLWithPath: string)
                }
            }
        }

        return nil
    }

    private static func copyAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func copyElementAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func copyElementArrayAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> [AXUIElement] {
        guard let value = copyAttribute(element, attribute),
              let values = value as? [AXUIElement] else {
            return []
        }
        return values
    }
}
