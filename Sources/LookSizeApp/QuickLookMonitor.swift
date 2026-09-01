import AppKit
import Foundation
import LookSizeCore
import OSLog

final class QuickLookMonitor {
    private static let idlePollingInterval: TimeInterval = 0.15
    private static let activeTrackingInterval: TimeInterval = 1.0 / 30.0

    private struct CacheEntry {
        let modificationDate: Date?
        let fileSize: Int64?
        let metadata: MediaDisplayMetadata
    }

    var onStateChange: (() -> Void)?

    private(set) var isEnabled = true
    private(set) var permissionGranted = AccessibilityPermission.isGranted
    private(set) var currentFileName: String?
    private(set) var isQuickLookVisible = false

    private let selectionReader = FinderSelectionReader()
    private let windowScanner = QuickLookWindowScanner()
    private let metadataReader = MediaMetadataReader()
    private let overlay = TitleOverlayController()
    private let logger = Logger(subsystem: "com.wangke.LookSize", category: "monitor")

    private var timer: Timer?
    private var timerInterval: TimeInterval = QuickLookMonitor.idlePollingInterval
    private var appActivationObserver: NSObjectProtocol?
    private var quickLookWindow: QuickLookWindowSnapshot?
    private var selectedURLs: [URL] = []
    private var displayedURL: URL?
    private var metadataGeneration: UInt64 = 0
    private var metadataCache: [String: CacheEntry] = [:]
    private var selectionProbeInFlight = false
    private var lastSelectionProbe = Date.distantPast
    private var lastPermissionProbe = Date.distantPast
    private var lastSelectionSignature = ""

    func start() {
        guard timer == nil else { return }
        setupApplicationActivationObserver()
        scheduleTimer(interval: Self.idlePollingInterval)
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        closeCurrentPreviewState()
        removeApplicationActivationObserver()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled

        if enabled {
            scheduleTimer(interval: Self.idlePollingInterval)
            tick()
        } else {
            closeCurrentPreviewState()
        }
        onStateChange?()
    }

    func requestAccessibilityPermission() {
        permissionGranted = AccessibilityPermission.request(prompt: true)
        onStateChange?()
    }

    private func tick() {
        guard isEnabled else { return }

        let now = Date()
        if now.timeIntervalSince(lastPermissionProbe) > 1 {
            lastPermissionProbe = now
            let latestPermission = AccessibilityPermission.isGranted
            if latestPermission != permissionGranted {
                permissionGranted = latestPermission
                logger.info("辅助功能权限状态：\(latestPermission ? "已授权" : "未授权", privacy: .public)")
                onStateChange?()
            }
        }

        guard permissionGranted else {
            closeCurrentPreviewState()
            return
        }

        // macOS 会在 Finder 失焦后短暂保留 Quick Look 窗口对象。
        // 非 Finder 前台时禁止重新显示，避免悬浮层隐藏后又被残留窗口触发。
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            if isQuickLookVisible || overlay.isVisible {
                closeCurrentPreviewState(clearSelection: false)
            }
            return
        }

        if now.timeIntervalSince(lastSelectionProbe) > 0.32 {
            probeFinderSelection()
        }

        guard let snapshot = windowScanner.visibleWindow() else {
            if isQuickLookVisible {
                closeCurrentPreviewState(clearSelection: false)
            }
            return
        }

        let wasVisible = isQuickLookVisible
        let previousWindow = quickLookWindow
        let previousWindowID = previousWindow?.windowID
        let windowSizeChanged = previousWindow?.frame.size != snapshot.frame.size
        quickLookWindow = snapshot
        isQuickLookVisible = true
        scheduleTimer(interval: Self.activeTrackingInterval)

        if previousWindowID != snapshot.windowID {
            metadataGeneration &+= 1
            displayedURL = nil
            currentFileName = nil
            overlay.hide()
            logger.info(
                "检测到 Quick Look：title=\(snapshot.title ?? "—", privacy: .public) frame=\(NSStringFromRect(snapshot.frame), privacy: .public)"
            )
        } else if windowSizeChanged, let displayedURL {
            overlay.reanchor(
                afterSystemFileName: displayedURL.lastPathComponent,
                anchor: windowScanner.overlayAnchor(
                    fileName: displayedURL.lastPathComponent,
                    in: snapshot
                ),
                within: snapshot.frame
            )
        } else {
            overlay.reposition(within: snapshot.frame)
        }

        resolveAndDisplayCurrentFile(in: snapshot)

