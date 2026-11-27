import Foundation
import Carbon
import Cocoa

public enum GestureFingerMode: String, CaseIterable, Codable {
    case fourFingers = "four"
    case threeFingers = "three"
    case threeOrFour = "three_or_four"
    case disabled = "disabled"

    public var displayName: String {
        switch self {
        case .fourFingers: return "4 Fingers Tap (Default)"
        case .threeFingers: return "3 Fingers Tap"
        case .threeOrFour: return "3 or 4 Fingers Tap (Either)"
        case .disabled: return "Disabled (No Trackpad Gesture)"
        }
    }
}

public struct ShortcutConfig: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32 // Carbon modifiers: optionKey, shiftKey, cmdKey, controlKey
    public var displayString: String

    public init(keyCode: UInt32, modifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }

    public static let defaultUniversal = ShortcutConfig(
        keyCode: 49,
        modifiers: UInt32(optionKey | shiftKey),
        displayString: "⌥⇧ Space (Option + Shift + Space)"
    )

    public static let defaultContext = ShortcutConfig(
        keyCode: 49,
        modifiers: UInt32(optionKey),
        displayString: "⌥ Space (Option + Space)"
    )

    public static let defaultClipboard = ShortcutConfig(
        keyCode: 8, // 'C'
        modifiers: UInt32(optionKey | shiftKey),
        displayString: "⌥⇧ C (Option + Shift + C)"
    )

    public static let keyCodeNames: [UInt32: String] = [
        49: "Space",
        36: "Return",
        48: "Tab",
        53: "Escape",
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        43: ",", 47: ".", 44: "/", 41: ";", 39: "'", 33: "[", 30: "]", 42: "\\", 50: "`", 27: "-", 24: "="
    ]

    public static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    public static func formatDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var symbols: [String] = []
        var words: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { symbols.append("⌃"); words.append("Control") }
        if (modifiers & UInt32(optionKey)) != 0 { symbols.append("⌥"); words.append("Option") }
        if (modifiers & UInt32(shiftKey)) != 0 { symbols.append("⇧"); words.append("Shift") }
        if (modifiers & UInt32(cmdKey)) != 0 { symbols.append("⌘"); words.append("Command") }

        let keyName = keyCodeNames[keyCode] ?? "Key(\(keyCode))"
        words.append(keyName)
        let symStr = symbols.joined()
        let wordStr = words.joined(separator: " + ")
        if symStr.isEmpty {
            return keyName
        } else {
            return "\(symStr) \(keyName) (\(wordStr))"
        }
    }

    public func matchesNSEvent(_ event: NSEvent) -> Bool {
        guard UInt32(event.keyCode) == self.keyCode else { return false }
        let hasOpt = event.modifierFlags.contains(.option)
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmd = event.modifierFlags.contains(.command)
        let hasCtrl = event.modifierFlags.contains(.control)

        let reqOpt = (modifiers & UInt32(optionKey)) != 0
        let reqShift = (modifiers & UInt32(shiftKey)) != 0
        let reqCmd = (modifiers & UInt32(cmdKey)) != 0
        let reqCtrl = (modifiers & UInt32(controlKey)) != 0

        return hasOpt == reqOpt && hasShift == reqShift && hasCmd == reqCmd && hasCtrl == reqCtrl
    }

    public static let standardPresets: [ShortcutConfig] = [
        ShortcutConfig(keyCode: 49, modifiers: UInt32(optionKey | shiftKey), displayString: "⌥⇧ Space (Option + Shift + Space)"),
        ShortcutConfig(keyCode: 49, modifiers: UInt32(optionKey), displayString: "⌥ Space (Option + Space)"),
        ShortcutConfig(keyCode: 49, modifiers: UInt32(controlKey | optionKey), displayString: "⌃⌥ Space (Control + Option + Space)"),
        ShortcutConfig(keyCode: 49, modifiers: UInt32(cmdKey | optionKey), displayString: "⌘⌥ Space (Command + Option + Space)"),
        ShortcutConfig(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey), displayString: "⌘⇧ Space (Command + Shift + Space)"),
        ShortcutConfig(keyCode: 8, modifiers: UInt32(optionKey | shiftKey), displayString: "⌥⇧ C (Option + Shift + C)"),
        ShortcutConfig(keyCode: 8, modifiers: UInt32(cmdKey | optionKey), displayString: "⌘⌥ C (Command + Option + C)"),
        ShortcutConfig(keyCode: 8, modifiers: UInt32(controlKey | optionKey), displayString: "⌃⌥ C (Control + Option + C)"),
        ShortcutConfig(keyCode: 8, modifiers: UInt32(optionKey), displayString: "⌥ C (Option + C)"),
        ShortcutConfig(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey), displayString: "⌘⇧ C (Command + Shift + C)"),
        ShortcutConfig(keyCode: 14, modifiers: UInt32(optionKey), displayString: "⌥ E (Option + E)"),
        ShortcutConfig(keyCode: 14, modifiers: UInt32(optionKey | shiftKey), displayString: "⌥⇧ E (Option + Shift + E)"),
        ShortcutConfig(keyCode: 14, modifiers: UInt32(controlKey | optionKey), displayString: "⌃⌥ E (Control + Option + E)"),
        ShortcutConfig(keyCode: 14, modifiers: UInt32(cmdKey | shiftKey), displayString: "⌘⇧ E (Command + Shift + E)"),
        ShortcutConfig(keyCode: 2, modifiers: UInt32(optionKey), displayString: "⌥ D (Option + D)"),
        ShortcutConfig(keyCode: 2, modifiers: UInt32(optionKey | shiftKey), displayString: "⌥⇧ D (Option + Shift + D)")
    ]

    public static func fromDisplayString(_ str: String, defaultVal: ShortcutConfig) -> ShortcutConfig {
        if let found = standardPresets.first(where: { $0.displayString == str }) {
            return found
        }
        return defaultVal
    }
}

