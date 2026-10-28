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

    // Four-Finger Web & Universal Tab
    private var enableFourFingerCheckbox: NSButton!
    private var enableInternetSearchCheckbox: NSButton!
    private var fourFingerSystemPromptView: NSTextView!
    private var fourFingerTemplatePromptView: NSTextView!

    // Behavior tab
    private var enablePillCheckbox: NSButton!
    private var enableContextCheckbox: NSButton!
    private var permissionStatusLabel: NSTextField!
    private var openPermissionButton: NSButton!

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

        // 3. Tab Four-Finger Tap & Web
        let fourFingerTab = NSTabViewItem(identifier: "fourfinger")
        fourFingerTab.label = "🖐️ 4-Finger Tap & Web"
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

    // MARK: - Four-Finger Universal Web Lookup Tab Creation
    private func createFourFingerTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        // 1. Header & Description
        let headerLabel = createLabel(text: "🖐️ Four-Finger Tap & Universal Web Lookup", frame: NSRect(x: 20, y: 405, width: 450, height: 22), bold: true)
        headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        view.addSubview(headerLabel)

        let descLabel = createLabel(
            text: "Highlight any word, phrase, or sentence in Chrome, Safari, or anywhere on macOS and tap 4 fingers to get its meaning and real-world context from the internet.",
            frame: NSRect(x: 20, y: 365, width: 540, height: 35),
            bold: false
        )
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = NSColor.secondaryLabelColor
        view.addSubview(descLabel)

        // 2. Gesture & Internet Checkboxes
        enableFourFingerCheckbox = NSButton(checkboxWithTitle: "Enable Four-Finger Tap gesture on trackpad", target: nil, action: nil)
        enableFourFingerCheckbox.frame = NSRect(x: 20, y: 338, width: 380, height: 20)
        view.addSubview(enableFourFingerCheckbox)

        enableInternetSearchCheckbox = NSButton(checkboxWithTitle: "Include live internet knowledge & encyclopedic research", target: nil, action: nil)
        enableInternetSearchCheckbox.frame = NSRect(x: 20, y: 314, width: 420, height: 20)
        view.addSubview(enableInternetSearchCheckbox)

        let hotkeyHint = createLabel(
            text: "💡 Shortcut alternative: ⌥⇧ Space (Option + Shift + Space) also triggers this instantly.",
            frame: NSRect(x: 20, y: 290, width: 530, height: 18),
            bold: false
        )
        hotkeyHint.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hotkeyHint.textColor = NSColor.systemBlue
        view.addSubview(hotkeyHint)

        // 3. System Prompt Section
        let sysLabel = createLabel(text: "Four-Finger System Prompt (Instructions for AI):", frame: NSRect(x: 20, y: 262, width: 450, height: 18), bold: true)
        view.addSubview(sysLabel)

        let sysScroll = NSScrollView(frame: NSRect(x: 20, y: 172, width: 540, height: 86))
        sysScroll.hasVerticalScroller = true
        sysScroll.borderType = .bezelBorder

        fourFingerSystemPromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 86))
        fourFingerSystemPromptView.autoresizingMask = [.width]
        fourFingerSystemPromptView.isRichText = false
        fourFingerSystemPromptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sysScroll.documentView = fourFingerSystemPromptView
        view.addSubview(sysScroll)

        // 4. Prompt Template Section
        let templateLabel = createLabel(text: "Four-Finger Prompt Template (Variables: {selection}, {internet_context}):", frame: NSRect(x: 20, y: 145, width: 530, height: 18), bold: true)
        view.addSubview(templateLabel)

        let templateScroll = NSScrollView(frame: NSRect(x: 20, y: 55, width: 540, height: 86))
        templateScroll.hasVerticalScroller = true
        templateScroll.borderType = .bezelBorder

        fourFingerTemplatePromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 86))
        fourFingerTemplatePromptView.autoresizingMask = [.width]
        fourFingerTemplatePromptView.isRichText = false
        fourFingerTemplatePromptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        templateScroll.documentView = fourFingerTemplatePromptView
        view.addSubview(templateScroll)

        // 5. Reset Button & Privacy Notice
        let resetBtn = NSButton(frame: NSRect(x: 20, y: 15, width: 195, height: 26))
        resetBtn.title = "🔄 Reset Prompt to Default"
        resetBtn.bezelStyle = .rounded
        resetBtn.target = self
        resetBtn.action = #selector(resetFourFingerPromptClicked)
        view.addSubview(resetBtn)

        let privacyNote = createLabel(text: "🔒 Privacy: Only highlighted text is sent. Browser window contents are never accessed.", frame: NSRect(x: 225, y: 17, width: 345, height: 22), bold: false)
        privacyNote.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        privacyNote.textColor = NSColor.secondaryLabelColor
        view.addSubview(privacyNote)

        return view
    }

    // MARK: - Behavior Tab Creation
    private func createBehaviorTabView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        enablePillCheckbox = NSButton(checkboxWithTitle: "Show floating '💡 Explain' button above selected text in Preview", target: nil, action: nil)
        enablePillCheckbox.frame = NSRect(x: 20, y: 390, width: 500, height: 24)
        view.addSubview(enablePillCheckbox)

        enableContextCheckbox = NSButton(checkboxWithTitle: "Read surrounding page context from PDF in Preview automatically", target: nil, action: nil)
        enableContextCheckbox.frame = NSRect(x: 20, y: 350, width: 500, height: 24)
        view.addSubview(enableContextCheckbox)

        let shortcutBox = NSBox(frame: NSRect(x: 20, y: 185, width: 530, height: 140))
        shortcutBox.title = "Keyboard Shortcuts & Pinning"
        let boxView = NSView(frame: shortcutBox.contentView!.bounds)

        let scDesc = createLabel(
            text: "• ⌥ Space (Option + Space): Explains highlighted text with PDF page context.\n• ⌥⇧ Space (Option + Shift + Space): Universal 4-finger web & internet lookup.\n• Trackpad: Highlight a sentence and tap 4 fingers anywhere on your Mac.\n• 📌 Pin: Keeps the card anchored at a fixed position while reading.",
            frame: NSRect(x: 12, y: 12, width: 500, height: 95),
            bold: false
        )
        scDesc.font = NSFont.systemFont(ofSize: 12)
        boxView.addSubview(scDesc)
        shortcutBox.contentView = boxView
        view.addSubview(shortcutBox)

        // Accessibility Section
        let permBox = NSBox(frame: NSRect(x: 20, y: 45, width: 530, height: 110))
        permBox.title = "macOS Accessibility Permission"
        let pView = NSView(frame: permBox.contentView!.bounds)

        permissionStatusLabel = createLabel(text: "", frame: NSRect(x: 12, y: 45, width: 300, height: 24), bold: true)
        pView.addSubview(permissionStatusLabel)

        openPermissionButton = NSButton(frame: NSRect(x: 330, y: 40, width: 170, height: 30))
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

        // Four-Finger tab values
        enableFourFingerCheckbox.state = config.enableFourFingerTap ? .on : .off
        enableInternetSearchCheckbox.state = config.enableInternetSearchForFourFinger ? .on : .off
        fourFingerSystemPromptView.string = config.activeFourFingerSystemPrompt()
        fourFingerTemplatePromptView.string = config.activeFourFingerPromptTemplate()

        enablePillCheckbox.state = config.enableFloatingPill ? .on : .off
        enableContextCheckbox.state = config.enablePageContext ? .on : .off

        updatePermissionStatus()
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
        saveCurrentKeyToMemory()

        config.enableFloatingPill = (enablePillCheckbox.state == .on)
        config.enablePageContext = (enableContextCheckbox.state == .on)

        // Save Four-Finger tab values
        config.enableFourFingerTap = (enableFourFingerCheckbox.state == .on)
        config.enableInternetSearchForFourFinger = (enableInternetSearchCheckbox.state == .on)
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
        self.window?.close()
    }
}