        if !wasVisible {
            onStateChange?()
        }
    }

    private func probeFinderSelection() {
        guard !selectionProbeInFlight else { return }
        selectionProbeInFlight = true
        lastSelectionProbe = Date()

        selectionReader.selectedFileURLs { [weak self] urls in
            guard let self else { return }
            self.selectionProbeInFlight = false

            // Quick Look 出现时 Finder 偶尔暂时返回空选择，此时保留打开前缓存。
            if !urls.isEmpty || !self.isQuickLookVisible {
                self.selectedURLs = urls
            }

            let signature = self.selectedURLs.map(\.path).joined(separator: "|")
            if signature != self.lastSelectionSignature {
                self.lastSelectionSignature = signature
                let names = self.selectedURLs.map(\.lastPathComponent).joined(separator: ", ")
                self.logger.info(
                    "Finder 选择：count=\(self.selectedURLs.count) files=\(names, privacy: .public)"
                )
            }

            if let snapshot = self.quickLookWindow {
                self.resolveAndDisplayCurrentFile(in: snapshot)
            }
        }
    }

    private func resolveAndDisplayCurrentFile(in snapshot: QuickLookWindowSnapshot) {
        guard let url = chooseCurrentURL(windowTitle: snapshot.title),
              MediaMetadataReader.supports(url) else {
            if displayedURL != nil {
                metadataGeneration &+= 1
                displayedURL = nil
                currentFileName = nil
                overlay.hide()
                onStateChange?()
            }
            return
        }

        guard displayedURL?.standardizedFileURL != url.standardizedFileURL else {
            return
        }

        displayedURL = url
        currentFileName = url.lastPathComponent
        overlay.hide()
        metadataGeneration &+= 1
        let generation = metadataGeneration

        if let cachedMetadata = cachedMetadata(for: url) {
            show(metadata: cachedMetadata, for: url, generation: generation)
            return
        }

        let metadataTask = Task.detached(priority: .userInitiated) { [metadataReader] in
            await metadataReader.metadata(for: url)
        }

        Task { @MainActor [weak self] in
            let metadata = await metadataTask.value
            guard let self, self.metadataGeneration == generation else { return }
            guard let metadata else {
                self.logger.error("元数据读取失败：\(url.lastPathComponent, privacy: .public)")
                self.overlay.hide()
                return
            }

            self.logger.info(
                "元数据完成：\(MetadataFormatting.title(fileName: url.lastPathComponent, metadata: metadata), privacy: .public)"
            )
            self.store(metadata: metadata, for: url)
            self.show(metadata: metadata, for: url, generation: generation)
        }

        onStateChange?()
    }

    private func chooseCurrentURL(windowTitle: String?) -> URL? {
        guard !selectedURLs.isEmpty else { return nil }

        if let windowTitle {
            let normalizedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if let matched = selectedURLs.first(where: {
                $0.lastPathComponent.compare(
                    normalizedTitle,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }) {
                return matched
            }
        }

        if selectedURLs.count == 1 {
            return selectedURLs[0]
        }

        if let displayedURL,
           selectedURLs.contains(where: { $0.standardizedFileURL == displayedURL.standardizedFileURL }) {
            return displayedURL
        }

        return selectedURLs.first
    }

    private func show(
        metadata: MediaDisplayMetadata,
        for url: URL,
        generation: UInt64
    ) {
        guard metadataGeneration == generation,
              displayedURL?.standardizedFileURL == url.standardizedFileURL,
              let quickLookWindow else {
            return
        }

        overlay.show(
            text: MetadataFormatting.overlayText(metadata: metadata),
            afterSystemFileName: url.lastPathComponent,
            anchor: windowScanner.overlayAnchor(
                fileName: url.lastPathComponent,
                in: quickLookWindow
            ),
            within: quickLookWindow.frame
        )
    }

    private func cachedMetadata(for url: URL) -> MediaDisplayMetadata? {
        let key = url.standardizedFileURL.path
        guard let entry = metadataCache[key] else { return nil }
        let signature = fileSignature(for: url)

        guard entry.modificationDate == signature.modificationDate,
              entry.fileSize == signature.fileSize else {
            metadataCache.removeValue(forKey: key)
            return nil
        }

        return entry.metadata
    }

    private func store(metadata: MediaDisplayMetadata, for url: URL) {
        if metadataCache.count > 256 {
            metadataCache.removeAll(keepingCapacity: true)
        }

        let signature = fileSignature(for: url)
        metadataCache[url.standardizedFileURL.path] = CacheEntry(
            modificationDate: signature.modificationDate,
            fileSize: signature.fileSize,
            metadata: metadata
        )
    }

    private func fileSignature(for url: URL) -> (modificationDate: Date?, fileSize: Int64?) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (
            values?.contentModificationDate,
            values?.fileSize.map(Int64.init)
        )
    }

    private func closeCurrentPreviewState(clearSelection: Bool = false) {
        let hadVisibleState = isQuickLookVisible || displayedURL != nil || overlay.isVisible
        metadataGeneration &+= 1
        quickLookWindow = nil
        displayedURL = nil
        currentFileName = nil
        isQuickLookVisible = false
        windowScanner.reset()
        overlay.hide()
        if timer != nil {
            scheduleTimer(interval: Self.idlePollingInterval)
        }

        if clearSelection {
            selectedURLs = []
        }

        if hadVisibleState {
            logger.info("Quick Look 已关闭")
            onStateChange?()
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        if let timer, abs(timerInterval - interval) < 0.001, timer.isValid {
            return
        }

        timer?.invalidate()
        timerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setupApplicationActivationObserver() {
        guard appActivationObserver == nil else { return }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier != "com.apple.finder" else {
                return
            }

            // Finder 失去焦点时系统会隐藏 Quick Look；悬浮层必须同步立即消失。
            if self.isQuickLookVisible || self.overlay.isVisible {
                self.closeCurrentPreviewState(clearSelection: false)
            }
        }
    }

    private func removeApplicationActivationObserver() {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    deinit {
        timer?.invalidate()
        removeApplicationActivationObserver()
    }
}