public struct ModelInfo: Codable, Equatable {
    public let id: String
    public let name: String
    public let contextLength: Int?

    public init(id: String, name: String, contextLength: Int? = nil) {
        self.id = id
        self.name = name
        self.contextLength = contextLength
    }
}

public enum AIProvider: String, CaseIterable, Codable {
    case gemini = "gemini"
    case groq = "groq"
    case openrouter = "openrouter"
    case openai = "openai"
    case opencode = "opencode"
    case antigravity = "antigravity"

    public var isCLIProvider: Bool {
        return self == .opencode || self == .antigravity
    }

    public var cliExecutableName: String? {
        switch self {
        case .opencode: return "opencode"
        case .antigravity: return "agy"
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .groq: return "Groq (Ultra Fast)"
        case .openrouter: return "OpenRouter (Claude, DeepSeek, etc.)"
        case .openai: return "OpenAI"
        case .opencode: return "OpenCode CLI"
        case .antigravity: return "Antigravity CLI (agy)"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .openai: return "OpenAI"
        case .opencode: return "OpenCode"
        case .antigravity: return "Antigravity"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "openai/gpt-oss-120b"
        case .openrouter: return "anthropic/claude-3.5-sonnet"
        case .openai: return "gpt-4o"
        case .opencode: return "default"
        case .antigravity: return "gemini-3.8-flash-high"
        }
    }

    public var keyPortalURL: String {
        switch self {
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .groq: return "https://console.groq.com/keys"
        case .openrouter: return "https://openrouter.ai/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        case .opencode: return "https://opencode.ai/docs"
        case .antigravity: return "https://antigravity.google/docs/cli/reference"
        }
    }
}

public struct PromptPreset: Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let systemPrompt: String
    public let template: String
}

public class AppConfig: Codable {
    public var selectedProvider: AIProvider
    public var fallbackProvider: AIProvider?
    public var fallbackModel: String?
    public var apiKeys: [String: String]
    public var cliPaths: [String: String]
    public var selectedModels: [String: String]
    public var cachedModels: [String: [ModelInfo]]
    public var activePresetId: String
    public var customSystemPrompt: String
    public var customPromptTemplate: String
    public var enableFloatingPill: Bool
    public var enablePageContext: Bool
    public var pillDelayMs: Int
    public var hotkeyString: String

