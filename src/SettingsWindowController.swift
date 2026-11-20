import Cocoa

public protocol SettingsDelegate: AnyObject {
    func didUpdateConfig(_ config: AppConfig)
}

public class SettingsWindowController: NSWindowController, NSTextViewDelegate {
    public weak var delegate: SettingsDelegate?
    private var config: AppConfig

    // UI Elements
    private var providerSegment: NSSegmentedControl!
    private var apiKeyField: NSSecureTextField!
    private var apiKeyPlainField: NSTextField!
    private var isKeyRevealed: Bool = false
    private var revealKeyButton: NSButton!
    private var getKeyLinkButton: NSButton!
    private var testFetchButton: NSButton!
    private var statusLabel: NSTextField!
    private var modelPopUp: NSPopUpButton!
    private var fallbackPopUp: NSPopUpButton!
    private var fallbackModelPopUp: NSPopUpButton!
    private var progressIndicator: NSProgressIndicator!

    // PDF Prompt tab
    private var presetPopUp: NSPopUpButton!
    private var presetDescriptionLabel: NSTextField!
    private var systemPromptView: NSTextView!
    private var templatePromptView: NSTextView!

    // Gestures & Shortcuts UI
    private var gesturePopUp: NSPopUpButton!
    private var universalShortcutPopUp: NSPopUpButton!
    private var recordUniversalButton: NSButton!
    private var resetUniversalButton: NSButton!
    private var tempUniversalShortcut: ShortcutConfig!

    private var clipboardShortcutPopUp: NSPopUpButton!
    private var recordClipboardButton: NSButton!
    private var resetClipboardButton: NSButton!
    private var tempClipboardShortcut: ShortcutConfig!

    private var fourFingerSystemPromptView: NSTextView!
    private var fourFingerTemplatePromptView: NSTextView!

    // Behavior tab
    private var enablePillCheckbox: NSButton!
    private var enableContextCheckbox: NSButton!
    private var contextShortcutPopUp: NSPopUpButton!
    private var recordContextButton: NSButton!
    private var resetContextButton: NSButton!
    private var tempContextShortcut: ShortcutConfig!
    private var permissionStatusLabel: NSTextField!
    private var openPermissionButton: NSButton!

    // Interactive Key Recorder
    private enum ShortcutTarget {
        case universal
        case context
        case clipboard
    }
    private var activeRecordingTarget: ShortcutTarget? = nil
    private var localKeyMonitor: Any? = nil

    private var tabView: NSTabView!

    public init(config: AppConfig) {
        self.config = config

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 630, height: 570),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PlatoReader Preferences"
        window.center()
        super.init(window: window)

        setupUI()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        tabView = NSTabView(frame: NSRect(x: 20, y: 60, width: 590, height: 490))
        tabView.autoresizingMask = [.width, .height]

        // 1. Tab AI & Models
        let aiTab = NSTabViewItem(identifier: "ai")
        aiTab.label = "🤖 AI & Models"
        aiTab.view = createAITabView(frame: tabView.bounds)
        tabView.addTabViewItem(aiTab)

        // 2. Tab Prompts (PDF)
        let promptTab = NSTabViewItem(identifier: "prompts")
        promptTab.label = "📖 PDF Prompts"
        promptTab.view = createPromptTabView(frame: tabView.bounds)
        tabView.addTabViewItem(promptTab)

        // 3. Tab Gestures & Shortcuts
        let fourFingerTab = NSTabViewItem(identifier: "fourfinger")
        fourFingerTab.label = "🖐️ Gestures & Shortcuts"
        fourFingerTab.view = createFourFingerTabView(frame: tabView.bounds)
        tabView.addTabViewItem(fourFingerTab)

        // 4. Tab Reading Behavior
        let behaviorTab = NSTabViewItem(identifier: "behavior")
        behaviorTab.label = "⚙️ Preferences"
        behaviorTab.view = createBehaviorTabView(frame: tabView.bounds)
        tabView.addTabViewItem(behaviorTab)

        contentView.addSubview(tabView)

