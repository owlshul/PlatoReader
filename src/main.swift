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

    private var lastSelection: SelectionInfo?
    private var lastContextResult: PDFContextResult?
    private var lastExplanationText: String = ""
    private var lastPageContextText: String? = nil

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
        hotkeyManager.startMonitoring()

        // Setup Multitouch Trackpad Monitor for 4-Finger Tap
        multitouchManager = MultitouchManager()
        multitouchManager.delegate = self
        multitouchManager.isEnabled = config.enableFourFingerTap
        multitouchManager.startMonitoring()

        // Check Permissions and First Run
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.checkInitialStatus()
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
            button.title = "📖"
            button.toolTip = "Reading Companion • AI Explanation for Preview & Web"
        }
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "📖 Reading Companion", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let modelTitle = "Model: \(config.currentModel())"
        let modelItem = NSMenuItem(title: modelTitle, action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())

        let explainItem = NSMenuItem(title: "Explain Selection (PDF Context)", action: #selector(triggerExplainManually), keyEquivalent: " ")
        explainItem.keyEquivalentModifierMask = .option
        explainItem.target = self
        menu.addItem(explainItem)

        let fourFingerItem = NSMenuItem(title: "Explain Selection (4-Finger Universal)", action: #selector(triggerFourFingerManually), keyEquivalent: "$")
        fourFingerItem.keyEquivalentModifierMask = [.option, .shift]
        fourFingerItem.target = self
        menu.addItem(fourFingerItem)

        let settingsItem = NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permItem = NSMenuItem(title: "Check Accessibility Permissions...", action: #selector(checkPermissionsDialog), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
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
        alert.informativeText = "PlatoReader needs Accessibility access to detect text you select in Preview, browsers, and other apps.\n\nPlease enable PlatoReader in System Settings → Privacy & Security → Accessibility."
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
        if config.enableFloatingPill {
            floatingPill.show(for: selection)
        }
    }

    func didDeselect() {
        floatingPill.hide()
    }

    func didTriggerHotkey() {
        triggerNormalExplain()
    }

    func didTriggerFourFingerHotkey() {
        triggerFourFingerExplain()
    }

    @objc private func triggerExplainManually() {
        triggerNormalExplain()
    }

    @objc private func triggerFourFingerManually() {
        triggerFourFingerExplain()
    }

    // MARK: - MultitouchManagerDelegate
    func didDetectFourFingerTap() {
        guard config.enableFourFingerTap else { return }
        triggerFourFingerExplain()
    }

    private func triggerNormalExplain() {
        floatingPill.hide()
        if let sel = AccessibilityHelper.shared.captureCurrentSelection(allowClipboardFallback: false) ?? lastSelection {
            if sel.appBundleId == "com.apple.Preview" {
                executeExplanation(for: sel)
            } else {
                executeFourFingerExplanation(for: sel)
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "No Text Highlighted"
            alert.informativeText = "Highlight a sentence in Preview or any document, then press ⌥ Space."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func triggerFourFingerExplain() {
        floatingPill.hide()
        if let sel = AccessibilityHelper.shared.captureCurrentSelection(allowClipboardFallback: true) {
            executeFourFingerExplanation(for: sel)
        } else if let last = lastSelection {
            executeFourFingerExplanation(for: last)
        } else {
            let alert = NSAlert()
            alert.messageText = "No Text Highlighted"
            alert.informativeText = "Highlight any word or sentence in Safari, Chrome, or any application, then tap 4 fingers or press ⌥⇧ Space."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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

        let key = config.currentKey().isEmpty ? (config.fallbackKey() ?? "") : config.currentKey()
        guard !key.isEmpty else {
            openSettings()
            return
        }

        let modelName = config.currentModel()
        let initialDoc = (selection.documentPath as NSString?)?.lastPathComponent ?? "Document"

        // 1. Show the window IMMEDIATELY on frame 0 (Zero delay feedback!)
        popoverWindow.showLoading(
            selection: selection.text,
            docName: initialDoc,
            pageDisplay: nil,
            modelName: modelName,
            near: selection.bounds,
            initialStatus: "🔍 Reading page context..."
        )

        // 2. Perform page context extraction and AI call asynchronously in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var docName: String? = initialDoc
            var pageDisplay: String? = nil
            var pageContextText: String? = nil

            if self.config.enablePageContext {
                DispatchQueue.main.async {
                    self.popoverWindow.updateProgress(status: "📄 Locating page & reading context...")
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
                    status: "⚡ Explaining with \(modelName)...",
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
                    self.lastExplanationText = res.text
                    self.lastPageContextText = pageContextText
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

        let key = config.currentKey().isEmpty ? (config.fallbackKey() ?? "") : config.currentKey()
        guard !key.isEmpty else {
            openSettings()
            return
        }

        let modelName = config.currentModel()
        let appDisplayName = selection.appName.isEmpty ? "Browser / Application" : selection.appName

        // 1. Show popover immediately (0ms feedback) near the mouse/selection
        popoverWindow.showLoading(
            selection: selection.text,
            docName: appDisplayName,
            pageDisplay: "🖐️ 4-Finger Meaning",
            modelName: modelName,
            near: selection.bounds,
            initialStatus: "⚡ Explaining with AI..."
        )

        // 2. Perform four-finger web explanation asynchronously in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.popoverWindow.updateProgress(
                    status: "⚡ Explaining with \(modelName)...",
                    docName: appDisplayName,
                    pageDisplay: "🖐️ 4-Finger Meaning"
                )
            }

            AIService.shared.explainFourFingerSelection(
                selection: selection.text,
                appName: selection.appName,
                config: self.config
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let res):
                    self.lastExplanationText = res.text
                    self.lastPageContextText = nil // Strictly no window context stored
                    var activeModelDisplay = modelName
                    if let fb = res.fallbackUsed {
                        activeModelDisplay = "\(fb) [Fallback]"
                    }
                    self.popoverWindow.showExplanation(
                        selection: selection.text,
                        docName: appDisplayName,
                        pageDisplay: "🖐️ 4-Finger Meaning",
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

    // MARK: - ExplanationPopoverDelegate
    func didRequestRegenerate(simpler: Bool) {
        guard let sel = lastSelection else { return }
        if sel.appBundleId == "com.apple.Preview" {
            let originalPreset = config.activePresetId
            config.activePresetId = simpler ? "plain_english" : "concise_context"
            executeExplanation(for: sel)
            config.activePresetId = originalPreset
        } else {
            executeFourFingerExplanation(for: sel)
        }
    }

    func didSubmitDoubt(doubtText: String) {
        guard let sel = lastSelection else { return }
        let docName = (sel.documentPath as NSString?)?.lastPathComponent ?? sel.appName
        AIService.shared.answerDoubt(
            selection: sel.text,
            docName: docName,
            pageContext: lastPageContextText,
            previousExplanation: lastExplanationText,
            doubt: doubtText,
            config: self.config
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let answer):
                self.popoverWindow.appendDoubtAnswer(replyMarkdown: answer)
            case .failure(let error):
                self.popoverWindow.appendDoubtAnswer(replyMarkdown: "⚠️ Could not answer doubt: " + error.localizedDescription)
            }
        }
    }

    func didRequestOpenSettings() {
        openSettings()
    }

    // MARK: - SettingsDelegate
    func didUpdateConfig(_ updatedConfig: AppConfig) {
        self.config = updatedConfig
        multitouchManager.isEnabled = updatedConfig.enableFourFingerTap
        updateStatusMenu()
    }
}

// MARK: - Main Application Run Loop
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
