import AppKit
import LookSizeCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = QuickLookMonitor()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var permissionItem: NSMenuItem!
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

        let requestPermissionItem = NSMenuItem(
            title: "请求辅助功能权限",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        requestPermissionItem.target = self
        menu.addItem(requestPermissionItem)

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

        statusItem.button?.contentTintColor = monitor.permissionGranted ? nil : .systemOrange
        statusItem.button?.toolTip = monitor.permissionGranted
            ? "LookSize 正在运行"
            : "LookSize 需要辅助功能权限"
    }

    @objc private func toggleMonitoring() {
        monitor.setEnabled(!monitor.isEnabled)
        refreshStatus()
    }

    @objc private func requestAccessibilityPermission() {
        monitor.requestAccessibilityPermission()
        if !AccessibilityPermission.isGranted {
            openAccessibilitySettings()
        }
        refreshStatus()
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
        alert.messageText = "LookSize 0.1.5"
        alert.informativeText = "在 Finder 的 Quick Look 文件名后显示图片分辨率，以及视频分辨率和帧率。\n\n这是视觉悬浮文字，不会修改 Finder、Quick Look 或原文件。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