    // Trackpad Gesture & Customizable Shortcut Settings
    public var fingerTapMode: GestureFingerMode
    public var universalShortcut: ShortcutConfig
    public var contextShortcut: ShortcutConfig
    public var clipboardShortcut: ShortcutConfig

    // Four-Finger Universal Tap & Web Lookup Settings (Maintained for full backward compatibility)
    public var enableFourFingerTap: Bool
    public var enableInternetSearchForFourFinger: Bool
    public var fourFingerSystemPrompt: String
    public var fourFingerPromptTemplate: String
    public var fourFingerHotkeyString: String

    public static let defaultFourFingerSystemPrompt = """
    You are an insightful knowledge companion and universal lookup explainer for macOS.
    When the user highlights a sentence, phrase, word, or passage anywhere on their Mac (such as in a web browser, article, or document):
    1. CLEAR MEANING: Explain what the highlighted text means in clear, precise English. Break down complex phrasing or dense terminology.
    2. CONTEXT & SIGNIFICANCE: Explain the broader real-world, intellectual, cultural, or conceptual context behind the statement, drawing on your deep knowledge.
    3. NUANCES: Unpack any idioms, implicit references, technical jargon, or literary allusions.
    4. TONE & LENGTH: Direct, engaging, and concise (typically 2 to 4 sentences or punchy bullet points). Avoid conversational filler like "Sure!" or "In this sentence...".
    """

    public static let defaultFourFingerPromptTemplate = """
    Highlighted Selection:
    \"\"\"{selection}\"\"\"

    Explain the meaning, nuance, and broader context of this highlighted selection:
    """

    public static let presets: [PromptPreset] = [
        PromptPreset(
            id: "concise_context",
            title: "📖 Short Contextual Meaning (Universal Default)",
            description: "Short, direct explanation of the sentence in this context (2-4 sentences).",
            systemPrompt: """
            You are a concise, insightful reading companion for any book, article, or document.
            When given a selected sentence and its surrounding page context:
            1. Explain what the sentence means in clear, direct English within this specific context.
            2. If there are difficult or archaic words, explain their intended meaning here.
            3. Keep the entire response short (2 to 4 sentences or brief bullet points). Avoid fluff, preambles, or lecturing.
            """,
            template: """
            Surrounding Page Context:
            \"\"\"{page_context}\"\"\"

            Selected Sentence to Explain:
            \"\"\"{selection}\"\"\"

            Provide a short, direct explanation of what this sentence means in this context:
            """
        ),
        PromptPreset(
            id: "plain_english",
            title: "💡 Simple & Plain English",
            description: "Converts dense, archaic, or complex sentences into everyday speech.",
            systemPrompt: "You are a helpful reading companion. Explain dense or difficult sentences in simple, everyday English. Keep it brief (under 3 sentences).",
            template: """
            Context:
            \"\"\"{page_context}\"\"\"

            Selected Sentence:
            \"\"\"{selection}\"\"\"

            Explain this in simple everyday English:
            """
        ),
        PromptPreset(
            id: "plato_bloom",
            title: "🏛️ Classical Philosophy & Plato (Allan Bloom)",
            description: "Deep dialectical analysis tailored to Bloom's literal translation & Greek concepts.",
            systemPrompt: """
            You are an expert scholar of classical political philosophy and Allan Bloom's literal translation of Plato's Republic.
            Unpack Bloom's literalist choices (dikaiosyne, thumos, kallipolis, techne, eidos), identify who is speaking, and clarify the dialectical point. Keep it structured and accessible.
            """,
            template: """
            Surrounding Page Context:
            \"\"\"{page_context}\"\"\"

            Selected Passage:
            \"\"\"{selection}\"\"\"

            Explain the meaning, speaker context, and philosophical terminology:
            """
        ),
        PromptPreset(
            id: "custom",
            title: "✍️ Custom Prompt",
            description: "Your own personalized instructions.",
            systemPrompt: "You are a helpful reading companion.",
            template: """
            Context:
            \"{page_context}\"

            Selection:
            \"{selection}\"

            Explain the meaning in this context:
            """
        )
    ]

