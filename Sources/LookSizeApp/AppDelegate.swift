import AppKit
import LookSizeCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = QuickLookMonitor()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var permissionItem: NSMenuItem!
    private var automationPermissionItem: NSMenuItem!
    private var monitorStateItem: NSMenuItem!
    private var currentFileItem: NSMenuItem!
    private var toggleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        monitor.onStateChange = { [weak self] in
            self?.refreshStatus()
        }
        monitor.start()

        if !AccessibilityPermission.isGranted {
            _ = AccessibilityPermission.request(prompt: true)
        }
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "ruler",
                accessibilityDescription: "LookSize"
            )
            button.image?.isTemplate = true
            button.toolTip = "LookSize"
        }

        menu = NSMenu()
        menu.delegate = self

        permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        automationPermissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        automationPermissionItem.isEnabled = false
        menu.addItem(automationPermissionItem)

        monitorStateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        monitorStateItem.isEnabled = false
        menu.addItem(monitorStateItem)

        currentFileItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        currentFileItem.isEnabled = false
        menu.addItem(currentFileItem)

        menu.addItem(.separator())

        toggleItem = NSMenuItem(
            title: "",
            action: #selector(toggleMonitoring),
            keyEquivalent: "e"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let checkPermissionsItem = NSMenuItem(
            title: "授权诊断与修复…",
            action: #selector(showPermissionAssistant),
            keyEquivalent: ""
        )
        checkPermissionsItem.target = self
        menu.addItem(checkPermissionsItem)

        let requestPermissionItem = NSMenuItem(
            title: "请求辅助功能权限",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        requestPermissionItem.target = self
        menu.addItem(requestPermissionItem)

        let requestAutomationPermissionItem = NSMenuItem(
            title: "请求 Finder 自动化权限",
            action: #selector(requestFinderAutomationPermission),
            keyEquivalent: ""
        )
        requestAutomationPermissionItem.target = self
        menu.addItem(requestAutomationPermissionItem)

        let openSettingsItem = NSMenuItem(
            title: "打开辅助功能设置…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        let openAutomationSettingsItem = NSMenuItem(
            title: "打开自动化设置…",
            action: #selector(openAutomationSettings),
            keyEquivalent: ""
        )
        openAutomationSettingsItem.target = self
        menu.addItem(openAutomationSettingsItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "关于 LookSize",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "退出 LookSize",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshStatus() {
        permissionItem.title = monitor.permissionGranted
            ? "辅助功能权限：已授权"
            : "辅助功能权限：未授权"
        automationPermissionItem.title = automationPermissionTitle

        if !monitor.isEnabled {
            monitorStateItem.title = "监控状态：已暂停"
        } else if monitor.isQuickLookVisible {
            monitorStateItem.title = "监控状态：检测到 Quick Look"
        } else {
            monitorStateItem.title = "监控状态：运行中"
        }

        currentFileItem.title = monitor.currentFileName.map {
            "当前文件：\($0)"
        } ?? "当前文件：—"

        toggleItem.title = monitor.isEnabled ? "暂停监控" : "恢复监控"
        toggleItem.state = monitor.isEnabled ? .on : .off

        let allPermissionsGranted = monitor.permissionGranted
            && monitor.automationPermissionStatus?.isAuthorized == true
        statusItem.button?.contentTintColor = allPermissionsGranted ? nil : .systemOrange
        statusItem.button?.toolTip = allPermissionsGranted
            ? "LookSize 正在运行"
            : "LookSize 需要完成授权"
    }

    @objc private func toggleMonitoring() {
        monitor.setEnabled(!monitor.isEnabled)
        refreshStatus()
    }

    private var automationPermissionTitle: String {
        switch monitor.automationPermissionStatus {
        case .authorized:
            return "Finder 自动化权限：已授权"
        case .denied:
            return "Finder 自动化权限：未授权"
        case .notDetermined:
            return "Finder 自动化权限：未请求"
        case .targetNotRunning:
            return "Finder 自动化权限：Finder 未运行"
        case .unavailable(let status):
            return "Finder 自动化权限：检测失败（\(status)）"
        case nil:
            return "Finder 自动化权限：检测中"
        }
    }

    @objc private func requestAccessibilityPermission() {
        monitor.requestAccessibilityPermission()
        if !AccessibilityPermission.isGranted {
            openAccessibilitySettings()
        }
        refreshStatus()
    }

    @objc private func requestFinderAutomationPermission() {
        NSApp.activate(ignoringOtherApps: true)
        monitor.requestFinderAutomationPermission { [weak self] status in
            self?.refreshStatus()
            if status == .denied {
                self?.openAutomationSettings()
            }
        }
    }

    @objc private func showPermissionAssistant() {
        monitor.refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "LookSize 授权诊断"
        alert.informativeText = permissionDiagnosticText
        alert.addButton(withTitle: "请求缺失授权")
        alert.addButton(withTitle: "打开相关设置")
        alert.addButton(withTitle: "关闭")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            requestMissingPermissions()
        case .alertSecondButtonReturn:
            if !monitor.permissionGranted {
                openAccessibilitySettings()
            } else {
                openAutomationSettings()
            }
        default:
            break
        }
    }

    private var permissionDiagnosticText: String {
        let accessibility = monitor.permissionGranted ? "已授权" : "未授权"
        let automation = automationPermissionTitle
            .replacingOccurrences(of: "Finder 自动化权限：", with: "")
        let runningPath = Bundle.main.bundleURL.path

        return """
        正常显示 Quick Look 信息需要：
        • 辅助功能：\(accessibility)
        • Finder 自动化：\(automation)

        文件夹访问会在读取桌面、文稿、下载、网络磁盘或移动磁盘中的媒体时由系统按需询问。LookSize 不需要屏幕录制权限。

        当前程序：\(runningPath)

        如果更新后系统设置中已有 LookSize，但这里仍显示未授权，请删除旧条目，再重新打开 /Applications/LookSize.app 并授权。免费版本使用临时签名，替换程序后 macOS 可能把新版本识别为不同程序。
        """
    }

    private func requestMissingPermissions() {
        NSApp.activate(ignoringOtherApps: true)

        let requestAccessibility = { [weak self] in
            guard let self, !AccessibilityPermission.isGranted else { return }
            self.monitor.requestAccessibilityPermission()
            self.openAccessibilitySettings()
            self.refreshStatus()
        }

        if monitor.automationPermissionStatus?.isAuthorized == true {
            requestAccessibility()
            return
        }

        monitor.requestFinderAutomationPermission { [weak self] status in
            self?.refreshStatus()
            if status == .denied {
                self?.openAutomationSettings()
            } else {
                requestAccessibility()
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        alert.messageText = "LookSize \(version)"
        alert.informativeText = "在 Finder 的 Quick Look 文件名后显示图片分辨率，以及视频分辨率和帧率。\n\n这是视觉悬浮文字，不会修改 Finder、Quick Look 或原文件。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
