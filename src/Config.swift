import Foundation

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

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .groq: return "Groq (Ultra Fast)"
        case .openrouter: return "OpenRouter (Claude, DeepSeek, etc.)"
        case .openai: return "OpenAI"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "openai/gpt-oss-120b"
        case .openrouter: return "anthropic/claude-3.5-sonnet"
        case .openai: return "gpt-4o"
        }
    }

    public var keyPortalURL: String {
        switch self {
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .groq: return "https://console.groq.com/keys"
        case .openrouter: return "https://openrouter.ai/keys"
        case .openai: return "https://platform.openai.com/api-keys"
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
    public var selectedModels: [String: String]
    public var cachedModels: [String: [ModelInfo]]
    public var activePresetId: String
    public var customSystemPrompt: String
    public var customPromptTemplate: String
    public var enableFloatingPill: Bool
    public var enablePageContext: Bool
    public var pillDelayMs: Int
    public var hotkeyString: String

    // Four-Finger Universal Tap & Web Lookup Settings
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
        case selectedProvider, fallbackProvider, fallbackModel, apiKeys, selectedModels, cachedModels
        case activePresetId, customSystemPrompt, customPromptTemplate
        case enableFloatingPill, enablePageContext, pillDelayMs, hotkeyString
        case enableFourFingerTap, enableInternetSearchForFourFinger, fourFingerSystemPrompt, fourFingerPromptTemplate, fourFingerHotkeyString
    }

    public init() {
        self.selectedProvider = .gemini
        self.fallbackProvider = .groq
        self.fallbackModel = "openai/gpt-oss-120b"
        self.apiKeys = [:]
        self.selectedModels = [
            AIProvider.gemini.rawValue: AIProvider.gemini.defaultModel,
            AIProvider.groq.rawValue: "openai/gpt-oss-120b",
            AIProvider.openrouter.rawValue: AIProvider.openrouter.defaultModel,
            AIProvider.openai.rawValue: AIProvider.openai.defaultModel
        ]
        self.cachedModels = [
            AIProvider.gemini.rawValue: [
                ModelInfo(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash (Fast & Recommended)"),
                ModelInfo(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"),
                ModelInfo(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash")
            ],
            AIProvider.groq.rawValue: [
                ModelInfo(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B (Ultra Fast & Smart)"),
                ModelInfo(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B"),
                ModelInfo(id: "qwen/qwen3.8-27b", name: "Qwen 3.8 27B"),
                ModelInfo(id: "groq/compound", name: "Groq Compound"),
                ModelInfo(id: "groq/compound-mini", name: "Groq Compound Mini")
            ],
            AIProvider.openrouter.rawValue: [
                ModelInfo(id: "anthropic/claude-3.5-sonnet", name: "Claude 3.5 Sonnet"),
                ModelInfo(id: "deepseek/deepseek-r1", name: "DeepSeek R1"),
                ModelInfo(id: "openai/gpt-4o", name: "GPT-4o"),
                ModelInfo(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B")
            ],
            AIProvider.openai.rawValue: [
                ModelInfo(id: "gpt-4o", name: "GPT-4o"),
                ModelInfo(id: "gpt-4o-mini", name: "GPT-4o Mini")
            ]
        ]
        self.activePresetId = "concise_context"
        self.customSystemPrompt = AppConfig.presets[0].systemPrompt
        self.customPromptTemplate = AppConfig.presets[0].template
        self.enableFloatingPill = true
        self.enablePageContext = true
        self.pillDelayMs = 300
        self.hotkeyString = "⌥ Space (Option + Space)"

        // Defaults for Four-Finger Tap & Web Lookup
        self.enableFourFingerTap = true
        self.enableInternetSearchForFourFinger = true
        self.fourFingerSystemPrompt = AppConfig.defaultFourFingerSystemPrompt
        self.fourFingerPromptTemplate = AppConfig.defaultFourFingerPromptTemplate
        self.fourFingerHotkeyString = "⌥⇧ Space (Option + Shift + Space)"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.selectedProvider = try container.decodeIfPresent(AIProvider.self, forKey: .selectedProvider) ?? .gemini
        self.fallbackProvider = try container.decodeIfPresent(AIProvider.self, forKey: .fallbackProvider) ?? .groq
        self.fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel) ?? "openai/gpt-oss-120b"
        self.apiKeys = try container.decodeIfPresent([String: String].self, forKey: .apiKeys) ?? [:]
        self.selectedModels = try container.decodeIfPresent([String: String].self, forKey: .selectedModels) ?? [:]
        self.cachedModels = try container.decodeIfPresent([String: [ModelInfo]].self, forKey: .cachedModels) ?? [:]
        self.activePresetId = try container.decodeIfPresent(String.self, forKey: .activePresetId) ?? "concise_context"
        self.customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt) ?? AppConfig.presets[0].systemPrompt
        self.customPromptTemplate = try container.decodeIfPresent(String.self, forKey: .customPromptTemplate) ?? AppConfig.presets[0].template
        self.enableFloatingPill = try container.decodeIfPresent(Bool.self, forKey: .enableFloatingPill) ?? true
        self.enablePageContext = try container.decodeIfPresent(Bool.self, forKey: .enablePageContext) ?? true
        self.pillDelayMs = try container.decodeIfPresent(Int.self, forKey: .pillDelayMs) ?? 300
        self.hotkeyString = try container.decodeIfPresent(String.self, forKey: .hotkeyString) ?? "⌥ Space (Option + Space)"

        self.enableFourFingerTap = try container.decodeIfPresent(Bool.self, forKey: .enableFourFingerTap) ?? true
        self.enableInternetSearchForFourFinger = try container.decodeIfPresent(Bool.self, forKey: .enableInternetSearchForFourFinger) ?? true
        self.fourFingerSystemPrompt = try container.decodeIfPresent(String.self, forKey: .fourFingerSystemPrompt) ?? AppConfig.defaultFourFingerSystemPrompt
        self.fourFingerPromptTemplate = try container.decodeIfPresent(String.self, forKey: .fourFingerPromptTemplate) ?? AppConfig.defaultFourFingerPromptTemplate
        self.fourFingerHotkeyString = try container.decodeIfPresent(String.self, forKey: .fourFingerHotkeyString) ?? "⌥⇧ Space (Option + Shift + Space)"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedProvider, forKey: .selectedProvider)
        try container.encodeIfPresent(fallbackProvider, forKey: .fallbackProvider)
        try container.encodeIfPresent(fallbackModel, forKey: .fallbackModel)
        try container.encode(apiKeys, forKey: .apiKeys)
        try container.encode(selectedModels, forKey: .selectedModels)
        try container.encode(cachedModels, forKey: .cachedModels)
        try container.encode(activePresetId, forKey: .activePresetId)
        try container.encode(customSystemPrompt, forKey: .customSystemPrompt)
        try container.encode(customPromptTemplate, forKey: .customPromptTemplate)
        try container.encode(enableFloatingPill, forKey: .enableFloatingPill)
        try container.encode(enablePageContext, forKey: .enablePageContext)
        try container.encode(pillDelayMs, forKey: .pillDelayMs)
        try container.encode(hotkeyString, forKey: .hotkeyString)
        try container.encode(enableFourFingerTap, forKey: .enableFourFingerTap)
        try container.encode(enableInternetSearchForFourFinger, forKey: .enableInternetSearchForFourFinger)
        try container.encode(fourFingerSystemPrompt, forKey: .fourFingerSystemPrompt)
        try container.encode(fourFingerPromptTemplate, forKey: .fourFingerPromptTemplate)
        try container.encode(fourFingerHotkeyString, forKey: .fourFingerHotkeyString)
    }

    public static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/PlatoReader")
    }

    public static var configFileURL: URL {
        return configDirectory.appendingPathComponent("config.json")
    }

    public static func load() -> AppConfig {
        let url = configFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            let fresh = AppConfig()
            fresh.save()
            return fresh
        }
        return config
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

    public func currentKey() -> String {
        let direct = apiKeys[selectedProvider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !direct.isEmpty { return direct }
        return vaultKey(for: selectedProvider)
    }

    public func currentModel() -> String {
        return selectedModels[selectedProvider.rawValue] ?? selectedProvider.defaultModel
    }

    public func fallbackKey() -> String? {
        guard let fb = fallbackProvider else { return nil }
        let direct = apiKeys[fb.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !direct.isEmpty { return direct }
        let vk = vaultKey(for: fb)
        return vk.isEmpty ? nil : vk
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