    enum CodingKeys: String, CodingKey {
        case selectedProvider, fallbackProvider, fallbackModel, apiKeys, cliPaths, selectedModels, cachedModels
        case activePresetId, customSystemPrompt, customPromptTemplate
        case enableFloatingPill, enablePageContext, pillDelayMs, hotkeyString
        case fingerTapMode, universalShortcut, contextShortcut, clipboardShortcut
        case enableFourFingerTap, enableInternetSearchForFourFinger, fourFingerSystemPrompt, fourFingerPromptTemplate, fourFingerHotkeyString
    }

    public static func defaultModels(for provider: AIProvider) -> [ModelInfo] {
        switch provider {
        case .gemini:
            return [
                ModelInfo(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash (Fast & Recommended)"),
                ModelInfo(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"),
                ModelInfo(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash")
            ]
        case .groq:
            return [
                ModelInfo(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B (Ultra Fast & Smart)"),
                ModelInfo(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B"),
                ModelInfo(id: "qwen/qwen3.8-27b", name: "Qwen 3.8 27B"),
                ModelInfo(id: "groq/compound", name: "Groq Compound"),
                ModelInfo(id: "groq/compound-mini", name: "Groq Compound Mini")
            ]
        case .openrouter:
            return [
                ModelInfo(id: "anthropic/claude-3.5-sonnet", name: "Claude 3.5 Sonnet"),
                ModelInfo(id: "deepseek/deepseek-r1", name: "DeepSeek R1"),
                ModelInfo(id: "openai/gpt-4o", name: "GPT-4o"),
                ModelInfo(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B")
            ]
        case .openai:
            return [
                ModelInfo(id: "gpt-4o", name: "GPT-4o"),
                ModelInfo(id: "gpt-4o-mini", name: "GPT-4o Mini")
            ]
        case .opencode:
            return [
                ModelInfo(id: "default", name: "OpenCode Default (Auto)"),
                ModelInfo(id: "opencode/big-pickle", name: "OpenCode Big Pickle"),
                ModelInfo(id: "opencode/deepseek-v4.1-flash-free", name: "DeepSeek V4.1 Flash (Free)"),
                ModelInfo(id: "opencode/hy4-flash-free", name: "HY4 Flash (Free)")
            ]
        case .antigravity:
            return [
                ModelInfo(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High)"),
                ModelInfo(id: "gemini-4-hydrogen-high", name: "Gemini 4 Hydrogen (High)"),
                ModelInfo(id: "gemini-4-hydrogen-medium", name: "Gemini 4 Hydrogen (Medium)"),
                ModelInfo(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (Thinking)"),
                ModelInfo(id: "default", name: "Antigravity Default (Auto)")
            ]
        }
    }

    public init() {
        self.selectedProvider = .gemini
        self.fallbackProvider = .groq
        self.fallbackModel = "openai/gpt-oss-120b"
        self.apiKeys = [:]
        self.cliPaths = [:]
        self.selectedModels = [
            AIProvider.gemini.rawValue: AIProvider.gemini.defaultModel,
            AIProvider.groq.rawValue: "openai/gpt-oss-120b",
            AIProvider.openrouter.rawValue: AIProvider.openrouter.defaultModel,
            AIProvider.openai.rawValue: AIProvider.openai.defaultModel,
            AIProvider.opencode.rawValue: AIProvider.opencode.defaultModel,
            AIProvider.antigravity.rawValue: AIProvider.antigravity.defaultModel
        ]
        self.cachedModels = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map {
            ($0.rawValue, AppConfig.defaultModels(for: $0))
        })
        self.activePresetId = "concise_context"
        self.customSystemPrompt = AppConfig.presets[0].systemPrompt
        self.customPromptTemplate = AppConfig.presets[0].template
        self.enableFloatingPill = true
        self.enablePageContext = true
        self.pillDelayMs = 300
        self.hotkeyString = ShortcutConfig.defaultContext.displayString

        // Defaults for Gesture & Customizable Shortcuts
        self.fingerTapMode = .fourFingers
        self.universalShortcut = ShortcutConfig.defaultUniversal
        self.contextShortcut = ShortcutConfig.defaultContext
        self.clipboardShortcut = ShortcutConfig.defaultClipboard

        // Defaults for Four-Finger Tap & Web Lookup (Backward compatibility)
        self.enableFourFingerTap = true
        self.enableInternetSearchForFourFinger = true
        self.fourFingerSystemPrompt = AppConfig.defaultFourFingerSystemPrompt
        self.fourFingerPromptTemplate = AppConfig.defaultFourFingerPromptTemplate
        self.fourFingerHotkeyString = ShortcutConfig.defaultUniversal.displayString
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.selectedProvider = try container.decodeIfPresent(AIProvider.self, forKey: .selectedProvider) ?? .gemini
        self.fallbackProvider = try container.decodeIfPresent(AIProvider.self, forKey: .fallbackProvider) ?? .groq
        self.fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel) ?? "openai/gpt-oss-120b"
        self.apiKeys = try container.decodeIfPresent([String: String].self, forKey: .apiKeys) ?? [:]
        self.cliPaths = try container.decodeIfPresent([String: String].self, forKey: .cliPaths) ?? [:]
        self.selectedModels = try container.decodeIfPresent([String: String].self, forKey: .selectedModels) ?? [:]
        self.cachedModels = try container.decodeIfPresent([String: [ModelInfo]].self, forKey: .cachedModels) ?? [:]

        // Ensure newly added providers have defaults without overwriting any saved entries
        for provider in AIProvider.allCases {
            if self.selectedModels[provider.rawValue] == nil {
                self.selectedModels[provider.rawValue] = provider.defaultModel
            }
            if self.cachedModels[provider.rawValue]?.isEmpty ?? true {
                self.cachedModels[provider.rawValue] = AppConfig.defaultModels(for: provider)
            }
        }

        self.activePresetId = try container.decodeIfPresent(String.self, forKey: .activePresetId) ?? "concise_context"
        self.customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt) ?? AppConfig.presets[0].systemPrompt
        self.customPromptTemplate = try container.decodeIfPresent(String.self, forKey: .customPromptTemplate) ?? AppConfig.presets[0].template
        self.enableFloatingPill = try container.decodeIfPresent(Bool.self, forKey: .enableFloatingPill) ?? true
        self.enablePageContext = try container.decodeIfPresent(Bool.self, forKey: .enablePageContext) ?? true
        self.pillDelayMs = try container.decodeIfPresent(Int.self, forKey: .pillDelayMs) ?? 300
        self.hotkeyString = try container.decodeIfPresent(String.self, forKey: .hotkeyString) ?? ShortcutConfig.defaultContext.displayString

        // Decode fingerTapMode with graceful migration from enableFourFingerTap
        if let mode = try container.decodeIfPresent(GestureFingerMode.self, forKey: .fingerTapMode) {
            self.fingerTapMode = mode
        } else {
            let oldTap = try container.decodeIfPresent(Bool.self, forKey: .enableFourFingerTap) ?? true
            self.fingerTapMode = oldTap ? .fourFingers : .disabled
        }

        // Decode universalShortcut with graceful migration from fourFingerHotkeyString
        if let uSc = try container.decodeIfPresent(ShortcutConfig.self, forKey: .universalShortcut) {
            self.universalShortcut = uSc
        } else if let oldStr = try container.decodeIfPresent(String.self, forKey: .fourFingerHotkeyString), !oldStr.isEmpty {
            self.universalShortcut = ShortcutConfig.fromDisplayString(oldStr, defaultVal: .defaultUniversal)
        } else {
            self.universalShortcut = .defaultUniversal
        }

        // Decode contextShortcut with graceful migration from hotkeyString
        if let cSc = try container.decodeIfPresent(ShortcutConfig.self, forKey: .contextShortcut) {
            self.contextShortcut = cSc
        } else if let oldStr = try container.decodeIfPresent(String.self, forKey: .hotkeyString), !oldStr.isEmpty {
            self.contextShortcut = ShortcutConfig.fromDisplayString(oldStr, defaultVal: .defaultContext)
        } else {
            self.contextShortcut = .defaultContext
        }

        // Decode clipboardShortcut (safe fallback for existing users)
        self.clipboardShortcut = try container.decodeIfPresent(ShortcutConfig.self, forKey: .clipboardShortcut) ?? ShortcutConfig.defaultClipboard

        self.enableFourFingerTap = (self.fingerTapMode != .disabled)
        self.enableInternetSearchForFourFinger = try container.decodeIfPresent(Bool.self, forKey: .enableInternetSearchForFourFinger) ?? true
        self.fourFingerSystemPrompt = try container.decodeIfPresent(String.self, forKey: .fourFingerSystemPrompt) ?? AppConfig.defaultFourFingerSystemPrompt
        self.fourFingerPromptTemplate = try container.decodeIfPresent(String.self, forKey: .fourFingerPromptTemplate) ?? AppConfig.defaultFourFingerPromptTemplate
        self.fourFingerHotkeyString = self.universalShortcut.displayString
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedProvider, forKey: .selectedProvider)
        try container.encodeIfPresent(fallbackProvider, forKey: .fallbackProvider)
        try container.encodeIfPresent(fallbackModel, forKey: .fallbackModel)
        try container.encode(apiKeys, forKey: .apiKeys)
        try container.encode(cliPaths, forKey: .cliPaths)
        try container.encode(selectedModels, forKey: .selectedModels)
        try container.encode(cachedModels, forKey: .cachedModels)
        try container.encode(activePresetId, forKey: .activePresetId)
        try container.encode(customSystemPrompt, forKey: .customSystemPrompt)
        try container.encode(customPromptTemplate, forKey: .customPromptTemplate)
        try container.encode(enableFloatingPill, forKey: .enableFloatingPill)
        try container.encode(enablePageContext, forKey: .enablePageContext)
        try container.encode(pillDelayMs, forKey: .pillDelayMs)
        try container.encode(contextShortcut.displayString, forKey: .hotkeyString)
        try container.encode(fingerTapMode, forKey: .fingerTapMode)
        try container.encode(universalShortcut, forKey: .universalShortcut)
        try container.encode(contextShortcut, forKey: .contextShortcut)
        try container.encode(clipboardShortcut, forKey: .clipboardShortcut)
        try container.encode(fingerTapMode != .disabled, forKey: .enableFourFingerTap)
        try container.encode(enableInternetSearchForFourFinger, forKey: .enableInternetSearchForFourFinger)
        try container.encode(fourFingerSystemPrompt, forKey: .fourFingerSystemPrompt)
        try container.encode(fourFingerPromptTemplate, forKey: .fourFingerPromptTemplate)
        try container.encode(universalShortcut.displayString, forKey: .fourFingerHotkeyString)
    }

    public static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/PlatoReader")
    }

    public static var configFileURL: URL {
        return configDirectory.appendingPathComponent("config.json")
    }

    public static var alternateConfigFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/PlatoReader/config.json")
    }

    public static func load() -> AppConfig {
        let url = configFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }

        // Secondary fallback to Application Support if user previously placed config there
        let altUrl = alternateConfigFileURL
        if FileManager.default.fileExists(atPath: altUrl.path),
           let data = try? Data(contentsOf: altUrl),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config.save() // migrate to ~/.config/PlatoReader
            return config
        }

