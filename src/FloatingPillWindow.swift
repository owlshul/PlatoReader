import Cocoa

public protocol FloatingPillDelegate: AnyObject {
    func didClickExplain(for selectionInfo: SelectionInfo)
}

public class FloatingPillWindow: NSPanel {
    public weak var pillDelegate: FloatingPillDelegate?
    private var currentSelection: SelectionInfo?
    private var button: NSButton!
    private var containerView: NSView!

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 95, height: 28),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = true

        setupView()
    }

    private func setupView() {
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 95, height: 28))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.layer?.borderWidth = 1.0
        containerView.layer?.borderColor = NSColor.separatorColor.cgColor

        button = NSButton(frame: NSRect(x: 0, y: 0, width: 95, height: 28))
        button.title = "Explain"
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = #selector(buttonClicked)
        button.focusRingType = .none

        containerView.addSubview(button)
        self.contentView = containerView
    }

    @objc private func buttonClicked() {
        self.orderOut(nil)
        if let sel = currentSelection {
            pillDelegate?.didClickExplain(for: sel)
        }
    }

    public func show(for selection: SelectionInfo) {
        self.currentSelection = selection

        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 900
        let cocoaX = selection.bounds.midX - (frame.width / 2)
        let cocoaY = mainScreenHeight - selection.bounds.minY + 6

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let clampedX = max(screen.minX + 10, min(cocoaX, screen.maxX - frame.width - 10))
        let clampedY = max(screen.minY + 10, min(cocoaY, screen.maxY - frame.height - 10))

        self.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        self.alphaValue = 0.0
        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.animator().alphaValue = 1.0
        }
    }

    public func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.currentSelection = nil
        })
    }
}
