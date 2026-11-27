import Cocoa

public protocol SettingsDelegate: AnyObject {
    func didUpdateConfig(_ config: AppConfig)
}

public class SettingsWindowController: NSWindowController, NSTextViewDelegate {
    public weak var delegate: SettingsDelegate?
    private var config: AppConfig

    // Navigation
    private var tabView: NSTabView!

    // General Tab (Reading, Gestures, Shortcuts, Permissions)
    private var enablePillCheckbox: NSButton!
    private var enableContextCheckbox: NSButton!
    private var gesturePopUp: NSPopUpButton!
    private var universalShortcutPopUp: NSPopUpButton!
    private var recordUniversalButton: NSButton!
    private var resetUniversalButton: NSButton!
    private var tempUniversalShortcut: ShortcutConfig!

    private var contextShortcutPopUp: NSPopUpButton!
    private var recordContextButton: NSButton!
    private var resetContextButton: NSButton!
    private var tempContextShortcut: ShortcutConfig!

    private var clipboardShortcutPopUp: NSPopUpButton!
    private var recordClipboardButton: NSButton!
    private var resetClipboardButton: NSButton!
    private var tempClipboardShortcut: ShortcutConfig!

    private var permissionStatusLabel: NSTextField!
    private var openPermissionButton: NSButton!

    // AI Tab
    private var providerSegment: NSSegmentedControl!
    private var keyLabel: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var apiKeyPlainField: NSTextField!
    private var cliPathField: NSTextField!
    private var cliBrowseButton: NSButton!
    private var isKeyRevealed: Bool = false
    private var revealKeyButton: NSButton!
    private var getKeyLinkButton: NSButton!
    private var testFetchButton: NSButton!
    private var statusLabel: NSTextField!
    private var modelPopUp: NSPopUpButton!
    private var progressIndicator: NSProgressIndicator!

    private var enableFallbackCheckbox: NSButton!
    private var fallbackContainer: NSView!
    private var fallbackPopUp: NSPopUpButton!
    private var fallbackModelPopUp: NSPopUpButton!

    // Prompts Tab
    private var presetPopUp: NSPopUpButton!
    private var presetDescriptionLabel: NSTextField!
    private var showAdvancedPromptsCheckbox: NSButton!
    private var advancedCollapsedHint: NSTextField!
    private var advancedPromptsContainer: NSView!
    private var promptScopeSegment: NSSegmentedControl!
    private var promptSystemView: NSTextView!
    private var promptTemplateView: NSTextView!
    private var promptVarsHint: NSTextField!
    private var resetPromptButton: NSButton!

    // Working buffers for prompt editor (0 = PDF, 1 = Universal)
    private var draftPDFSystemPrompt: String = ""
    private var draftPDFTemplate: String = ""
    private var draftUniversalSystemPrompt: String = ""
    private var draftUniversalTemplate: String = ""
    private var activePromptScope: Int = 0
    private var isUpdatingPromptViews: Bool = false

    // Interactive Key Recorder
    private enum ShortcutTarget {
        case universal
        case context
        case clipboard
    }
    private var activeRecordingTarget: ShortcutTarget? = nil
    private var localKeyMonitor: Any? = nil

    public init(config: AppConfig) {
        self.config = config

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 475),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PlatoReader Settings"
        window.center()
        super.init(window: window)