        // Bottom Save Button
        let saveButton = NSButton(frame: NSRect(x: 480, y: 16, width: 130, height: 32))
        saveButton.title = "Save & Apply"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveAndClose)
        contentView.addSubview(saveButton)

        let cancelBtn = NSButton(frame: NSRect(x: 380, y: 16, width: 90, height: 32))
        cancelBtn.title = "Cancel"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}" // Esc
        cancelBtn.target = self
        cancelBtn.action = #selector(cancel)
        contentView.addSubview(cancelBtn)
    }

    // MARK: - AI Tab Creation
    private func createAITabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        // Provider Selector
        let providerLabel = createLabel(text: "Select Primary Provider:", frame: NSRect(x: 20, y: 395, width: 220, height: 20), bold: true)
        view.addSubview(providerLabel)

        providerSegment = NSSegmentedControl(labels: ["Gemini", "Groq", "OpenRouter", "OpenAI"], trackingMode: .selectOne, target: self, action: #selector(providerChanged))
        providerSegment.frame = NSRect(x: 20, y: 360, width: 530, height: 30)
        view.addSubview(providerSegment)

        // API Key Section
        let keyLabel = createLabel(text: "API Key for Selected Provider:", frame: NSRect(x: 20, y: 325, width: 250, height: 20), bold: true)
        view.addSubview(keyLabel)

        apiKeyField = NSSecureTextField(frame: NSRect(x: 20, y: 295, width: 440, height: 24))
        apiKeyField.placeholderString = "Paste API key here..."
        view.addSubview(apiKeyField)

        apiKeyPlainField = NSTextField(frame: NSRect(x: 20, y: 295, width: 440, height: 24))
        apiKeyPlainField.placeholderString = "Paste API key here..."
        apiKeyPlainField.isHidden = true
        view.addSubview(apiKeyPlainField)

        revealKeyButton = NSButton(frame: NSRect(x: 470, y: 293, width: 80, height: 26))
        revealKeyButton.title = "👁️ Show"
        revealKeyButton.bezelStyle = .rounded
        revealKeyButton.target = self
        revealKeyButton.action = #selector(toggleKeyReveal)
        view.addSubview(revealKeyButton)

        getKeyLinkButton = NSButton(frame: NSRect(x: 20, y: 265, width: 200, height: 20))
        getKeyLinkButton.title = "🔗 Get API Key from Provider →"
        getKeyLinkButton.isBordered = false
        getKeyLinkButton.contentTintColor = NSColor.linkColor
        getKeyLinkButton.target = self
        getKeyLinkButton.action = #selector(openKeyPortal)
        view.addSubview(getKeyLinkButton)

        // Fetch Models & Test Button
        testFetchButton = NSButton(frame: NSRect(x: 20, y: 225, width: 240, height: 32))
        testFetchButton.title = "⚡ Test Key & Fetch Models"
        testFetchButton.bezelStyle = .rounded
        testFetchButton.target = self
        testFetchButton.action = #selector(testAndFetchModels)
        view.addSubview(testFetchButton)

        progressIndicator = NSProgressIndicator(frame: NSRect(x: 270, y: 232, width: 18, height: 18))
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        view.addSubview(progressIndicator)

        statusLabel = createLabel(text: "", frame: NSRect(x: 300, y: 230, width: 250, height: 20), bold: false)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        view.addSubview(statusLabel)

        // Active Model Dropdown
        let modelLabel = createLabel(text: "Active Model for Selected Provider:", frame: NSRect(x: 20, y: 185, width: 300, height: 20), bold: true)
        view.addSubview(modelLabel)

        modelPopUp = NSPopUpButton(frame: NSRect(x: 20, y: 155, width: 530, height: 26))
        modelPopUp.target = self
        modelPopUp.action = #selector(modelSelected)
        view.addSubview(modelPopUp)

        // Fallback Section Box
        let fallbackBox = NSBox(frame: NSRect(x: 20, y: 20, width: 530, height: 120))
        fallbackBox.title = "🛡️ Automatic Failover Fallback"
        let boxView = NSView(frame: fallbackBox.contentView!.bounds)

        let fbDesc = createLabel(text: "If primary provider hits rate-limits or fails, PlatoReader fails over instantly without interrupting your reading.", frame: NSRect(x: 12, y: 65, width: 490, height: 30), bold: false)
        fbDesc.font = NSFont.systemFont(ofSize: 11)
        boxView.addSubview(fbDesc)

        let fbProviderLabel = createLabel(text: "Fallback Provider:", frame: NSRect(x: 12, y: 35, width: 130, height: 20), bold: true)
        fbProviderLabel.font = NSFont.systemFont(ofSize: 11)
        boxView.addSubview(fbProviderLabel)

        fallbackPopUp = NSPopUpButton(frame: NSRect(x: 145, y: 32, width: 160, height: 24))
        fallbackPopUp.addItem(withTitle: "None (Disabled)")
        fallbackPopUp.lastItem?.representedObject = "none"
        for p in AIProvider.allCases {
            fallbackPopUp.addItem(withTitle: p.displayName)
            fallbackPopUp.lastItem?.representedObject = p.rawValue
        }
        fallbackPopUp.target = self
        fallbackPopUp.action = #selector(fallbackProviderChanged)
        boxView.addSubview(fallbackPopUp)

        let fbModelLabel = createLabel(text: "Fallback Model:", frame: NSRect(x: 12, y: 8, width: 130, height: 20), bold: true)
        fbModelLabel.font = NSFont.systemFont(ofSize: 11)
        boxView.addSubview(fbModelLabel)

        fallbackModelPopUp = NSPopUpButton(frame: NSRect(x: 145, y: 5, width: 340, height: 24))
        boxView.addSubview(fallbackModelPopUp)

        fallbackBox.contentView = boxView
        view.addSubview(fallbackBox)

        return view
    }

    // MARK: - Prompt Tab Creation (PDF)
    private func createPromptTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let presetLabel = createLabel(text: "Choose Reading Preset for PDFs & Books:", frame: NSRect(x: 20, y: 400, width: 320, height: 20), bold: true)
        view.addSubview(presetLabel)

        presetPopUp = NSPopUpButton(frame: NSRect(x: 20, y: 370, width: 530, height: 26))
        for p in AppConfig.presets {
            presetPopUp.addItem(withTitle: p.title)
            presetPopUp.lastItem?.representedObject = p.id
        }
        presetPopUp.target = self
        presetPopUp.action = #selector(presetChanged)
        view.addSubview(presetPopUp)

        presetDescriptionLabel = createLabel(text: "", frame: NSRect(x: 20, y: 340, width: 530, height: 22), bold: false)
        presetDescriptionLabel.textColor = NSColor.secondaryLabelColor
        view.addSubview(presetDescriptionLabel)

        let sysPromptLabel = createLabel(text: "System Instructions:", frame: NSRect(x: 20, y: 310, width: 200, height: 20), bold: true)
        view.addSubview(sysPromptLabel)

        let sysScroll = NSScrollView(frame: NSRect(x: 20, y: 195, width: 530, height: 110))
        sysScroll.hasVerticalScroller = true
        sysScroll.borderType = .bezelBorder

        systemPromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 530, height: 110))
        systemPromptView.autoresizingMask = [.width]
        systemPromptView.isRichText = false
        systemPromptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sysScroll.documentView = systemPromptView
        view.addSubview(sysScroll)

        let templateLabel = createLabel(text: "Prompt Template (Variables: {selection}, {page_context}):", frame: NSRect(x: 20, y: 165, width: 500, height: 20), bold: true)
        view.addSubview(templateLabel)

        let templateScroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 530, height: 140))
        templateScroll.hasVerticalScroller = true
        templateScroll.borderType = .bezelBorder

        templatePromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 530, height: 140))
        templatePromptView.autoresizingMask = [.width]
        templatePromptView.isRichText = false
        templatePromptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        templateScroll.documentView = templatePromptView
        view.addSubview(templateScroll)

        return view
    }

    // MARK: - Gestures & Universal Web Lookup Tab Creation
    private func createFourFingerTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        // 1. Header & Description
        let headerLabel = createLabel(text: "🖐️ 3/4-Finger Tap Gesture & Universal Lookup", frame: NSRect(x: 20, y: 412, width: 540, height: 22), bold: true)
        headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        view.addSubview(headerLabel)

        let descLabel = createLabel(
            text: "Highlight text in Chrome, Safari, Notes, or anywhere on macOS and tap with 3 or 4 fingers (or press your shortcut) to explain its meaning and real-world context with zero latency.",
            frame: NSRect(x: 20, y: 382, width: 550, height: 28),
            bold: false
        )
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = NSColor.secondaryLabelColor
        view.addSubview(descLabel)

        // 2. Gesture Selector Dropdown
        let gestureLabel = createLabel(text: "Trackpad Tap Gesture:", frame: NSRect(x: 20, y: 350, width: 145, height: 20), bold: true)
        view.addSubview(gestureLabel)

        gesturePopUp = NSPopUpButton(frame: NSRect(x: 165, y: 347, width: 235, height: 26))
        for mode in GestureFingerMode.allCases {
            gesturePopUp.addItem(withTitle: mode.displayName)
            gesturePopUp.lastItem?.representedObject = mode.rawValue
        }
        view.addSubview(gesturePopUp)

        let gestureHint = createLabel(text: "Tap on trackpad triggers lookup", frame: NSRect(x: 410, y: 350, width: 170, height: 18), bold: false)
        gestureHint.font = NSFont.systemFont(ofSize: 11)
        gestureHint.textColor = NSColor.secondaryLabelColor
        view.addSubview(gestureHint)

        // 3. Universal Keyboard Shortcut Section
        let shortcutLabel = createLabel(text: "Universal Shortcut:", frame: NSRect(x: 20, y: 315, width: 145, height: 20), bold: true)
        view.addSubview(shortcutLabel)

        universalShortcutPopUp = NSPopUpButton(frame: NSRect(x: 165, y: 312, width: 235, height: 26))
        view.addSubview(universalShortcutPopUp)

        recordUniversalButton = NSButton(frame: NSRect(x: 410, y: 311, width: 110, height: 26))
        recordUniversalButton.title = "🎙️ Record Key"
        recordUniversalButton.bezelStyle = .rounded
        recordUniversalButton.target = self
        recordUniversalButton.action = #selector(recordUniversalClicked)
        view.addSubview(recordUniversalButton)

        resetUniversalButton = NSButton(frame: NSRect(x: 525, y: 311, width: 55, height: 26))
        resetUniversalButton.title = "↺ Reset"
        resetUniversalButton.bezelStyle = .rounded
        resetUniversalButton.target = self
        resetUniversalButton.action = #selector(resetUniversalClicked)
        view.addSubview(resetUniversalButton)

        // 4. Clipboard Explain Shortcut Section (New Feature)
        let clipboardLabel = createLabel(text: "Clipboard Shortcut:", frame: NSRect(x: 20, y: 280, width: 145, height: 20), bold: true)
        view.addSubview(clipboardLabel)

        clipboardShortcutPopUp = NSPopUpButton(frame: NSRect(x: 165, y: 277, width: 235, height: 26))
        view.addSubview(clipboardShortcutPopUp)

        recordClipboardButton = NSButton(frame: NSRect(x: 410, y: 276, width: 110, height: 26))
        recordClipboardButton.title = "🎙️ Record Key"
        recordClipboardButton.bezelStyle = .rounded
        recordClipboardButton.target = self
        recordClipboardButton.action = #selector(recordClipboardClicked)
        view.addSubview(recordClipboardButton)

        resetClipboardButton = NSButton(frame: NSRect(x: 525, y: 276, width: 55, height: 26))
        resetClipboardButton.title = "↺ Reset"
        resetClipboardButton.bezelStyle = .rounded
        resetClipboardButton.target = self
        resetClipboardButton.action = #selector(resetClipboardClicked)
        view.addSubview(resetClipboardButton)

        let clipboardHint = createLabel(text: "Explains recently copied text (⌘C) anytime using the 4-finger prompt.", frame: NSRect(x: 165, y: 258, width: 415, height: 16), bold: false)
        clipboardHint.font = NSFont.systemFont(ofSize: 10)
        clipboardHint.textColor = NSColor.secondaryLabelColor
        view.addSubview(clipboardHint)

        // 5. System Prompt Section
        let sysLabel = createLabel(text: "System Instructions (Universal Explainer):", frame: NSRect(x: 20, y: 235, width: 450, height: 18), bold: true)
        view.addSubview(sysLabel)

        let sysScroll = NSScrollView(frame: NSRect(x: 20, y: 148, width: 550, height: 85))
        sysScroll.hasVerticalScroller = true
        sysScroll.borderType = .bezelBorder

        fourFingerSystemPromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 550, height: 85))
        fourFingerSystemPromptView.autoresizingMask = [.width]
        fourFingerSystemPromptView.isRichText = false
        fourFingerSystemPromptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sysScroll.documentView = fourFingerSystemPromptView
        view.addSubview(sysScroll)

        // 6. Prompt Template Section
        let templateLabel = createLabel(text: "Prompt Template (Variable: {selection}):", frame: NSRect(x: 20, y: 122, width: 530, height: 18), bold: true)
        view.addSubview(templateLabel)

        let templateScroll = NSScrollView(frame: NSRect(x: 20, y: 45, width: 550, height: 75))
        templateScroll.hasVerticalScroller = true
        templateScroll.borderType = .bezelBorder

        fourFingerTemplatePromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 550, height: 75))
        fourFingerTemplatePromptView.autoresizingMask = [.width]
        fourFingerTemplatePromptView.isRichText = false
        fourFingerTemplatePromptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        templateScroll.documentView = fourFingerTemplatePromptView
        view.addSubview(templateScroll)

        // 7. Reset Prompt Button & Privacy Notice
        let resetBtn = NSButton(frame: NSRect(x: 20, y: 12, width: 195, height: 26))
        resetBtn.title = "🔄 Reset Prompt to Default"
        resetBtn.bezelStyle = .rounded
        resetBtn.target = self
        resetBtn.action = #selector(resetFourFingerPromptClicked)
        view.addSubview(resetBtn)

        let privacyNote = createLabel(text: "🔒 Privacy: Only highlighted or copied text is sent. Background tabs are never read.", frame: NSRect(x: 225, y: 14, width: 345, height: 22), bold: false)
        privacyNote.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        privacyNote.textColor = NSColor.secondaryLabelColor
        view.addSubview(privacyNote)

        return view
    }

    // MARK: - Behavior Tab Creation
    private func createBehaviorTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        enablePillCheckbox = NSButton(checkboxWithTitle: "Show floating '💡 Explain' button above selected text in Preview", target: nil, action: nil)
        enablePillCheckbox.frame = NSRect(x: 20, y: 405, width: 500, height: 24)
        view.addSubview(enablePillCheckbox)

        enableContextCheckbox = NSButton(checkboxWithTitle: "Read surrounding page context from PDF in Preview automatically", target: nil, action: nil)
        enableContextCheckbox.frame = NSRect(x: 20, y: 375, width: 500, height: 24)
        view.addSubview(enableContextCheckbox)

        // PDF Context Shortcut Configuration
        let contextLabel = createLabel(text: "PDF Context Shortcut:", frame: NSRect(x: 20, y: 335, width: 150, height: 20), bold: true)
        view.addSubview(contextLabel)

        contextShortcutPopUp = NSPopUpButton(frame: NSRect(x: 175, y: 332, width: 225, height: 26))
        view.addSubview(contextShortcutPopUp)

        recordContextButton = NSButton(frame: NSRect(x: 410, y: 331, width: 110, height: 26))
        recordContextButton.title = "🎙️ Record Key"
        recordContextButton.bezelStyle = .rounded
        recordContextButton.target = self
        recordContextButton.action = #selector(recordContextClicked)
        view.addSubview(recordContextButton)

        resetContextButton = NSButton(frame: NSRect(x: 525, y: 331, width: 55, height: 26))
        resetContextButton.title = "↺ Reset"
        resetContextButton.bezelStyle = .rounded
        resetContextButton.target = self
        resetContextButton.action = #selector(resetContextClicked)
        view.addSubview(resetContextButton)

        // Shortcut & Gesture Reference Box
        let shortcutBox = NSBox(frame: NSRect(x: 20, y: 160, width: 550, height: 155))
        shortcutBox.title = "Keyboard Shortcuts & Trackpad Gestures"
        let boxView = NSView(frame: shortcutBox.contentView!.bounds)

        let scDesc = createLabel(
            text: "• PDF Context Explain: Triggers explanation with surrounding page context in Preview.\n• Universal Web Lookup: Explains any highlighted word or passage across all apps.\n• Trackpad: Supports 3-finger or 4-finger tap according to your configuration.\n• Customizable Shortcuts: Use presets or click 'Record Key' to set any key combo.\n• 📌 Pin Card: Anchors the floating explanation card in place while reading.",
            frame: NSRect(x: 12, y: 8, width: 525, height: 115),
            bold: false
        )
        scDesc.font = NSFont.systemFont(ofSize: 12)
        boxView.addSubview(scDesc)
        shortcutBox.contentView = boxView
        view.addSubview(shortcutBox)

        // Accessibility Section
        let permBox = NSBox(frame: NSRect(x: 20, y: 30, width: 550, height: 115))
        permBox.title = "macOS Accessibility Permission"
        let pView = NSView(frame: permBox.contentView!.bounds)

        permissionStatusLabel = createLabel(text: "", frame: NSRect(x: 12, y: 45, width: 300, height: 24), bold: true)
        pView.addSubview(permissionStatusLabel)

        openPermissionButton = NSButton(frame: NSRect(x: 340, y: 40, width: 170, height: 30))
        openPermissionButton.title = "Open System Settings"
        openPermissionButton.bezelStyle = .rounded
        openPermissionButton.target = self
        openPermissionButton.action = #selector(openAccessibilitySettings)
        pView.addSubview(openPermissionButton)

        permBox.contentView = pView
        view.addSubview(permBox)

        updatePermissionStatus()

        return view
    }

    private func createLabel(text: String, frame: NSRect, bold: Bool = false) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = bold ? NSFont.systemFont(ofSize: 13, weight: .semibold) : NSFont.systemFont(ofSize: 13)
        return label
    }

    // MARK: - Load & Sync Values
    private func loadValues() {
        switch config.selectedProvider {
        case .gemini: providerSegment.selectedSegment = 0
        case .groq: providerSegment.selectedSegment = 1
        case .openrouter: providerSegment.selectedSegment = 2
        case .openai: providerSegment.selectedSegment = 3
        }

        updateKeyAndLink()
        refreshModelList()

        // Fallback popup
        let fbStr = config.fallbackProvider?.rawValue ?? "groq"
        for item in fallbackPopUp.itemArray {
            if (item.representedObject as? String) == fbStr {
                fallbackPopUp.select(item)
                break
            }
        }
        refreshFallbackModelList()

        if let idx = AppConfig.presets.firstIndex(where: { $0.id == config.activePresetId }) {
            presetPopUp.selectItem(at: idx)
            presetDescriptionLabel.stringValue = AppConfig.presets[idx].description
        }
        systemPromptView.string = config.activeSystemPrompt()
        templatePromptView.string = config.activePromptTemplate()

        // Gestures & Shortcuts values
        for item in gesturePopUp.itemArray {
            if (item.representedObject as? String) == config.fingerTapMode.rawValue {
                gesturePopUp.select(item)
                break
            }
        }

        tempUniversalShortcut = config.universalShortcut
        populateShortcutPopUp(universalShortcutPopUp, current: tempUniversalShortcut, action: #selector(universalPresetChanged))

        tempClipboardShortcut = config.clipboardShortcut
        populateShortcutPopUp(clipboardShortcutPopUp, current: tempClipboardShortcut, action: #selector(clipboardPresetChanged))

        tempContextShortcut = config.contextShortcut
        populateShortcutPopUp(contextShortcutPopUp, current: tempContextShortcut, action: #selector(contextPresetChanged))

        fourFingerSystemPromptView.string = config.activeFourFingerSystemPrompt()
        fourFingerTemplatePromptView.string = config.activeFourFingerPromptTemplate()

        enablePillCheckbox.state = config.enableFloatingPill ? .on : .off
        enableContextCheckbox.state = config.enablePageContext ? .on : .off

        updatePermissionStatus()
    }

    // MARK: - Shortcut Management & Recording
    private func populateShortcutPopUp(_ popUp: NSPopUpButton, current: ShortcutConfig, action: Selector) {
        popUp.removeAllItems()
        for p in ShortcutConfig.standardPresets {
            popUp.addItem(withTitle: p.displayString)
            popUp.lastItem?.representedObject = p
        }
        popUp.addItem(withTitle: "Custom Key Combination...")
        popUp.lastItem?.representedObject = nil
        popUp.target = self
        popUp.action = action
        syncPopUpSelection(popUp, current: current)
    }

    private func syncPopUpSelection(_ popUp: NSPopUpButton, current: ShortcutConfig) {
        var matched = false
        for item in popUp.itemArray {
            if let sc = item.representedObject as? ShortcutConfig, sc.keyCode == current.keyCode && sc.modifiers == current.modifiers {
                popUp.select(item)
                matched = true
                break
            }
        }
        if !matched {
            if let customItem = popUp.itemArray.last {
                customItem.title = "Custom: \(current.displayString)"
                popUp.select(customItem)
            }
        }
    }

    @objc private func universalPresetChanged() {
        guard let item = universalShortcutPopUp.selectedItem else { return }
        if let sc = item.representedObject as? ShortcutConfig {
            tempUniversalShortcut = sc
        } else {
            startRecording(target: .universal)
        }
    }

    @objc private func clipboardPresetChanged() {
        guard let item = clipboardShortcutPopUp.selectedItem else { return }
        if let sc = item.representedObject as? ShortcutConfig {
            tempClipboardShortcut = sc
        } else {
            startRecording(target: .clipboard)
        }
    }

    @objc private func contextPresetChanged() {
        guard let item = contextShortcutPopUp.selectedItem else { return }
        if let sc = item.representedObject as? ShortcutConfig {
            tempContextShortcut = sc
        } else {
            startRecording(target: .context)
        }
    }

    @objc private func recordUniversalClicked() {
        if activeRecordingTarget == .universal {
            stopRecording()
        } else {
            startRecording(target: .universal)
        }
    }

    @objc private func recordClipboardClicked() {
        if activeRecordingTarget == .clipboard {
            stopRecording()
        } else {
            startRecording(target: .clipboard)
        }
    }

    @objc private func recordContextClicked() {
        if activeRecordingTarget == .context {
            stopRecording()
        } else {
            startRecording(target: .context)
        }
    }

    @objc private func resetUniversalClicked() {
        stopRecording()
        tempUniversalShortcut = ShortcutConfig.defaultUniversal
        syncPopUpSelection(universalShortcutPopUp, current: tempUniversalShortcut)
    }

    @objc private func resetClipboardClicked() {
        stopRecording()
        tempClipboardShortcut = ShortcutConfig.defaultClipboard
        syncPopUpSelection(clipboardShortcutPopUp, current: tempClipboardShortcut)
    }

    @objc private func resetContextClicked() {
        stopRecording()
        tempContextShortcut = ShortcutConfig.defaultContext
        syncPopUpSelection(contextShortcutPopUp, current: tempContextShortcut)
    }

    private func startRecording(target: ShortcutTarget) {
        stopRecording()
        activeRecordingTarget = target

        if target == .universal {
            recordUniversalButton.title = "⌨️ Press Keys (Esc)"
        } else if target == .clipboard {
            recordClipboardButton.title = "⌨️ Press Keys (Esc)"
        } else {
            recordContextButton.title = "⌨️ Press Keys (Esc)"
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 { // Escape
                self.stopRecording()
                return nil
            }

            let cocoaMods = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if !cocoaMods.isEmpty {
                let carbonMods = ShortcutConfig.carbonModifiers(from: cocoaMods)
                let keyCode = UInt32(event.keyCode)
                let display = ShortcutConfig.formatDisplayString(keyCode: keyCode, modifiers: carbonMods)
                let newSc = ShortcutConfig(keyCode: keyCode, modifiers: carbonMods, displayString: display)

                if self.activeRecordingTarget == .universal {
                    self.tempUniversalShortcut = newSc
                    self.syncPopUpSelection(self.universalShortcutPopUp, current: newSc)
                } else if self.activeRecordingTarget == .clipboard {
                    self.tempClipboardShortcut = newSc
                    self.syncPopUpSelection(self.clipboardShortcutPopUp, current: newSc)
                } else if self.activeRecordingTarget == .context {
                    self.tempContextShortcut = newSc
                    self.syncPopUpSelection(self.contextShortcutPopUp, current: newSc)
                }
                self.stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
        activeRecordingTarget = nil
        recordUniversalButton?.title = "🎙️ Record Key"
        recordClipboardButton?.title = "🎙️ Record Key"
        recordContextButton?.title = "🎙️ Record Key"
    }

    @objc private func resetFourFingerPromptClicked() {
        fourFingerSystemPromptView.string = AppConfig.defaultFourFingerSystemPrompt
        fourFingerTemplatePromptView.string = AppConfig.defaultFourFingerPromptTemplate
    }

    @objc private func providerChanged() {
        saveCurrentKeyToMemory()

        switch providerSegment.selectedSegment {
        case 0: config.selectedProvider = .gemini
        case 1: config.selectedProvider = .groq
        case 2: config.selectedProvider = .openrouter
        case 3: config.selectedProvider = .openai
        default: break
        }

        updateKeyAndLink()
        refreshModelList()
        statusLabel.stringValue = ""
    }

    private func updateKeyAndLink() {
        let currentKey = config.apiKeys[config.selectedProvider.rawValue] ?? ""
        apiKeyField.stringValue = currentKey
        apiKeyPlainField.stringValue = currentKey
        getKeyLinkButton.title = "🔗 Get \(config.selectedProvider.displayName) API Key →"
    }

    @objc private func toggleKeyReveal() {
        isKeyRevealed.toggle()
        if isKeyRevealed {
            apiKeyPlainField.stringValue = apiKeyField.stringValue
            apiKeyPlainField.isHidden = false
            apiKeyField.isHidden = true
            revealKeyButton.title = "🔒 Hide"
        } else {
            apiKeyField.stringValue = apiKeyPlainField.stringValue
            apiKeyField.isHidden = false
            apiKeyPlainField.isHidden = true
            revealKeyButton.title = "👁️ Show"
        }
    }

    @objc private func openKeyPortal() {
        if let url = URL(string: config.selectedProvider.keyPortalURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveCurrentKeyToMemory() {
        let currentVal = isKeyRevealed ? apiKeyPlainField.stringValue : apiKeyField.stringValue
        config.apiKeys[config.selectedProvider.rawValue] = currentVal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func testAndFetchModels() {
        saveCurrentKeyToMemory()
        let key = config.currentKey()

        guard !key.isEmpty else {
            statusLabel.stringValue = "⚠️ Please enter an API key first."
            statusLabel.textColor = NSColor.systemRed
            return
        }

        testFetchButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Fetching available models..."
        statusLabel.textColor = NSColor.secondaryLabelColor

        let provider = config.selectedProvider

        AIService.shared.fetchModels(provider: provider, apiKey: key) { [weak self] result in
            guard let self = self else { return }
            self.testFetchButton.isEnabled = true
            self.progressIndicator.stopAnimation(nil)

            switch result {
            case .success(let models):
                self.config.cachedModels[provider.rawValue] = models
                self.refreshModelList()
                self.refreshFallbackModelList()
                self.statusLabel.stringValue = "✅ Key valid! Found \(models.count) models."
                self.statusLabel.textColor = NSColor.systemGreen
                self.config.save()
            case .failure(let error):
                self.statusLabel.stringValue = "❌ " + error.localizedDescription
                self.statusLabel.textColor = NSColor.systemRed
            }
        }
    }

    private func refreshModelList() {
        modelPopUp.removeAllItems()
        let provider = config.selectedProvider
        let models = config.cachedModels[provider.rawValue] ?? []

        let activeSavedModel = config.selectedModels[provider.rawValue] ?? provider.defaultModel
        var foundMatch = false

        for m in models {
            modelPopUp.addItem(withTitle: m.name)
            modelPopUp.lastItem?.representedObject = m.id
            if m.id == activeSavedModel {
                modelPopUp.select(modelPopUp.lastItem)
                foundMatch = true
            }
        }

        if !foundMatch {
            if !models.isEmpty {
                modelPopUp.selectItem(at: 0)
                if let id = modelPopUp.selectedItem?.representedObject as? String {
                    config.selectedModels[provider.rawValue] = id
                }
            } else {
                modelPopUp.addItem(withTitle: provider.defaultModel)
                modelPopUp.lastItem?.representedObject = provider.defaultModel
                modelPopUp.selectItem(at: 0)
            }
        }
    }

    @objc private func modelSelected() {
        if let id = modelPopUp.selectedItem?.representedObject as? String {
            config.selectedModels[config.selectedProvider.rawValue] = id
        }
    }

    @objc private func fallbackProviderChanged() {
        guard let item = fallbackPopUp.selectedItem, let repr = item.representedObject as? String else { return }
        if repr == "none" {
            config.fallbackProvider = nil
        } else if let p = AIProvider(rawValue: repr) {
            config.fallbackProvider = p
        }
        refreshFallbackModelList()
    }

    @objc private func presetChanged() {
        guard let item = presetPopUp.selectedItem, let repr = item.representedObject as? String else { return }
        config.activePresetId = repr
        if let p = AppConfig.presets.first(where: { $0.id == repr }) {
            presetDescriptionLabel.stringValue = p.description
            systemPromptView.string = p.systemPrompt
            templatePromptView.string = p.template
        }
    }

    private func refreshFallbackModelList() {
        fallbackModelPopUp.removeAllItems()
        guard let fbSelected = fallbackPopUp.selectedItem?.representedObject as? String,
              fbSelected != "none",
              let provider = AIProvider(rawValue: fbSelected) else {
            fallbackModelPopUp.isEnabled = false
            fallbackModelPopUp.addItem(withTitle: "No fallback active")
            return
        }

        fallbackModelPopUp.isEnabled = true
        let cached = config.cachedModels[provider.rawValue] ?? []
        let currentFallbackModel = config.fallbackModel ?? provider.defaultModel

        var foundMatch = false
        for m in cached {
            fallbackModelPopUp.addItem(withTitle: m.name)
            fallbackModelPopUp.lastItem?.representedObject = m.id
            if m.id == currentFallbackModel {
                fallbackModelPopUp.select(fallbackModelPopUp.lastItem)
                foundMatch = true
            }
        }

        if !foundMatch {
            if !cached.isEmpty {
                fallbackModelPopUp.selectItem(at: 0)
            } else {
                fallbackModelPopUp.addItem(withTitle: provider.defaultModel)
                fallbackModelPopUp.lastItem?.representedObject = provider.defaultModel
                fallbackModelPopUp.selectItem(at: 0)
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        let urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
        AccessibilityHelper.requestAccessibilityPermission()
    }

    public func updatePermissionStatus() {
        let granted = AccessibilityHelper.isAccessibilityTrusted()
        if granted {
            permissionStatusLabel.stringValue = "🟢 Permission Granted"
            permissionStatusLabel.textColor = NSColor.systemGreen
            openPermissionButton.title = "Re-check Permission"
        } else {
            permissionStatusLabel.stringValue = "🔴 Permission Needed"
            permissionStatusLabel.textColor = NSColor.systemRed
            openPermissionButton.title = "Grant in Settings"
        }
    }

    @objc private func saveAndClose() {
        stopRecording()
        saveCurrentKeyToMemory()

        config.enableFloatingPill = (enablePillCheckbox.state == .on)
        config.enablePageContext = (enableContextCheckbox.state == .on)

        // Save Gestures & Shortcuts
        if let gestureRaw = gesturePopUp.selectedItem?.representedObject as? String,
           let mode = GestureFingerMode(rawValue: gestureRaw) {
            config.fingerTapMode = mode
            config.enableFourFingerTap = (mode != .disabled)
        }

        if let uSc = tempUniversalShortcut {
            config.universalShortcut = uSc
            config.fourFingerHotkeyString = uSc.displayString
        }

        if let clSc = tempClipboardShortcut {
            config.clipboardShortcut = clSc
        }

        if let cSc = tempContextShortcut {
            config.contextShortcut = cSc
            config.hotkeyString = cSc.displayString
        }

        // Save Prompts
        config.fourFingerSystemPrompt = fourFingerSystemPromptView.string
        config.fourFingerPromptTemplate = fourFingerTemplatePromptView.string

        if config.activePresetId == "custom" {
            config.customSystemPrompt = systemPromptView.string
            config.customPromptTemplate = templatePromptView.string
        }

        config.save()
        delegate?.didUpdateConfig(config)
        self.window?.close()
    }

    @objc private func cancel() {
        stopRecording()
        self.window?.close()
    }
}