        let fresh = AppConfig()
        fresh.save()
        return fresh
    }

    public func save() {
        let dir = AppConfig.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: AppConfig.configFileURL)
        }
    }

    public func activeSystemPrompt() -> String {
        if activePresetId == "custom" {
            return customSystemPrompt
        }
        return AppConfig.presets.first(where: { $0.id == activePresetId })?.systemPrompt ?? customSystemPrompt
    }

    public func activePromptTemplate() -> String {
        if activePresetId == "custom" {
            return customPromptTemplate
        }
        return AppConfig.presets.first(where: { $0.id == activePresetId })?.template ?? customPromptTemplate
    }

    public func activeFourFingerSystemPrompt() -> String {
        let trimmed = fourFingerSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppConfig.defaultFourFingerSystemPrompt : trimmed
    }

    public func activeFourFingerPromptTemplate() -> String {
        let trimmed = fourFingerPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppConfig.defaultFourFingerPromptTemplate : trimmed
    }

    public func resetFourFingerPromptToDefault() {
        self.fourFingerSystemPrompt = AppConfig.defaultFourFingerSystemPrompt
        self.fourFingerPromptTemplate = AppConfig.defaultFourFingerPromptTemplate
    }

    private static var detectedCLICache: [String: String] = [:]

    public func effectiveKey(for provider: AIProvider) -> String {
        guard !provider.isCLIProvider else { return "" }
        let direct = apiKeys[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !direct.isEmpty { return direct }
        return vaultKey(for: provider)
    }

    public func resolveCLIPath(for provider: AIProvider, overridePath: String? = nil) -> String? {
        guard let exe = provider.cliExecutableName else { return nil }
        let fm = FileManager.default

        if let custom = overridePath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        if let configured = cliPaths[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !configured.isEmpty {
            let expanded = (configured as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        let home = fm.homeDirectoryForCurrentUser.path
        var candidateDirs = [
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin"
        ]
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            candidateDirs.append(contentsOf: envPath.components(separatedBy: ":").filter { !$0.isEmpty })
        }

        for dir in candidateDirs {
            let full = (dir as NSString).appendingPathComponent(exe)
            if fm.isExecutableFile(atPath: full) {
                AppConfig.detectedCLICache[exe] = full
                return full
            }
        }

        if let cached = AppConfig.detectedCLICache[exe], fm.isExecutableFile(atPath: cached) {
            return cached
        }

        // Final fallback via login shell PATH
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v \(exe)"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   fm.isExecutableFile(atPath: path) {
                    AppConfig.detectedCLICache[exe] = path
                    return path
                }
            }
        }

        return nil
    }

    public func credential(for provider: AIProvider) -> String {
        if provider.isCLIProvider {
            return resolveCLIPath(for: provider) ?? ""
        }
        return effectiveKey(for: provider)
    }

    public func isProviderReady(_ provider: AIProvider) -> Bool {
        return !credential(for: provider).isEmpty
    }

    public func hasAnyConfiguredProvider() -> Bool {
        if isProviderReady(selectedProvider) { return true }
        if let fb = fallbackProvider, isProviderReady(fb) { return true }
        return AIProvider.allCases.contains { isProviderReady($0) }
    }

    public func currentKey() -> String {
        return effectiveKey(for: selectedProvider)
    }

    public func currentModel() -> String {
        return selectedModels[selectedProvider.rawValue] ?? selectedProvider.defaultModel
    }

    public func fallbackKey() -> String? {
        guard let fb = fallbackProvider else { return nil }
        let cred = credential(for: fb)
        return cred.isEmpty ? nil : cred
    }

    public func vaultKey(for provider: AIProvider) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let vaultURLs = [
            home.appendingPathComponent("Downloads/Code Projects/Central_Auth_Vault/api_keys.env"),
            home.appendingPathComponent(".config/Central_Auth_Vault/api_keys.env")
        ]
        let keyName: String
        switch provider {
        case .gemini: keyName = "GEMINI_API_KEY"
        case .openrouter: keyName = "OPENROUTER_API_KEY"
        case .groq: keyName = "GROQ_API_KEY"
        case .openai: keyName = "OPENAI_API_KEY"
        case .opencode, .antigravity: return ""
        }

        for url in vaultURLs {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix(keyName + "=") {
                        let val = String(trimmed.dropFirst(keyName.count + 1))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
                        if !val.isEmpty { return val }
                    }
                }
            }
        }
        return ""
    }

    public func activeFallbackModel() -> String {
        if let m = fallbackModel, !m.isEmpty { return m }
        return fallbackProvider?.defaultModel ?? "openai/gpt-oss-120b"
    }

    public func candidateModels(for provider: AIProvider) -> [String] {
        var models: [String] = []
        if let sel = selectedModels[provider.rawValue], !sel.isEmpty {
            models.append(sel)
        }
        if let fb = fallbackModel, provider == fallbackProvider, !fb.isEmpty, !models.contains(fb) {
            models.append(fb)
        }
        if !models.contains(provider.defaultModel) {
            models.append(provider.defaultModel)
        }
        if let cached = cachedModels[provider.rawValue] {
            for m in cached {
                if !models.contains(m.id) {
                    models.append(m.id)
                }
            }
        }
        return models
    }
}