        setupUI()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }

        tabView = NSTabView(frame: NSRect(x: 20, y: 56, width: 560, height: 400))
        tabView.autoresizingMask = [.width, .height]

        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = createGeneralTabView(frame: tabView.bounds)
        tabView.addTabViewItem(generalTab)

        let aiTab = NSTabViewItem(identifier: "ai")
        aiTab.label = "AI"
        aiTab.view = createAITabView(frame: tabView.bounds)
        tabView.addTabViewItem(aiTab)

        let promptsTab = NSTabViewItem(identifier: "prompts")
        promptsTab.label = "Prompts"
        promptsTab.view = createPromptsTabView(frame: tabView.bounds)
        tabView.addTabViewItem(promptsTab)

        contentView.addSubview(tabView)

        let saveButton = NSButton(frame: NSRect(x: 470, y: 14, width: 110, height: 30))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveAndClose)
        contentView.addSubview(saveButton)

        let cancelBtn = NSButton(frame: NSRect(x: 375, y: 14, width: 85, height: 30))
        cancelBtn.title = "Cancel"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.target = self
        cancelBtn.action = #selector(cancel)
        contentView.addSubview(cancelBtn)
    }

    // MARK: - General Tab (Reading, Gestures & Shortcuts)
    private func createGeneralTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let readingTitle = createLabel(text: "Reading", frame: NSRect(x: 18, y: 332, width: 200, height: 18), bold: true)
        view.addSubview(readingTitle)

        enablePillCheckbox = NSButton(checkboxWithTitle: "Show floating \"Explain\" button when text is selected", target: nil, action: nil)
        enablePillCheckbox.frame = NSRect(x: 18, y: 304, width: 510, height: 22)
        view.addSubview(enablePillCheckbox)

        enableContextCheckbox = NSButton(checkboxWithTitle: "Include surrounding PDF page context in Preview", target: nil, action: nil)
        enableContextCheckbox.frame = NSRect(x: 18, y: 278, width: 510, height: 22)
        view.addSubview(enableContextCheckbox)

        let sep1 = NSBox(frame: NSRect(x: 18, y: 264, width: 505, height: 1))
        sep1.boxType = .separator
        view.addSubview(sep1)

        let triggerTitle = createLabel(text: "Shortcuts & Trackpad", frame: NSRect(x: 18, y: 236, width: 240, height: 18), bold: true)
        view.addSubview(triggerTitle)

        let gestureLabel = createLabel(text: "Trackpad Tap", frame: NSRect(x: 18, y: 204, width: 130, height: 20), bold: false)
        view.addSubview(gestureLabel)

        gesturePopUp = NSPopUpButton(frame: NSRect(x: 155, y: 201, width: 225, height: 26))
        for mode in GestureFingerMode.allCases {
            gesturePopUp.addItem(withTitle: mode.displayName)
            gesturePopUp.lastItem?.representedObject = mode.rawValue
        }
        view.addSubview(gesturePopUp)

        let uLabel = createLabel(text: "Explain Anywhere", frame: NSRect(x: 18, y: 168, width: 130, height: 20), bold: false)
        view.addSubview(uLabel)
        universalShortcutPopUp = NSPopUpButton(frame: NSRect(x: 155, y: 165, width: 225, height: 26))
        view.addSubview(universalShortcutPopUp)
        recordUniversalButton = createSmallButton(title: "Record", frame: NSRect(x: 388, y: 165, width: 72, height: 25), action: #selector(recordUniversalClicked))
        view.addSubview(recordUniversalButton)
        resetUniversalButton = createSmallButton(title: "Reset", frame: NSRect(x: 465, y: 165, width: 60, height: 25), action: #selector(resetUniversalClicked))
        view.addSubview(resetUniversalButton)

        let cLabel = createLabel(text: "Explain in PDF", frame: NSRect(x: 18, y: 134, width: 130, height: 20), bold: false)
        view.addSubview(cLabel)
        contextShortcutPopUp = NSPopUpButton(frame: NSRect(x: 155, y: 131, width: 225, height: 26))
        view.addSubview(contextShortcutPopUp)
        recordContextButton = createSmallButton(title: "Record", frame: NSRect(x: 388, y: 131, width: 72, height: 25), action: #selector(recordContextClicked))
        view.addSubview(recordContextButton)
        resetContextButton = createSmallButton(title: "Reset", frame: NSRect(x: 465, y: 131, width: 60, height: 25), action: #selector(resetContextClicked))
        view.addSubview(resetContextButton)

        let clLabel = createLabel(text: "Explain Copied Text", frame: NSRect(x: 18, y: 100, width: 130, height: 20), bold: false)
        view.addSubview(clLabel)
        clipboardShortcutPopUp = NSPopUpButton(frame: NSRect(x: 155, y: 97, width: 225, height: 26))
        view.addSubview(clipboardShortcutPopUp)
        recordClipboardButton = createSmallButton(title: "Record", frame: NSRect(x: 388, y: 97, width: 72, height: 25), action: #selector(recordClipboardClicked))
        view.addSubview(recordClipboardButton)
        resetClipboardButton = createSmallButton(title: "Reset", frame: NSRect(x: 465, y: 97, width: 60, height: 25), action: #selector(resetClipboardClicked))
        view.addSubview(resetClipboardButton)

        let shortcutNote = createLabel(text: "Tip: Pressing a shortcut with no text selected opens Quick Ask.", frame: NSRect(x: 155, y: 72, width: 375, height: 16), bold: false)
        shortcutNote.font = NSFont.systemFont(ofSize: 11)
        shortcutNote.textColor = NSColor.secondaryLabelColor
        view.addSubview(shortcutNote)

        let sep2 = NSBox(frame: NSRect(x: 18, y: 56, width: 505, height: 1))
        sep2.boxType = .separator
        view.addSubview(sep2)

        permissionStatusLabel = createLabel(text: "", frame: NSRect(x: 18, y: 28, width: 320, height: 20), bold: false)
        permissionStatusLabel.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(permissionStatusLabel)

        openPermissionButton = NSButton(frame: NSRect(x: 365, y: 24, width: 160, height: 26))
        openPermissionButton.title = "Accessibility Settings"
        openPermissionButton.bezelStyle = .rounded
        openPermissionButton.target = self
        openPermissionButton.action = #selector(openAccessibilitySettings)
        view.addSubview(openPermissionButton)

        let versionLabel = createLabel(text: "Version \(UpdateManager.shared.currentVersion)", frame: NSRect(x: 18, y: 4, width: 220, height: 18), bold: false)
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = NSColor.secondaryLabelColor
        view.addSubview(versionLabel)

        let checkUpdateBtn = createSmallButton(title: "Check for Updates", frame: NSRect(x: 365, y: 0, width: 160, height: 24), action: #selector(checkForUpdatesFromSettings))
        checkUpdateBtn.font = NSFont.systemFont(ofSize: 11.5)
        view.addSubview(checkUpdateBtn)

        return view
    }

    // MARK: - AI Tab (Provider, Model, Optional Backup)
    private func createAITabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let providerLabel = createLabel(text: "Provider", frame: NSRect(x: 18, y: 332, width: 200, height: 18), bold: true)
        view.addSubview(providerLabel)

        providerSegment = NSSegmentedControl(labels: ["Gemini", "Groq", "OpenRouter", "OpenAI", "OpenCode", "Antigravity"], trackingMode: .selectOne, target: self, action: #selector(providerChanged))
        providerSegment.frame = NSRect(x: 16, y: 298, width: 512, height: 28)
        view.addSubview(providerSegment)

        keyLabel = createLabel(text: "API Key", frame: NSRect(x: 18, y: 268, width: 350, height: 18), bold: false)
        view.addSubview(keyLabel)

        apiKeyField = NSSecureTextField(frame: NSRect(x: 18, y: 240, width: 420, height: 24))
        apiKeyField.placeholderString = "Paste API key..."
        view.addSubview(apiKeyField)

        apiKeyPlainField = NSTextField(frame: NSRect(x: 18, y: 240, width: 420, height: 24))
        apiKeyPlainField.placeholderString = "Paste API key..."
        apiKeyPlainField.isHidden = true
        view.addSubview(apiKeyPlainField)

        cliPathField = NSTextField(frame: NSRect(x: 18, y: 240, width: 420, height: 24))
        cliPathField.placeholderString = "Auto-detected automatically"
        cliPathField.isHidden = true
        view.addSubview(cliPathField)

        revealKeyButton = createSmallButton(title: "Show", frame: NSRect(x: 446, y: 239, width: 80, height: 25), action: #selector(toggleKeyReveal))
        view.addSubview(revealKeyButton)

        cliBrowseButton = createSmallButton(title: "Browse", frame: NSRect(x: 446, y: 239, width: 80, height: 25), action: #selector(browseCLIPath))
        cliBrowseButton.isHidden = true
        view.addSubview(cliBrowseButton)

        getKeyLinkButton = NSButton(frame: NSRect(x: 18, y: 214, width: 220, height: 18))
        getKeyLinkButton.title = "Get API Key →"
        getKeyLinkButton.isBordered = false
        getKeyLinkButton.alignment = .left
        getKeyLinkButton.font = NSFont.systemFont(ofSize: 11.5)
        getKeyLinkButton.contentTintColor = NSColor.linkColor
        getKeyLinkButton.target = self
        getKeyLinkButton.action = #selector(openKeyPortal)
        view.addSubview(getKeyLinkButton)

        let modelLabel = createLabel(text: "Model", frame: NSRect(x: 18, y: 182, width: 200, height: 18), bold: false)
        view.addSubview(modelLabel)

        modelPopUp = NSPopUpButton(frame: NSRect(x: 18, y: 152, width: 340, height: 26))
        modelPopUp.target = self
        modelPopUp.action = #selector(modelSelected)
        view.addSubview(modelPopUp)

        testFetchButton = NSButton(frame: NSRect(x: 366, y: 152, width: 160, height: 26))
        testFetchButton.title = "Verify & Refresh"
        testFetchButton.bezelStyle = .rounded
        testFetchButton.target = self
        testFetchButton.action = #selector(testAndFetchModels)
        view.addSubview(testFetchButton)

        progressIndicator = NSProgressIndicator(frame: NSRect(x: 18, y: 126, width: 16, height: 16))
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        view.addSubview(progressIndicator)

        statusLabel = createLabel(text: "", frame: NSRect(x: 38, y: 125, width: 488, height: 18), bold: false)
        statusLabel.font = NSFont.systemFont(ofSize: 11.5)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        view.addSubview(statusLabel)

        let sep = NSBox(frame: NSRect(x: 18, y: 108, width: 508, height: 1))
        sep.boxType = .separator
        view.addSubview(sep)

        // Toggleable Backup Provider
        enableFallbackCheckbox = NSButton(checkboxWithTitle: "Use a backup provider if the main one fails", target: self, action: #selector(fallbackToggleChanged))
        enableFallbackCheckbox.frame = NSRect(x: 18, y: 80, width: 420, height: 22)
        view.addSubview(enableFallbackCheckbox)

        fallbackContainer = NSView(frame: NSRect(x: 18, y: 12, width: 510, height: 64))
        let fbProviderLabel = createLabel(text: "Backup", frame: NSRect(x: 0, y: 36, width: 80, height: 20), bold: false)
        fallbackContainer.addSubview(fbProviderLabel)

        fallbackPopUp = NSPopUpButton(frame: NSRect(x: 84, y: 33, width: 424, height: 26))
        for p in AIProvider.allCases {
            fallbackPopUp.addItem(withTitle: p.displayName)
            fallbackPopUp.lastItem?.representedObject = p.rawValue
        }
        fallbackPopUp.target = self
        fallbackPopUp.action = #selector(fallbackProviderChanged)
        fallbackContainer.addSubview(fallbackPopUp)

        let fbModelLabel = createLabel(text: "Model", frame: NSRect(x: 0, y: 6, width: 80, height: 20), bold: false)
        fallbackContainer.addSubview(fbModelLabel)

        fallbackModelPopUp = NSPopUpButton(frame: NSRect(x: 84, y: 3, width: 424, height: 26))
        fallbackModelPopUp.target = self
        fallbackModelPopUp.action = #selector(fallbackModelChanged)
        fallbackContainer.addSubview(fallbackModelPopUp)

        view.addSubview(fallbackContainer)

        return view
    }

    // MARK: - Prompts Tab (Simple Style Picker + Toggleable Editor)
    private func createPromptsTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let presetLabel = createLabel(text: "Reading Style (PDF)", frame: NSRect(x: 18, y: 332, width: 250, height: 18), bold: true)
        view.addSubview(presetLabel)

        presetPopUp = NSPopUpButton(frame: NSRect(x: 18, y: 300, width: 508, height: 26))
        for p in AppConfig.presets {
            presetPopUp.addItem(withTitle: p.title)
            presetPopUp.lastItem?.representedObject = p.id
        }
        presetPopUp.target = self
        presetPopUp.action = #selector(presetChanged)
        view.addSubview(presetPopUp)

        presetDescriptionLabel = createLabel(text: "", frame: NSRect(x: 18, y: 274, width: 508, height: 20), bold: false)
        presetDescriptionLabel.font = NSFont.systemFont(ofSize: 11.5)
        presetDescriptionLabel.textColor = NSColor.secondaryLabelColor
        view.addSubview(presetDescriptionLabel)

        let sep = NSBox(frame: NSRect(x: 18, y: 258, width: 508, height: 1))
        sep.boxType = .separator
        view.addSubview(sep)

        showAdvancedPromptsCheckbox = NSButton(checkboxWithTitle: "Customize prompt instructions (Advanced)", target: self, action: #selector(advancedPromptsToggled))
        showAdvancedPromptsCheckbox.frame = NSRect(x: 18, y: 228, width: 400, height: 22)
        view.addSubview(showAdvancedPromptsCheckbox)

        advancedCollapsedHint = createLabel(
            text: "Using clean built-in prompts. Check the box above if you want to edit raw instructions.",
            frame: NSRect(x: 38, y: 202, width: 480, height: 20),
            bold: false
        )
        advancedCollapsedHint.font = NSFont.systemFont(ofSize: 11.5)
        advancedCollapsedHint.textColor = NSColor.secondaryLabelColor
        view.addSubview(advancedCollapsedHint)

        // Collapsible Advanced Editor Container
        advancedPromptsContainer = NSView(frame: NSRect(x: 18, y: 10, width: 510, height: 212))
        advancedPromptsContainer.isHidden = true

        promptScopeSegment = NSSegmentedControl(labels: ["PDF Explanations", "Universal & Quick Ask"], trackingMode: .selectOne, target: self, action: #selector(promptScopeChanged))
        promptScopeSegment.frame = NSRect(x: 0, y: 182, width: 320, height: 26)
        promptScopeSegment.selectedSegment = 0
        advancedPromptsContainer.addSubview(promptScopeSegment)

        resetPromptButton = createSmallButton(title: "Reset Default", frame: NSRect(x: 398, y: 183, width: 110, height: 24), action: #selector(resetActivePromptClicked))
        advancedPromptsContainer.addSubview(resetPromptButton)

        let sysLabel = createLabel(text: "Instructions", frame: NSRect(x: 0, y: 160, width: 200, height: 16), bold: false)
        sysLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        advancedPromptsContainer.addSubview(sysLabel)

        let sysScroll = NSScrollView(frame: NSRect(x: 0, y: 88, width: 508, height: 68))
        sysScroll.hasVerticalScroller = true
        sysScroll.borderType = .bezelBorder
        promptSystemView = NSTextView(frame: NSRect(x: 0, y: 0, width: 508, height: 68))
        promptSystemView.autoresizingMask = [.width]
        promptSystemView.isRichText = false
        promptSystemView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        promptSystemView.delegate = self
        sysScroll.documentView = promptSystemView
        advancedPromptsContainer.addSubview(sysScroll)

        promptVarsHint = createLabel(text: "Template ({selection}, {page_context})", frame: NSRect(x: 0, y: 66, width: 380, height: 16), bold: false)
        promptVarsHint.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        advancedPromptsContainer.addSubview(promptVarsHint)

        let tmplScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 508, height: 62))
        tmplScroll.hasVerticalScroller = true
        tmplScroll.borderType = .bezelBorder
        promptTemplateView = NSTextView(frame: NSRect(x: 0, y: 0, width: 508, height: 62))
        promptTemplateView.autoresizingMask = [.width]
        promptTemplateView.isRichText = false
        promptTemplateView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        promptTemplateView.delegate = self
        tmplScroll.documentView = promptTemplateView
        advancedPromptsContainer.addSubview(tmplScroll)

        view.addSubview(advancedPromptsContainer)

        return view
    }

    private func createLabel(text: String, frame: NSRect, bold: Bool = false) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = bold ? NSFont.systemFont(ofSize: 13, weight: .semibold) : NSFont.systemFont(ofSize: 12.5)
        return label
    }

    private func createSmallButton(title: String, frame: NSRect, action: Selector) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.title = title
        btn.bezelStyle = .rounded
        btn.target = self
        btn.action = action
        return btn
    }

    // MARK: - Load & Sync Values
    private func loadValues() {
        // General
        enablePillCheckbox.state = config.enableFloatingPill ? .on : .off
        enableContextCheckbox.state = config.enablePageContext ? .on : .off

        for item in gesturePopUp.itemArray {
            if (item.representedObject as? String) == config.fingerTapMode.rawValue {
                gesturePopUp.select(item)
                break
            }
        }

        tempUniversalShortcut = config.universalShortcut
        populateShortcutPopUp(universalShortcutPopUp, current: tempUniversalShortcut, action: #selector(universalPresetChanged))

        tempContextShortcut = config.contextShortcut
        populateShortcutPopUp(contextShortcutPopUp, current: tempContextShortcut, action: #selector(contextPresetChanged))

        tempClipboardShortcut = config.clipboardShortcut
        populateShortcutPopUp(clipboardShortcutPopUp, current: tempClipboardShortcut, action: #selector(clipboardPresetChanged))

        updatePermissionStatus()

        // AI
        if let idx = AIProvider.allCases.firstIndex(of: config.selectedProvider) {
            providerSegment.selectedSegment = idx
        } else {
            providerSegment.selectedSegment = 0
        }

        updateKeyAndLink()
        refreshModelList()

        let hasFallback = config.fallbackProvider != nil
        enableFallbackCheckbox.state = hasFallback ? .on : .off
        if let fb = config.fallbackProvider {
            for item in fallbackPopUp.itemArray {
                if (item.representedObject as? String) == fb.rawValue {
                    fallbackPopUp.select(item)
                    break
                }
            }
        }
        updateFallbackVisibility()
        refreshFallbackModelList()

        // Prompts
        if let idx = AppConfig.presets.firstIndex(where: { $0.id == config.activePresetId }) {
            presetPopUp.selectItem(at: idx)
            presetDescriptionLabel.stringValue = AppConfig.presets[idx].description
        }
        draftPDFSystemPrompt = config.activeSystemPrompt()
        draftPDFTemplate = config.activePromptTemplate()
        draftUniversalSystemPrompt = config.activeFourFingerSystemPrompt()
        draftUniversalTemplate = config.activeFourFingerPromptTemplate()

        showAdvancedPromptsCheckbox.state = .off
        updateAdvancedPromptsVisibility()
        syncPromptEditorViews()
    }

    // MARK: - Prompt Editor Visibility & Sync
    @objc private func advancedPromptsToggled() {
        updateAdvancedPromptsVisibility()
    }

    private func updateAdvancedPromptsVisibility() {
        let expanded = (showAdvancedPromptsCheckbox.state == .on)
        advancedPromptsContainer.isHidden = !expanded
        advancedCollapsedHint.isHidden = expanded
    }

    @objc private func promptScopeChanged() {
        saveActivePromptViewToDraft()
        activePromptScope = promptScopeSegment.selectedSegment
        syncPromptEditorViews()
    }

    private func saveActivePromptViewToDraft() {
        if activePromptScope == 0 {
            draftPDFSystemPrompt = promptSystemView.string
            draftPDFTemplate = promptTemplateView.string
        } else {
            draftUniversalSystemPrompt = promptSystemView.string
            draftUniversalTemplate = promptTemplateView.string
        }
    }

    private func syncPromptEditorViews() {
        isUpdatingPromptViews = true
        if activePromptScope == 0 {
            promptSystemView.string = draftPDFSystemPrompt
            promptTemplateView.string = draftPDFTemplate
            promptVarsHint.stringValue = "Template ({selection}, {page_context})"
        } else {
            promptSystemView.string = draftUniversalSystemPrompt
            promptTemplateView.string = draftUniversalTemplate
            promptVarsHint.stringValue = "Template ({selection})"
        }
        isUpdatingPromptViews = false
    }

    public func textDidChange(_ notification: Notification) {
        guard !isUpdatingPromptViews else { return }
        saveActivePromptViewToDraft()
        if activePromptScope == 0 && config.activePresetId != "custom" {
            config.activePresetId = "custom"
            if let customIdx = AppConfig.presets.firstIndex(where: { $0.id == "custom" }) {
                presetPopUp.selectItem(at: customIdx)
                presetDescriptionLabel.stringValue = AppConfig.presets[customIdx].description
            }
        }
    }

    @objc private func presetChanged() {
        guard let item = presetPopUp.selectedItem, let repr = item.representedObject as? String else { return }
        config.activePresetId = repr
        if let p = AppConfig.presets.first(where: { $0.id == repr }) {
            presetDescriptionLabel.stringValue = p.description
            if repr == "custom" {
                draftPDFSystemPrompt = config.customSystemPrompt
                draftPDFTemplate = config.customPromptTemplate
            } else {
                draftPDFSystemPrompt = p.systemPrompt
                draftPDFTemplate = p.template
            }
            if activePromptScope == 0 {
                syncPromptEditorViews()
            }
        }
    }

    @objc private func resetActivePromptClicked() {
        if activePromptScope == 0 {
            if let def = AppConfig.presets.first(where: { $0.id == "concise_context" }) {
                config.activePresetId = def.id
                presetPopUp.selectItem(at: 0)
                presetDescriptionLabel.stringValue = def.description
                draftPDFSystemPrompt = def.systemPrompt
                draftPDFTemplate = def.template
            }
        } else {
            draftUniversalSystemPrompt = AppConfig.defaultFourFingerSystemPrompt
            draftUniversalTemplate = AppConfig.defaultFourFingerPromptTemplate
        }
        syncPromptEditorViews()
    }

    // MARK: - Shortcut Management & Recording
    private func populateShortcutPopUp(_ popUp: NSPopUpButton, current: ShortcutConfig, action: Selector) {
        popUp.removeAllItems()
        for p in ShortcutConfig.standardPresets {
            popUp.addItem(withTitle: p.displayString)
            popUp.lastItem?.representedObject = p
        }
        popUp.addItem(withTitle: "Custom...")
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
        if !matched, let customItem = popUp.itemArray.last {
            customItem.title = "Custom: \(current.displayString)"
            popUp.select(customItem)
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
        activeRecordingTarget == .universal ? stopRecording() : startRecording(target: .universal)
    }

    @objc private func recordClipboardClicked() {
        activeRecordingTarget == .clipboard ? stopRecording() : startRecording(target: .clipboard)
    }

    @objc private func recordContextClicked() {
        activeRecordingTarget == .context ? stopRecording() : startRecording(target: .context)
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
            recordUniversalButton.title = "Press Keys"
        } else if target == .clipboard {
            recordClipboardButton.title = "Press Keys"
        } else {
            recordContextButton.title = "Press Keys"
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
        recordUniversalButton?.title = "Record"
        recordClipboardButton?.title = "Record"
        recordContextButton?.title = "Record"
    }

    // MARK: - AI Provider & Models
    @objc private func providerChanged() {
        saveCurrentKeyToMemory()

        let idx = providerSegment.selectedSegment
        if idx >= 0 && idx < AIProvider.allCases.count {
            config.selectedProvider = AIProvider.allCases[idx]
        }

        updateKeyAndLink()
        refreshModelList()
    }

    private func updateKeyAndLink() {
        let provider = config.selectedProvider
        if provider.isCLIProvider {
            keyLabel.stringValue = "CLI Path (optional)"
            apiKeyField.isHidden = true
            apiKeyPlainField.isHidden = true
            revealKeyButton.isHidden = true
            cliPathField.isHidden = false
            cliBrowseButton.isHidden = false

            let savedPath = config.cliPaths[provider.rawValue] ?? ""
            cliPathField.stringValue = savedPath
            if let resolved = config.resolveCLIPath(for: provider) {
                cliPathField.placeholderString = "Auto-detected: \(resolved)"
                statusLabel.stringValue = "Detected at \(resolved)"
                statusLabel.textColor = NSColor.systemGreen
            } else {
                let exe = provider.cliExecutableName ?? provider.rawValue
                cliPathField.placeholderString = "Path to '\(exe)' binary..."
                statusLabel.stringValue = "'\(exe)' not found"
                statusLabel.textColor = NSColor.systemRed
            }

            getKeyLinkButton.title = "\(provider.shortDisplayName) Docs →"
            testFetchButton.title = "Detect & Refresh"
        } else {
            keyLabel.stringValue = "API Key"
            cliPathField.isHidden = true
            cliBrowseButton.isHidden = true
            revealKeyButton.isHidden = false
            apiKeyField.isHidden = isKeyRevealed
            apiKeyPlainField.isHidden = !isKeyRevealed

            let currentKey = config.apiKeys[provider.rawValue] ?? ""
            apiKeyField.stringValue = currentKey
            apiKeyPlainField.stringValue = currentKey
            getKeyLinkButton.title = "Get \(provider.shortDisplayName) API Key →"
            testFetchButton.title = "Verify & Refresh"
            statusLabel.stringValue = ""
        }
    }

    @objc private func browseCLIPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select \(config.selectedProvider.displayName) Binary"
        if panel.runModal() == .OK, let url = panel.url {
            cliPathField.stringValue = url.path
            saveCurrentKeyToMemory()
            updateKeyAndLink()
        }
    }

    @objc private func toggleKeyReveal() {
        isKeyRevealed.toggle()
        if isKeyRevealed {
            apiKeyPlainField.stringValue = apiKeyField.stringValue
            apiKeyPlainField.isHidden = false
            apiKeyField.isHidden = true
            revealKeyButton.title = "Hide"
        } else {
            apiKeyField.stringValue = apiKeyPlainField.stringValue
            apiKeyField.isHidden = false
            apiKeyPlainField.isHidden = true
            revealKeyButton.title = "Show"
        }
    }

    @objc private func openKeyPortal() {
        if let url = URL(string: config.selectedProvider.keyPortalURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveCurrentKeyToMemory() {
        let provider = config.selectedProvider
        if provider.isCLIProvider {
            let trimmed = cliPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                config.cliPaths.removeValue(forKey: provider.rawValue)
            } else {
                config.cliPaths[provider.rawValue] = trimmed
            }
        } else {
            let currentVal = isKeyRevealed ? apiKeyPlainField.stringValue : apiKeyField.stringValue
            config.apiKeys[provider.rawValue] = currentVal.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @objc private func testAndFetchModels() {
        saveCurrentKeyToMemory()
        let provider = config.selectedProvider
        let customPath = config.cliPaths[provider.rawValue]
        let key = config.currentKey()

        if provider.isCLIProvider {
            guard config.resolveCLIPath(for: provider, overridePath: customPath) != nil else {
                let exe = provider.cliExecutableName ?? provider.rawValue
                statusLabel.stringValue = "'\(exe)' not found."
                statusLabel.textColor = NSColor.systemRed
                return
            }
        } else if key.isEmpty {
            statusLabel.stringValue = "Please enter an API key first."
            statusLabel.textColor = NSColor.systemRed
            return
        }

        testFetchButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Checking..."
        statusLabel.textColor = NSColor.secondaryLabelColor

        AIService.shared.fetchModels(provider: provider, apiKey: key, cliPath: customPath) { [weak self] result in
            guard let self = self else { return }
            self.testFetchButton.isEnabled = true
            self.progressIndicator.stopAnimation(nil)

            switch result {
            case .success(let models):
                self.config.cachedModels[provider.rawValue] = models
                self.refreshModelList()
                self.refreshFallbackModelList()
                self.statusLabel.stringValue = "Ready — \(models.count) models loaded."
                self.statusLabel.textColor = NSColor.systemGreen
                self.config.save()
            case .failure(let error):
                self.statusLabel.stringValue = error.localizedDescription
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

    @objc private func fallbackToggleChanged() {
        if enableFallbackCheckbox.state == .on {
            if config.fallbackProvider == nil {
                if let repr = fallbackPopUp.selectedItem?.representedObject as? String,
                   let p = AIProvider(rawValue: repr) {
                    config.fallbackProvider = p
                } else {
                    config.fallbackProvider = .groq
                }
            }
        } else {
            config.fallbackProvider = nil
        }
        updateFallbackVisibility()
        refreshFallbackModelList()
    }

    private func updateFallbackVisibility() {
        fallbackContainer.isHidden = (enableFallbackCheckbox.state != .on)
    }

    @objc private func fallbackProviderChanged() {
        guard enableFallbackCheckbox.state == .on,
              let item = fallbackPopUp.selectedItem,
              let repr = item.representedObject as? String,
              let p = AIProvider(rawValue: repr) else { return }
        config.fallbackProvider = p
        config.fallbackModel = config.selectedModels[p.rawValue] ?? p.defaultModel
        refreshFallbackModelList()
    }

    @objc private func fallbackModelChanged() {
        if let id = fallbackModelPopUp.selectedItem?.representedObject as? String {
            config.fallbackModel = id
        }
    }

    private func refreshFallbackModelList() {
        fallbackModelPopUp.removeAllItems()
        guard enableFallbackCheckbox.state == .on,
              let fbSelected = fallbackPopUp.selectedItem?.representedObject as? String,
              let provider = AIProvider(rawValue: fbSelected) else {
            fallbackModelPopUp.isEnabled = false
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

    @objc private func checkForUpdatesFromSettings() {
        UpdateManager.shared.checkForUpdates(config: config, silentIfUpToDate: false)
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
            permissionStatusLabel.stringValue = "Accessibility: Granted"
            permissionStatusLabel.textColor = NSColor.systemGreen
            openPermissionButton.title = "Re-check"
        } else {
            permissionStatusLabel.stringValue = "Accessibility: Needed for text selection"
            permissionStatusLabel.textColor = NSColor.systemRed
            openPermissionButton.title = "Open Settings"
        }
    }

    @objc private func saveAndClose() {
        stopRecording()
        saveCurrentKeyToMemory()
        saveActivePromptViewToDraft()

        if enableFallbackCheckbox.state == .on {
            if let repr = fallbackPopUp.selectedItem?.representedObject as? String,
               let p = AIProvider(rawValue: repr) {
                config.fallbackProvider = p
                if let fbModelId = fallbackModelPopUp.selectedItem?.representedObject as? String {
                    config.fallbackModel = fbModelId
                }
            }
        } else {
            config.fallbackProvider = nil
        }

        config.enableFloatingPill = (enablePillCheckbox.state == .on)
        config.enablePageContext = (enableContextCheckbox.state == .on)

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

        config.fourFingerSystemPrompt = draftUniversalSystemPrompt
        config.fourFingerPromptTemplate = draftUniversalTemplate

        if config.activePresetId == "custom" {
            config.customSystemPrompt = draftPDFSystemPrompt
            config.customPromptTemplate = draftPDFTemplate
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
