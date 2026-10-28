import Cocoa
import ApplicationServices

public struct SelectionInfo {
    public let text: String
    public let bounds: CGRect
    public let documentPath: String?
    public let windowTitle: String?
    public let appName: String
    public let appBundleId: String?
}

public class AccessibilityHelper {
    public static let shared = AccessibilityHelper()

    private init() {}

    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Captures the highlighted text selection in the active application.
    /// Strictly extracts only what the user highlighted with their cursor.
    /// Does NOT access background window contents, tabs, or DOM trees.
    public func captureCurrentSelection(allowClipboardFallback: Bool = true) -> SelectionInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = frontApp.localizedName ?? "Application"
        let bundleId = frontApp.bundleIdentifier

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // 1. Try to get focused element and its selected text directly via Accessibility APIs
        var focusedObj: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedObj)

        var selectedText: String? = nil
        var textBounds = CGRect.zero
        var focusedAX: AXUIElement? = nil

        if focusResult == .success, let focusedElement = focusedObj {
            let el = focusedElement as! AXUIElement
            focusedAX = el

            var selectedTextObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &selectedTextObj) == .success,
               let rawText = selectedTextObj as? String,
               !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedText = rawText
            }

            // Extract bounds if text is found
            if selectedText != nil {
                var selectedRangeObj: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &selectedRangeObj) == .success,
                   let rangeVal = selectedRangeObj {
                    var boundsObj: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeVal, &boundsObj) == .success,
                       let boundsVal = boundsObj {
                        var cgRect = CGRect.zero
                        if AXValueGetValue(boundsVal as! AXValue, .cgRect, &cgRect) {
                            textBounds = cgRect
                        }
                    }
                }
            }
        }

        // 2. If focused element did not expose selected text (e.g. some web views), check focused window
        if selectedText == nil {
            var winObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winObj) == .success,
               let winElement = winObj {
                var winSelectedObj: CFTypeRef?
                if AXUIElementCopyAttributeValue(winElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &winSelectedObj) == .success,
                   let winText = winSelectedObj as? String,
                   !winText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedText = winText
                }
            }
        }

        // 3. Resilient Clipboard Fallback for browsers & custom controls
        // If native Accessibility didn't return text and clipboard fallback is permitted,
        // copy the highlighted portion only.
        if (selectedText == nil || selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) && allowClipboardFallback {
            if let copied = performSimulatedCopy() {
                selectedText = copied
            }
        }

        guard let finalText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !finalText.isEmpty else {
            return nil
        }

        // 4. Calculate bounds (fall back to mouse cursor if element bounds unavailable)
        var bounds = textBounds
        if bounds == .zero || bounds.width <= 0 || bounds.height <= 0 {
            let mouseLoc = NSEvent.mouseLocation
            if let primaryScreen = NSScreen.screens.first {
                let flippedY = primaryScreen.frame.height - mouseLoc.y
                bounds = CGRect(x: mouseLoc.x - 20, y: flippedY - 10, width: 40, height: 20)
            } else {
                bounds = CGRect(x: mouseLoc.x, y: mouseLoc.y, width: 40, height: 20)
            }
        }

        // 5. Get Window Title and Document URL (if available)
        var documentPath: String? = nil
        var windowTitle: String? = nil

        if let ax = focusedAX {
            var windowObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(ax, kAXWindowAttribute as CFString, &windowObj) == .success,
               let winElement = windowObj {
                var winDocObj: CFTypeRef?
                if AXUIElementCopyAttributeValue(winElement as! AXUIElement, kAXDocumentAttribute as CFString, &winDocObj) == .success,
                   let winDocStr = winDocObj as? String {
                    documentPath = winDocStr
                }
                var titleObj: CFTypeRef?
                if AXUIElementCopyAttributeValue(winElement as! AXUIElement, kAXTitleAttribute as CFString, &titleObj) == .success,
                   let titleStr = titleObj as? String {
                    windowTitle = titleStr
                }
            }
        }

        // If window title is still nil, try frontmost window of app
        if windowTitle == nil || documentPath == nil {
            var windowsObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsObj) == .success,
               let wins = windowsObj as? [AXUIElement], let frontWin = wins.first {
                if windowTitle == nil {
                    var titleObj: CFTypeRef?
                    if AXUIElementCopyAttributeValue(frontWin, kAXTitleAttribute as CFString, &titleObj) == .success,
                       let titleStr = titleObj as? String {
                        windowTitle = titleStr
                    }
                }
                if documentPath == nil {
                    var docObj: CFTypeRef?
                    if AXUIElementCopyAttributeValue(frontWin, kAXDocumentAttribute as CFString, &docObj) == .success,
                       let docStr = docObj as? String {
                        documentPath = docStr
                    }
                }
            }
        }

        // Clean file:// prefix if present
        if let doc = documentPath, doc.hasPrefix("file://") {
            if let url = URL(string: doc) {
                documentPath = url.path
            }
        }

        return SelectionInfo(
            text: finalText,
            bounds: bounds,
            documentPath: documentPath,
            windowTitle: windowTitle,
            appName: appName,
            appBundleId: bundleId
        )
    }

    /// Performs a non-destructive Command+C to capture whatever is highlighted in any app (Chrome, Arc, Safari, Firefox, Notes, etc.)
    private func performSimulatedCopy() -> String? {
        let pb = NSPasteboard.general
        let initialChangeCount = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 0x08 // virtual key code for 'c'
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false) else {
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Poll for pasteboard change (up to 80ms)
        for _ in 0..<8 {
            usleep(10000) // 10ms
            if pb.changeCount != initialChangeCount {
                if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    return str
                }
            }
        }
        return nil
    }
}
