import Cocoa
import Carbon

public protocol HotkeyManagerDelegate: AnyObject {
    func didTriggerHotkey()
    func didTriggerFourFingerHotkey()
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

    public init() {}

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
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let isSpace = (event.keyCode == 49)
        let hasOption = event.modifierFlags.contains(.option)
        let hasCmd = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)

        // 1. Option + Shift + Space: Universal 4-Finger Internet Explain
        if isSpace && hasOption && hasShift && !hasCmd {
            DispatchQueue.main.async {
                self.delegate?.didTriggerFourFingerHotkey()
            }
            return true
        }

        // 2. Option + Space OR Command + Shift + E (keyCode 14): Context Explain
        if (isSpace && hasOption && !hasCmd && !hasShift) || (event.keyCode == 14 && hasCmd && hasShift) {
            DispatchQueue.main.async {
                self.delegate?.didTriggerHotkey()
            }
            return true
        }

        return false
    }

    // Carbon Event Hotkeys for system-wide triggers
    private func registerCarbonHotkeys() {
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
                    }
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        // ID 1: Option + Space
        var hotKeyNormal = EventHotKeyID()
        hotKeyNormal.signature = OSType(0x504C544F) // 'PLTO'
        hotKeyNormal.id = 1
        RegisterEventHotKey(49, UInt32(optionKey), hotKeyNormal, GetApplicationEventTarget(), 0, &hotKeyRefNormal)

        // ID 2: Option + Shift + Space
        var hotKeyFour = EventHotKeyID()
        hotKeyFour.signature = OSType(0x504C544F) // 'PLTO'
        hotKeyFour.id = 2
        RegisterEventHotKey(49, UInt32(optionKey | shiftKey), hotKeyFour, GetApplicationEventTarget(), 0, &hotKeyRefFourFinger)
    }

    deinit {
        stopMonitoring()
    }
}
