import Cocoa
import Carbon

public protocol HotkeyManagerDelegate: AnyObject {
    func didTriggerHotkey()
    func didTriggerFourFingerHotkey()
    func didTriggerClipboardHotkey()
    func didDetectSelection(_ selection: SelectionInfo)
    func didDeselect()
}

public class HotkeyManager {
    public weak var delegate: HotkeyManagerDelegate?
    private var globalMouseDownMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?

    private var selectionCheckTimer: Timer?

    private var hotKeyRefNormal: EventHotKeyRef?
    private var hotKeyRefFourFinger: EventHotKeyRef?
    private var hotKeyRefClipboard: EventHotKeyRef?
    private var isCarbonHandlerInstalled: Bool = false

    public var universalShortcut: ShortcutConfig = .defaultUniversal
    public var contextShortcut: ShortcutConfig = .defaultContext
    public var clipboardShortcut: ShortcutConfig = .defaultClipboard

    public init() {}

    public func updateShortcuts(universal: ShortcutConfig, context: ShortcutConfig, clipboard: ShortcutConfig = .defaultClipboard) {
        self.universalShortcut = universal
        self.contextShortcut = context
        self.clipboardShortcut = clipboard
        reregisterCarbonHotkeys()
    }

    public func startMonitoring() {
        stopMonitoring()

        // 1. Monitor Mouse Down (dismiss pill when clicking away)
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.delegate?.didDeselect()
        }

        // 2. Monitor Mouse Up (detect if user highlighted text in Preview or elsewhere)
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self = self else { return }
            self.selectionCheckTimer?.invalidate()
            // Slight debounce so the OS updates the selection attributes
            self.selectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                if let selection = AccessibilityHelper.shared.captureCurrentSelection(allowClipboardFallback: false) {
                    let clean = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.count >= 2 {
                        self.delegate?.didDetectSelection(selection)
                        return
                    }
                }
                self.delegate?.didDeselect()
            }
        }

        // 3. Monitor Key Down for Hotkeys
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // consume event
            }
            return event
        }

        registerCarbonHotkeys()
    }

    public func stopMonitoring() {
        if let m = globalMouseDownMonitor { NSEvent.removeMonitor(m); globalMouseDownMonitor = nil }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m); globalMouseUpMonitor = nil }
        if let m = globalKeyDownMonitor { NSEvent.removeMonitor(m); globalKeyDownMonitor = nil }
        if let m = localKeyDownMonitor { NSEvent.removeMonitor(m); localKeyDownMonitor = nil }
        selectionCheckTimer?.invalidate()

        if let ref = hotKeyRefNormal {
            UnregisterEventHotKey(ref)
            hotKeyRefNormal = nil
        }
        if let ref = hotKeyRefFourFinger {
            UnregisterEventHotKey(ref)
            hotKeyRefFourFinger = nil
        }
        if let ref = hotKeyRefClipboard {
            UnregisterEventHotKey(ref)
            hotKeyRefClipboard = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // 1. Universal (3/4-Finger / Web) Explain Shortcut
        if universalShortcut.matchesNSEvent(event) {
            DispatchQueue.main.async {
                self.delegate?.didTriggerFourFingerHotkey()
            }
            return true
        }

        // 2. PDF Context Explain Shortcut
        if contextShortcut.matchesNSEvent(event) {
            DispatchQueue.main.async {
                self.delegate?.didTriggerHotkey()
            }
            return true
        }

        // 3. Clipboard Explain Shortcut
        if clipboardShortcut.matchesNSEvent(event) {
            DispatchQueue.main.async {
                self.delegate?.didTriggerClipboardHotkey()
            }
            return true
        }

        return false
    }

    // Carbon Event Hotkeys for system-wide triggers
    public func reregisterCarbonHotkeys() {
        if let ref = hotKeyRefNormal {
            UnregisterEventHotKey(ref)
            hotKeyRefNormal = nil
        }
        if let ref = hotKeyRefFourFinger {
            UnregisterEventHotKey(ref)
            hotKeyRefFourFinger = nil
        }
        if let ref = hotKeyRefClipboard {
            UnregisterEventHotKey(ref)
            hotKeyRefClipboard = nil
        }

        // ID 1: Context Shortcut
        var hotKeyNormal = EventHotKeyID()
        hotKeyNormal.signature = OSType(0x504C544F) // 'PLTO'
        hotKeyNormal.id = 1
        RegisterEventHotKey(contextShortcut.keyCode, contextShortcut.modifiers, hotKeyNormal, GetApplicationEventTarget(), 0, &hotKeyRefNormal)

        // ID 2: Universal Shortcut
        var hotKeyFour = EventHotKeyID()
        hotKeyFour.signature = OSType(0x504C544F) // 'PLTO'
        hotKeyFour.id = 2
        RegisterEventHotKey(universalShortcut.keyCode, universalShortcut.modifiers, hotKeyFour, GetApplicationEventTarget(), 0, &hotKeyRefFourFinger)

        // ID 3: Clipboard Shortcut
        var hotKeyClip = EventHotKeyID()
        hotKeyClip.signature = OSType(0x504C544F) // 'PLTO'
        hotKeyClip.id = 3
        RegisterEventHotKey(clipboardShortcut.keyCode, clipboardShortcut.modifiers, hotKeyClip, GetApplicationEventTarget(), 0, &hotKeyRefClipboard)
    }

    private func registerCarbonHotkeys() {
        if !isCarbonHandlerInstalled {
            var eventType = EventTypeSpec()
            eventType.eventClass = OSType(kEventClassKeyboard)
            eventType.eventKind = OSType(kEventHotKeyPressed)

            InstallEventHandler(GetApplicationEventTarget(), { (handlerCallRef, eventRef, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hkID = EventHotKeyID()
                let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)

                if status == noErr {
                    DispatchQueue.main.async {
                        if hkID.id == 1 {
                            manager.delegate?.didTriggerHotkey()
                        } else if hkID.id == 2 {
                            manager.delegate?.didTriggerFourFingerHotkey()
                        } else if hkID.id == 3 {
                            manager.delegate?.didTriggerClipboardHotkey()
                        }
                    }
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
            isCarbonHandlerInstalled = true
        }

        reregisterCarbonHotkeys()
    }

    deinit {
        stopMonitoring()
    }
}
