import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate, FloatingPillDelegate, ExplanationPopoverDelegate, SettingsDelegate, HotkeyManagerDelegate, MultitouchManagerDelegate {
    private var statusItem: NSStatusItem!
    private var config: AppConfig!
    private var floatingPill: FloatingPillWindow!
    private var popoverWindow: ExplanationPopoverWindow!
    private var settingsController: SettingsWindowController?
    private var hotkeyManager: HotkeyManager!
    private var multitouchManager: MultitouchManager!

    private enum ExplanationMode {
        case pdfContext
        case universal
        case quickAsk
    }

    private var lastSelection: SelectionInfo?
    private var lastSelectionTime: TimeInterval = 0
    private var lastContextResult: PDFContextResult?

    // Dedicated active popover state (never cleared by didDeselect / handleAppSwitch)
    private var activeSelection: SelectionInfo?
    private var activeExplanationText: String = ""
    private var activePageContextText: String? = nil
    private var activeDoubtHistory: [(question: String, answer: String)] = []
    private var activeMode: ExplanationMode = .universal

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory app with floating panel support across all applications
        NSApp.setActivationPolicy(.accessory)

        // Setup standard macOS Edit menu so Cmd+C, Cmd+V, Cmd+A work in all text fields!
        setupMainMenu()

        // Load configuration
        config = AppConfig.load()

        // Setup windows
        floatingPill = FloatingPillWindow()
        floatingPill.pillDelegate = self

        popoverWindow = ExplanationPopoverWindow()
        popoverWindow.actionDelegate = self

        // Setup Menu Bar Item
        setupStatusBar()

        // Setup Hotkey and Event Monitors
        hotkeyManager = HotkeyManager()
        hotkeyManager.delegate = self
        hotkeyManager.updateShortcuts(universal: config.universalShortcut, context: config.contextShortcut, clipboard: config.clipboardShortcut)
        hotkeyManager.startMonitoring()

        // Setup Multitouch Trackpad Monitor for 3/4-Finger Tap
        multitouchManager = MultitouchManager()
        multitouchManager.delegate = self
        multitouchManager.fingerTapMode = config.fingerTapMode
        multitouchManager.isEnabled = (config.fingerTapMode != .disabled)
        multitouchManager.startMonitoring()

        // Listen for active app changes to prevent stale selection leakage across windows
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppSwitch),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Check Permissions and Updates on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.checkInitialStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UpdateManager.shared.checkInBackgroundIfNeeded(config: self.config)
        }
    }

    // MARK: - Standard Application & Edit Menu for Copy/Paste Support
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit PlatoReader", action: #selector(quitApp), keyEquivalent: "q")

        // Edit menu (Required by AppKit for ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z in NSTextField/NSTextView)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar Setup
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "book", accessibilityDescription: "PlatoReader") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "Plato"
            }
            button.toolTip = "PlatoReader"
        }
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        let menu = NSMenu()

        let askAnythingItem = NSMenuItem(title: "Ask a Question...", action: #selector(triggerAskManually), keyEquivalent: "")
        askAnythingItem.target = self
        menu.addItem(askAnythingItem)

        let explainItem = NSMenuItem(title: "Explain Selection", action: #selector(triggerExplainManually), keyEquivalent: "")
        explainItem.target = self
        menu.addItem(explainItem)

        let clipboardItem = NSMenuItem(title: "Explain Copied Text", action: #selector(triggerClipboardManually), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        menu.addItem(NSMenuItem.separator())

        // Clean AI Provider Switcher submenu
        let switchProviderItem = NSMenuItem(title: "AI Provider: \(config.selectedProvider.shortDisplayName)", action: nil, keyEquivalent: "")
        let providerSubmenu = NSMenu()
        for provider in AIProvider.allCases {
            let ready = config.isProviderReady(provider)
            let statusNote = ready ? "" : (provider.isCLIProvider ? " (Not found)" : " (Setup needed)")
            let item = NSMenuItem(title: "\(provider.shortDisplayName)\(statusNote)", action: #selector(switchProviderFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.state = (provider == config.selectedProvider) ? .on : .off
            providerSubmenu.addItem(item)
        }
        switchProviderItem.submenu = providerSubmenu
        menu.addItem(switchProviderItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit PlatoReader", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func checkInitialStatus() {
        if !AccessibilityHelper.isAccessibilityTrusted() {
            showPermissionAlert()
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "PlatoReader needs Accessibility access to detect selected text.\n\nEnable PlatoReader in System Settings → Privacy & Security → Accessibility.\n\nIf PlatoReader is already ticked from an older unsigned version, select it, click '−' to remove it, then add PlatoReader again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            if let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
            AccessibilityHelper.requestAccessibilityPermission()
        }
    }

    @objc private func checkForUpdatesClicked() {
        UpdateManager.shared.checkForUpdates(config: config, silentIfUpToDate: false)
    }

    @objc private func checkPermissionsDialog() {
        if AccessibilityHelper.isAccessibilityTrusted() {
            let alert = NSAlert()
            alert.messageText = "Permissions Active"
            alert.informativeText = "PlatoReader has full Accessibility access.\n• Highlight text in Preview: press ⌥ Space or click 💡 Explain.\n• Highlight text in any app/browser: tap 4 fingers or press ⌥⇧ Space."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            showPermissionAlert()
        }
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(config: config)
            settingsController?.delegate = self
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - HotkeyManagerDelegate
    func didDetectSelection(_ selection: SelectionInfo) {
        lastSelection = selection
        lastSelectionTime = Date().timeIntervalSince1970
        if config.enableFloatingPill {
            floatingPill.show(for: selection)
        }
    }

    func didDeselect() {
        floatingPill.hide()
        lastSelection = nil
    }

    @objc private func handleAppSwitch(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        floatingPill.hide()
        lastSelection = nil
    }

    func didTriggerHotkey() {
        triggerNormalExplain()
    }

    func didTriggerFourFingerHotkey() {
        triggerFourFingerExplain(fromGesture: false)
    }

    func didTriggerClipboardHotkey() {
        triggerClipboardExplain()
    }

    @objc private func triggerExplainManually() {
        triggerNormalExplain()
    }

    @objc private func triggerFourFingerManually() {
        triggerFourFingerExplain(fromGesture: false)
    }

    @objc private func triggerClipboardManually() {
        triggerClipboardExplain()
    }

    @objc private func triggerAskManually() {
        openBlankInputBox()
    }

    @objc private func switchProviderFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = AIProvider(rawValue: raw) else { return }
        config.selectedProvider = provider
        config.save()
        updateStatusMenu()
        if !config.isProviderReady(provider) {
            openSettings()
        }
    }

    // MARK: - MultitouchManagerDelegate
    func didDetectFourFingerTap() {
        guard config.enableFourFingerTap else { return }
        triggerFourFingerExplain(fromGesture: true)
    }

    private func currentMouseBounds() -> CGRect {
        let mouseLoc = NSEvent.mouseLocation
        if let primaryScreen = NSScreen.screens.first {
            let flippedY = primaryScreen.frame.height - mouseLoc.y
            return CGRect(x: mouseLoc.x - 20, y: flippedY - 10, width: 40, height: 20)
        }
        return CGRect(x: mouseLoc.x, y: mouseLoc.y, width: 40, height: 20)
    }

    private func openBlankInputBox(initialText: String? = nil) {
        floatingPill.hide()
        guard config.hasAnyConfiguredProvider() else {
            openSettings()
            return
        }
        let modelDisplay = "\(config.selectedProvider.shortDisplayName) • \(config.currentModel())"
        popoverWindow.showAskInput(
            modelName: modelDisplay,
            providerName: config.selectedProvider.shortDisplayName,
            near: currentMouseBounds(),
            initialText: initialText
        )
    }

    private func triggerNormalExplain() {
        floatingPill.hide()
        let now = Date().timeIntervalSince1970
        let freshSelection = (now - lastSelectionTime < 3.0) ? lastSelection : nil
        if let sel = AccessibilityHelper.shared.captureCurrentSelection(allowClipboardFallback: false) ?? freshSelection {
            if sel.appBundleId == "com.apple.Preview" {
                executeExplanation(for: sel)
            } else {
                executeFourFingerExplanation(for: sel)
            }
        } else {
            openBlankInputBox()
        }
    }

    private func triggerFourFingerExplain(fromGesture: Bool = false) {
        floatingPill.hide()
        let now = Date().timeIntervalSince1970
        let freshSelection = (now - lastSelectionTime < 3.0) ? lastSelection : nil

        if let sel = AccessibilityHelper.shared.captureCurrentSelection(allowClipboardFallback: true) {
            executeFourFingerExplanation(for: sel)
        } else if let fresh = freshSelection {
            executeFourFingerExplanation(for: fresh)
        } else if !fromGesture {
            openBlankInputBox()
        }
    }

    // MARK: - Clipboard Explain Flow (Recently Copied Sentence)
    private func triggerClipboardExplain() {
        floatingPill.hide()
        guard let copiedText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !copiedText.isEmpty else {
            openBlankInputBox()
            return
        }

        let selectionInfo = SelectionInfo(
            text: copiedText,
            bounds: currentMouseBounds(),
            documentPath: nil,
            windowTitle: nil,
            appName: "Copied Text",
            appBundleId: nil
        )

        executeFourFingerExplanation(for: selectionInfo)
    }

    // MARK: - FloatingPillDelegate
    func didClickExplain(for selectionInfo: SelectionInfo) {
        floatingPill.hide()
        if selectionInfo.appBundleId == "com.apple.Preview" {
            executeExplanation(for: selectionInfo)
        } else {
            executeFourFingerExplanation(for: selectionInfo)
        }
    }

    // MARK: - Explanation Execution Flow for Preview / PDF (Page Context Extraction)
    private func executeExplanation(for selection: SelectionInfo) {
        self.lastSelection = selection
        self.activeSelection = selection
        self.activeMode = .pdfContext
        self.activeDoubtHistory = []

        guard config.hasAnyConfiguredProvider() else {
            openSettings()
            return
        }

        let modelName = "\(config.selectedProvider.shortDisplayName) • \(config.currentModel())"
        let initialDoc = (selection.documentPath as NSString?)?.lastPathComponent ?? "Document"

        // 1. Show the window IMMEDIATELY on frame 0 (Zero delay feedback!)
        popoverWindow.showLoading(
            selection: selection.text,
            docName: initialDoc,
            pageDisplay: nil,
            modelName: modelName,
            near: selection.bounds,
            initialStatus: "Reading page context..."
        )

        // 2. Perform page context extraction and AI call asynchronously in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var docName: String? = initialDoc
            var pageDisplay: String? = nil
            var pageContextText: String? = nil

            if self.config.enablePageContext {
                DispatchQueue.main.async {
                    self.popoverWindow.updateProgress(status: "Finding page context...")
                }

                if let ctx = PDFContextHelper.shared.extractContext(
                    documentPath: selection.documentPath,
                    windowTitle: selection.windowTitle,
                    selection: selection.text
                ) {
                    docName = ctx.documentName
                    pageDisplay = ctx.pageDisplay
                    pageContextText = ctx.pageText
                }
            }

            DispatchQueue.main.async {
                self.popoverWindow.updateProgress(
                    status: "Explaining...",
                    docName: docName,
                    pageDisplay: pageDisplay
                )
            }

            // 3. Call AI Service (with automatic fallback failover)
            AIService.shared.explain(
                selection: selection.text,
                pageContext: pageContextText,
                config: self.config
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let res):
                    self.activeExplanationText = res.text
                    self.activePageContextText = pageContextText
                    var activeModelDisplay = modelName
                    if let fb = res.fallbackUsed {
                        activeModelDisplay = "\(fb) [Fallback]"
                    }
                    self.popoverWindow.showExplanation(
                        selection: selection.text,
                        docName: docName,
                        pageDisplay: pageDisplay,
                        modelName: activeModelDisplay,
                        pageContext: pageContextText,
                        explanationMarkdown: res.text
                    )
                case .failure(let error):
                    self.popoverWindow.showError(
                        selection: selection.text,
                        errorMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Four-Finger Universal Web Lookup (Strictly Highlighted Text Only)
    private func executeFourFingerExplanation(for selection: SelectionInfo) {
        self.lastSelection = selection
        self.activeSelection = selection
        self.activeMode = .universal
        self.activeDoubtHistory = []

        guard config.hasAnyConfiguredProvider() else {
            openSettings()
            return
        }

        let modelName = "\(config.selectedProvider.shortDisplayName) • \(config.currentModel())"
        let appDisplayName = selection.appName.isEmpty ? "Browser / Application" : selection.appName

        // 1. Show popover immediately (0ms feedback) near the mouse/selection
        popoverWindow.showLoading(
            selection: selection.text,
            docName: appDisplayName,
            pageDisplay: nil,
            modelName: modelName,
            near: selection.bounds,
            initialStatus: "Explaining..."
        )

        // 2. Perform universal explanation asynchronously in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            AIService.shared.explainFourFingerSelection(
                selection: selection.text,
                appName: selection.appName,
                config: self.config
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let res):
                    self.activeExplanationText = res.text
                    self.activePageContextText = nil // Strictly no window context stored
                    var activeModelDisplay = modelName
                    if let fb = res.fallbackUsed {
                        activeModelDisplay = "\(fb) [Fallback]"
                    }
                    self.popoverWindow.showExplanation(
                        selection: selection.text,
                        docName: appDisplayName,
                        pageDisplay: nil,
                        modelName: activeModelDisplay,
                        pageContext: nil,
                        explanationMarkdown: res.text
                    )
                case .failure(let error):
                    self.popoverWindow.showError(
                        selection: selection.text,
                        errorMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Direct Quick Ask (From Blank Input Box)
    private func executeQuickQuestion(_ question: String) {
        let sel = SelectionInfo(
            text: question,
            bounds: currentMouseBounds(),
            documentPath: nil,
            windowTitle: nil,
            appName: "Quick Ask",
            appBundleId: nil
        )
        self.activeSelection = sel
        self.activeMode = .quickAsk
        self.activeDoubtHistory = []

        guard config.hasAnyConfiguredProvider() else {
            openSettings()
            return
        }

        let modelName = "\(config.selectedProvider.shortDisplayName) • \(config.currentModel())"
        popoverWindow.showLoading(
            selection: question,
            docName: "Quick Ask",
            pageDisplay: nil,
            modelName: modelName,
            near: sel.bounds,
            initialStatus: "Thinking..."
        )

        AIService.shared.askDirectQuestion(
            question: question,
            config: self.config
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let res):
                self.activeExplanationText = res.text
                self.activePageContextText = nil
                var activeModelDisplay = modelName
                if let fb = res.fallbackUsed {
                    activeModelDisplay = "\(fb) [Fallback]"
                }
                self.popoverWindow.showExplanation(
                    selection: question,
                    docName: "Quick Ask",
                    pageDisplay: nil,
                    modelName: activeModelDisplay,
                    pageContext: nil,
                    explanationMarkdown: res.text
                )
            case .failure(let error):
                self.popoverWindow.showError(
                    selection: question,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    // MARK: - ExplanationPopoverDelegate
    func didRequestRegenerate(simpler: Bool) {
        guard let sel = activeSelection ?? lastSelection else { return }
        switch activeMode {
        case .pdfContext:
            let originalPreset = config.activePresetId
            config.activePresetId = simpler ? "plain_english" : "concise_context"
            executeExplanation(for: sel)
            config.activePresetId = originalPreset
        case .universal:
            executeFourFingerExplanation(for: sel)
        case .quickAsk:
            executeQuickQuestion(sel.text)
        }
    }

    func didSubmitQuickQuestion(questionText: String) {
        executeQuickQuestion(questionText)
    }

    func didSubmitDoubt(doubtId: String, doubtText: String) {
        guard let sel = activeSelection ?? lastSelection else {
            popoverWindow.appendDoubtAnswer(
                doubtId: doubtId,
                replyMarkdown: "⚠️ No active passage context found. Please trigger an explanation first and ask again."
            )
            return
        }
        let docName = (sel.documentPath as NSString?)?.lastPathComponent ?? sel.appName
        AIService.shared.answerDoubt(
            selection: sel.text,
            docName: docName,
            pageContext: activePageContextText,
            previousExplanation: activeExplanationText,
            doubtHistory: activeDoubtHistory,
            doubt: doubtText,
            config: self.config
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let answer):
                self.activeDoubtHistory.append((question: doubtText, answer: answer))
                self.popoverWindow.appendDoubtAnswer(doubtId: doubtId, replyMarkdown: answer)
            case .failure(let error):
                self.popoverWindow.appendDoubtAnswer(
                    doubtId: doubtId,
                    replyMarkdown: "⚠️ Could not answer doubt: " + error.localizedDescription
                )
            }
        }
    }

    func didRequestOpenSettings() {
        openSettings()
    }

    // MARK: - SettingsDelegate
    func didUpdateConfig(_ updatedConfig: AppConfig) {
        self.config = updatedConfig
        multitouchManager.fingerTapMode = updatedConfig.fingerTapMode
        multitouchManager.isEnabled = (updatedConfig.fingerTapMode != .disabled)
        hotkeyManager.updateShortcuts(
            universal: updatedConfig.universalShortcut,
            context: updatedConfig.contextShortcut,
            clipboard: updatedConfig.clipboardShortcut
        )
        updateStatusMenu()
    }
}

// MARK: - Main Application Run Loop
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
