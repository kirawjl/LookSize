import AppKit
import LookSizeCore

final class TitleOverlayController {
    private enum Placement {
        case titleBar
        case previewContent
    }

    private let panel: PassthroughPanel
    private let contentView: NSView
    private let label: NSTextField
    private let systemTitleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private var anchorOffset = CGPoint.zero
    private var placement: Placement = .titleBar
    private(set) var isVisible = false

    init() {
        panel = PassthroughPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]

        contentView = NSView(frame: .zero)
        contentView.wantsLayer = true

        label = NSTextField(labelWithString: "")
        label.font = systemTitleFont
        label.alignment = .left
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.drawsBackground = false
        label.isBezeled = false
        label.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        panel.contentView = contentView
        panel.setAccessibilityElement(false)
        applyTitleBarAppearance()
    }

    func show(
        text: String,
        afterSystemFileName fileName: String,
        anchor: QuickLookOverlayAnchor?,
        within quickLookFrame: CGRect
    ) {
        label.stringValue = text
        updateAnchor(
            afterSystemFileName: fileName,
            anchor: anchor,
            within: quickLookFrame
        )
        updateFrame(within: quickLookFrame)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func reanchor(
        afterSystemFileName fileName: String,
        anchor: QuickLookOverlayAnchor?,
        within quickLookFrame: CGRect
    ) {
        guard isVisible else { return }
        updateAnchor(
            afterSystemFileName: fileName,
            anchor: anchor,
            within: quickLookFrame
        )
        updateFrame(within: quickLookFrame)
    }

    func reposition(within quickLookFrame: CGRect) {
        guard isVisible else { return }
        updateFrame(within: quickLookFrame)
    }

    func hide() {
        guard isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
    }

    private func updateAnchor(
        afterSystemFileName fileName: String,
        anchor: QuickLookOverlayAnchor?,
        within quickLookFrame: CGRect
    ) {
        let textWidth = measuredTextWidth
        if let anchor,
           anchor.fileNameFrame.maxX + 8 + textWidth <= anchor.titleRightBoundary - 8 {
            placement = .titleBar
            applyTitleBarAppearance()
            anchorOffset = CGPoint(
                x: anchor.fileNameFrame.maxX - quickLookFrame.minX + 8,
                y: anchor.fileNameFrame.midY - quickLookFrame.minY
            )
            return
        }

        if let contentFrame = anchor?.contentFrame {
            placement = .previewContent
            applyPreviewContentAppearance()
            anchorOffset = CGPoint(
                x: contentFrame.minX - quickLookFrame.minX + 10,
                y: contentFrame.maxY - quickLookFrame.minY - 10
            )
            return
        }

        // AX 偶尔会短暂缺少文件名元素，使用系统标题的居中布局作为兜底。
        placement = .titleBar
        applyTitleBarAppearance()
        let estimatedFileNameWidth = ceil(
            (fileName as NSString).size(
                withAttributes: [.font: systemTitleFont]
            ).width
        )
        anchorOffset = CGPoint(
            x: quickLookFrame.width / 2 + estimatedFileNameWidth / 2 + 8,
            y: quickLookFrame.height - 18
        )
    }

    private func updateFrame(within quickLookFrame: CGRect) {
        let horizontalPadding: CGFloat = placement == .previewContent ? 8 : 0
        let verticalPadding: CGFloat = placement == .previewContent ? 4 : 0
        let width = max(1, measuredTextWidth + horizontalPadding * 2)
        let textHeight = max(18, ceil(measuredTextSize.height))
        let height = textHeight + verticalPadding * 2

        let origin: CGPoint
        switch placement {
        case .titleBar:
            origin = CGPoint(
                x: quickLookFrame.minX + anchorOffset.x,
                y: quickLookFrame.minY + anchorOffset.y - height / 2
            )
        case .previewContent:
            origin = CGPoint(
                x: quickLookFrame.minX + anchorOffset.x,
                y: quickLookFrame.minY + anchorOffset.y - height
            )
        }

        panel.setFrame(
            CGRect(origin: origin, size: CGSize(width: width, height: height)),
            display: true
        )
    }

    private var measuredTextSize: CGSize {
        (label.stringValue as NSString).size(
            withAttributes: [.font: label.font as Any]
        )
    }

    private var measuredTextWidth: CGFloat {
        max(1, ceil(measuredTextSize.width) + 1)
    }

    private func applyTitleBarAppearance() {
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.cornerRadius = 0
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        panel.hasShadow = false
    }

    private func applyPreviewContentAppearance() {
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        contentView.layer?.cornerRadius = 5
        label.textColor = .white
        label.alignment = .center
        panel.hasShadow = false
    }
}

private final class PassthroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
