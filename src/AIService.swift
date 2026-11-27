import Foundation

public enum AIServiceError: LocalizedError {
    case missingApiKey(AIProvider)
    case invalidApiKey(String)
    case cliNotInstalled(AIProvider)
    case cliError(String)
    case rateLimitExceeded
    case networkError(String)
    case parseError(String)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .missingApiKey(let provider):
            return "No API key configured for \(provider.displayName). Please open Settings and enter your key."
        case .invalidApiKey(let msg):
            return "Invalid API Key: \(msg)"
        case .cliNotInstalled(let provider):
            let bin = provider.cliExecutableName ?? provider.rawValue
            return "\(provider.displayName) binary ('\(bin)') was not found. Please install it or set its path in Preferences."
        case .cliError(let msg):
            return msg
        case .rateLimitExceeded:
            return "Rate limit reached. Please wait a moment or switch to another model/provider."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .parseError(let msg):
            return "Response format error: \(msg)"
        case .apiError(let msg):
            return msg
        }
    }
}

public class AIService {
    public static let shared = AIService()
    private let urlSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 35
        configuration.timeoutIntervalForResource = 50
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Fetch Models Dynamically
    public func fetchModels(provider: AIProvider, apiKey: String, cliPath: String? = nil, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
        if provider.isCLIProvider {
            fetchCLIModels(provider: provider, explicitPath: cliPath, completion: completion)
            return
        }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            completion(.failure(.missingApiKey(provider)))
            return
        }

        switch provider {
        case .gemini:
            fetchGeminiModels(apiKey: cleanKey, completion: completion)
        case .groq:
            fetchGroqModels(apiKey: cleanKey, completion: completion)
        case .openrouter:
            fetchOpenRouterModels(apiKey: cleanKey, completion: completion)
        case .openai:
            fetchOpenAIModels(apiKey: cleanKey, completion: completion)
        case .opencode, .antigravity:
            break
        }
    }

    private func fetchGeminiModels(apiKey: String, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            completion(.failure(.apiError("Invalid Gemini URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error.localizedDescription))) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { completion(.failure(.apiError("No response from Gemini"))) }
                return
            }

            if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                DispatchQueue.main.async { completion(.failure(.invalidApiKey("Google Gemini rejected this key (HTTP \(httpResponse.statusCode)). Please check your key at AI Studio."))) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let modelsList = json["models"] as? [[String: Any]] {
                    var resultModels: [ModelInfo] = []
                    for item in modelsList {
                        guard let name = item["name"] as? String else { continue }
                        let methods = item["supportedGenerationMethods"] as? [String] ?? []
                        if methods.contains("generateContent") {
                            let cleanId = name.replacingOccurrences(of: "models/", with: "")
                            if !cleanId.contains("embedding") && !cleanId.contains("aqa") && !cleanId.contains("imagen") {
                                let displayName = item["displayName"] as? String ?? cleanId
                                let inputTokenLimit = item["inputTokenLimit"] as? Int
                                resultModels.append(ModelInfo(id: cleanId, name: displayName, contextLength: inputTokenLimit))
                            }
                        }
                    }

                    resultModels.sort { a, b in
                        let rankA = self.geminiRank(id: a.id)
                        let rankB = self.geminiRank(id: b.id)
                        if rankA != rankB { return rankA < rankB }
                        return a.id > b.id
                    }

                    DispatchQueue.main.async { completion(.success(resultModels)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.parseError("Could not parse models list from Gemini response."))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.parseError(error.localizedDescription))) }
            }
        }.resume()
    }

    private func geminiRank(id: String) -> Int {
        if id.contains("2.5-flash") { return 1 }
        if id.contains("2.5-pro") { return 2 }
        if id.contains("2.0-flash") { return 3 }
        if id.contains("1.5-flash") { return 4 }
        if id.contains("1.5-pro") { return 5 }
        return 10
    }

    // MARK: - Groq Models
    private func fetchGroqModels(apiKey: String, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
        guard let url = URL(string: "https://api.groq.com/openai/v1/models") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error.localizedDescription))) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { completion(.failure(.apiError("No response from Groq"))) }
                return
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                DispatchQueue.main.async { completion(.failure(.invalidApiKey("Groq rejected this key. Please check console.groq.com/keys."))) }
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["data"] as? [[String: Any]] {
                    var models: [ModelInfo] = []
                    for item in list {
                        guard let id = item["id"] as? String else { continue }
                        if !id.hasPrefix("whisper") {
                            let name = id.replacingOccurrences(of: "/", with: " • ")
                            let context = item["context_window"] as? Int
                            models.append(ModelInfo(id: id, name: name, contextLength: context))
                        }
                    }
                    models.sort { $0.id < $1.id }
                    DispatchQueue.main.async { completion(.success(models)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.parseError("Unexpected Groq format"))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.parseError(error.localizedDescription))) }
            }
        }.resume()
    }

    // MARK: - OpenRouter Models
    private func fetchOpenRouterModels(apiKey: String, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error.localizedDescription))) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { completion(.failure(.apiError("No response from OpenRouter"))) }
                return
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                DispatchQueue.main.async { completion(.failure(.invalidApiKey("OpenRouter rejected this key. Please check openrouter.ai/keys."))) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataList = json["data"] as? [[String: Any]] {
                    var models: [ModelInfo] = []
                    for item in dataList {
                        if let id = item["id"] as? String, let name = item["name"] as? String {
                            let context = item["context_length"] as? Int
                            models.append(ModelInfo(id: id, name: name, contextLength: context))
                        }
                    }

                    models.sort { a, b in
                        let prioA = self.openRouterPriority(id: a.id)
                        let prioB = self.openRouterPriority(id: b.id)
                        if prioA != prioB { return prioA < prioB }
                        return a.name < b.name
                    }

                    DispatchQueue.main.async { completion(.success(models)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.parseError("Unexpected JSON format from OpenRouter"))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.parseError(error.localizedDescription))) }
            }
        }.resume()
    }

    private func openRouterPriority(id: String) -> Int {
        if id.contains("claude-3.5-sonnet") { return 1 }
        if id.contains("deepseek-r1") { return 2 }
        if id.contains("gpt-4o") { return 3 }
        if id.contains("llama-3.3-70b") { return 4 }
        if id.contains("gemini-2.0-flash") { return 5 }
        if id.contains("claude-3.7-sonnet") { return 0 }
        return 50
    }

    // MARK: - OpenAI Models
    private func fetchOpenAIModels(apiKey: String, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error.localizedDescription))) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { completion(.failure(.apiError("No response from OpenAI"))) }
                return
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                DispatchQueue.main.async { completion(.failure(.invalidApiKey("OpenAI key rejected."))) }
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["data"] as? [[String: Any]] {
                    var models: [ModelInfo] = []
                    for item in list {
                        if let id = item["id"] as? String {
                            if id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") {
                                models.append(ModelInfo(id: id, name: id))
                            }
                        }
                    }
                    models.sort { $0.id < $1.id }
                    DispatchQueue.main.async { completion(.success(models)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.parseError("Unexpected OpenAI format"))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.parseError(error.localizedDescription))) }
            }
        }.resume()
    }

    // MARK: - CLI Models Discovery (OpenCode & Antigravity)
    private func fetchCLIModels(provider: AIProvider, explicitPath: String?, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
        let tempConfig = AppConfig()
        if let custom = explicitPath, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tempConfig.cliPaths[provider.rawValue] = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let binaryPath = tempConfig.resolveCLIPath(for: provider) else {
            DispatchQueue.main.async { completion(.failure(.cliNotInstalled(provider))) }
            return
        }

        runCLIProcess(
            executablePath: binaryPath,
            arguments: ["models"],
            timeoutSeconds: 20
        ) { result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let output):
                var models: [ModelInfo] = [
                    ModelInfo(id: "default", name: "\(provider.shortDisplayName) Default (Auto)")
                ]
                let cleaned = self.stripANSI(output)
                for rawLine in cleaned.components(separatedBy: .newlines) {
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { continue }
                    if line.contains("Fetching available models") { continue }

                    if provider == .antigravity {
                        let parts = line.components(separatedBy: "\t").filter { !$0.isEmpty }
                        if parts.count >= 2 {
                            let id = parts[0].trimmingCharacters(in: .whitespaces)
                            let name = parts[1].trimmingCharacters(in: .whitespaces)
                            if !models.contains(where: { $0.id == id }) {
                                models.append(ModelInfo(id: id, name: name))
                            }
                        } else if let firstSpace = line.range(of: "\\s{2,}", options: .regularExpression) {
                            let id = String(line[..<firstSpace.lowerBound]).trimmingCharacters(in: .whitespaces)
                            let name = String(line[firstSpace.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if !id.isEmpty && !models.contains(where: { $0.id == id }) {
                                models.append(ModelInfo(id: id, name: name.isEmpty ? id : name))
                            }
                        } else if !line.contains(" ") && !models.contains(where: { $0.id == line }) {
                            models.append(ModelInfo(id: line, name: line))
                        }
                    } else if provider == .opencode {
                        // opencode models prints one model ID per line (e.g. opencode/big-pickle)
                        if !line.contains(" ") && line.contains("/") {
                            let display = line.replacingOccurrences(of: "/", with: " • ")
                            if !models.contains(where: { $0.id == line }) {
                                models.append(ModelInfo(id: line, name: display))
                            }
                        }
                    }
                }

                if models.count == 1 {
                    // Preserve known defaults if CLI returned none
                    for def in AppConfig.defaultModels(for: provider) where def.id != "default" {
                        models.append(def)
                    }
                }
                DispatchQueue.main.async { completion(.success(models)) }
            }
        }
    }

    private func resolvePrimaryExecutionTarget(config: AppConfig) -> (provider: AIProvider, model: String, credential: String)? {
        let primaryCred = config.credential(for: config.selectedProvider)
        if !primaryCred.isEmpty {
            return (config.selectedProvider, config.currentModel(), primaryCred)
        }
        if let fbProvider = config.fallbackProvider {
            let fbCred = config.credential(for: fbProvider)
            if !fbCred.isEmpty {
                return (fbProvider, config.activeFallbackModel(), fbCred)
            }
        }
        return nil
    }

    // MARK: - Generate Explanation with Automatic Fallback
    public func explain(
        selection: String,
        pageContext: String?,
        config: AppConfig,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        guard let target = resolvePrimaryExecutionTarget(config: config) else {
            if config.selectedProvider.isCLIProvider {
                completion(.failure(.cliNotInstalled(config.selectedProvider)))
            } else {
                completion(.failure(.missingApiKey(config.selectedProvider)))
            }
            return
        }

        let cleanContext = pageContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "[Page text extraction was unavailable for this document]"
        let userPrompt = config.activePromptTemplate()
            .replacingOccurrences(of: "{selection}", with: selection)
            .replacingOccurrences(of: "{page_context}", with: cleanContext)

        let systemPrompt = config.activeSystemPrompt()

        executeWithFallback(
            primaryProvider: target.provider,
            primaryModel: target.model,
            primaryCredential: target.credential,
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            completion: completion
        )
    }

    // MARK: - Four-Finger Universal Meaning (Pure AI Knowledge, Strictly Highlighted Text Only)
    public func explainFourFingerSelection(
        selection: String,
        appName: String?,
        config: AppConfig,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        guard let target = resolvePrimaryExecutionTarget(config: config) else {
            if config.selectedProvider.isCLIProvider {
                completion(.failure(.cliNotInstalled(config.selectedProvider)))
            } else {
                completion(.failure(.missingApiKey(config.selectedProvider)))
            }
            return
        }

        let userPrompt = config.activeFourFingerPromptTemplate()
            .replacingOccurrences(of: "{selection}", with: selection)
            .replacingOccurrences(of: "{internet_context}", with: "")

        let systemPrompt = config.activeFourFingerSystemPrompt()

        self.executeWithFallback(
            primaryProvider: target.provider,
            primaryModel: target.model,
            primaryCredential: target.credential,
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            enableGoogleSearch: false,
            completion: completion
        )
    }

    // MARK: - Direct Question / Pasted Input (Blank Input Box Mode)
    public func askDirectQuestion(
        question: String,
        config: AppConfig,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        guard let target = resolvePrimaryExecutionTarget(config: config) else {
            if config.selectedProvider.isCLIProvider {
                completion(.failure(.cliNotInstalled(config.selectedProvider)))
            } else {
                completion(.failure(.missingApiKey(config.selectedProvider)))
            }
            return
        }

        let systemPrompt = """
        You are PlatoReader, an insightful, crisp AI reading companion and knowledge assistant on macOS.
        The user either pasted a passage/term they want explained OR typed a direct question.
        - If it is a sentence, quote, concept, or term: explain its clear meaning, nuances, and broader context concisely (2 to 5 sentences or clean bullet points).
        - If it is a direct question or prompt: answer directly, accurately, and thoughtfully without conversational fluff ("Sure!", "Great question!", etc.).
        Use clean Markdown formatting when helpful.
        """

        let userPrompt = """
        User Input / Question:
        \"\"\"\(question)\"\"\"

        Respond directly and clearly:
        """

        self.executeWithFallback(
            primaryProvider: target.provider,
            primaryModel: target.model,
            primaryCredential: target.credential,
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            enableGoogleSearch: false,
            completion: completion
        )
    }

    // MARK: - Answer Doubt (Intellectual Cross-Questioning via Deep AI Knowledge)
    public func answerDoubt(
        selection: String,
        docName: String? = nil,
        pageContext: String?,
        previousExplanation: String,
        doubtHistory: [(question: String, answer: String)] = [],
        doubt: String,
        config: AppConfig,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        guard let target = resolvePrimaryExecutionTarget(config: config) else {
            if config.selectedProvider.isCLIProvider {
                completion(.failure(.cliNotInstalled(config.selectedProvider)))
            } else {
                completion(.failure(.missingApiKey(config.selectedProvider)))
            }
            return
        }

        let cleanContext = pageContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let systemPrompt = """
        You are an insightful intellectual reading companion, mentor, and scholar.
        The reader has highlighted a passage (or asked a question) and asked a follow-up doubt, question, or cross-examination.

        CRITICAL GUIDELINES:
        1. FULL INTELLECTUAL FREEDOM & WORLD KNOWLEDGE:
           Do NOT restrict yourself to only the text visible on the page. Use your deep knowledge of philosophy, history, science, literature, human nature, and broader ideas to give an intellectually rich, complete answer.
        2. EXPLAIN THE "WHY" & BROADER CONTEXT:
           If the reader asks why an author claims something, who a person is, what a concept means, or what historical/philosophical context shaped this thought, explain it thoroughly, clearly, and engagingly.
        3. GROUND IN THE PASSAGE:
           Tie your explanation back to the passage/question being discussed.
        4. FORMAT & TONE:
           Thoughtful, direct, conversational, and lucid. Avoid boilerplate openings ("Great question!", "Certainly!", etc.).
        """

        var userPrompt = """
        Original Passage / Topic:
        \"\"\"\(selection)\"\"\"

        Previous Explanation:
        \"\"\"\(previousExplanation)\"\"\"
        """

        if !cleanContext.isEmpty {
            userPrompt += """

            Surrounding Page Context:
            \"\"\"\(cleanContext)\"\"\"
            """
        }

        if !doubtHistory.isEmpty {
            let recent = doubtHistory.suffix(4)
            let historyText = recent.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
            userPrompt += """

            Earlier Follow-Up Discussion:
            \(historyText)
            """
        }

        userPrompt += """

        Reader's Doubt / Cross-Question:
        \"\"\"\(doubt)\"\"\"

        Answer the reader's doubt directly, combining your intelligence and context:
        """

        self.executeWithFallback(
            primaryProvider: target.provider,
            primaryModel: target.model,
            primaryCredential: target.credential,
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            enableGoogleSearch: false
        ) { result in
            switch result {
            case .success(let res):
                var text = res.text
                if let fb = res.fallbackUsed {
                    text += "\n\n*(Answered via fallback: \(fb))*"
                }
                completion(.success(text))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Resilient Multi-Tier Fallback Engine
    private func executeWithFallback(
        primaryProvider: AIProvider,
        primaryModel: String,
        primaryCredential: String,
        config: AppConfig,
        systemPrompt: String,
        userPrompt: String,
        enableGoogleSearch: Bool = false,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        var fallbacks: [(provider: AIProvider, model: String, credential: String)] = []

        // 1. First priority: Configured fallback provider and model (API or CLI)
        if let fbProvider = config.fallbackProvider, fbProvider != primaryProvider {
            let fbCred = config.credential(for: fbProvider)
            if !fbCred.isEmpty {
                let primaryFbModel = config.activeFallbackModel()
                fallbacks.append((provider: fbProvider, model: primaryFbModel, credential: fbCred))

                if !fbProvider.isCLIProvider {
                    for m in config.candidateModels(for: fbProvider) {
                        if m != primaryFbModel && !fallbacks.contains(where: { $0.provider == fbProvider && $0.model == m }) {
                            fallbacks.append((provider: fbProvider, model: m, credential: fbCred))
                        }
                    }
                }
            }
        }

        // 2. Second priority: Any other API provider configured with a valid API key
        for provider in AIProvider.allCases {
            if provider.isCLIProvider { continue }
            if provider == primaryProvider || provider == config.fallbackProvider { continue }
            let key = config.effectiveKey(for: provider)
            if !key.isEmpty {
                for m in config.candidateModels(for: provider) {
                    if !fallbacks.contains(where: { $0.provider == provider && $0.model == m }) {
                        fallbacks.append((provider: provider, model: m, credential: key))
                    }
                }
            }
        }

        // 3. Execute Primary Provider
        callProvider(
            provider: primaryProvider,
            model: primaryModel,
            credential: primaryCredential,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            enableGoogleSearch: enableGoogleSearch
        ) { [weak self] primaryResult in
            guard let self = self else { return }
            switch primaryResult {
            case .success(let text):
                completion(.success((text: text, fallbackUsed: nil)))
            case .failure(let primaryError):
                if fallbacks.isEmpty {
                    completion(.failure(primaryError))
                    return
                }

                // Iterate through the fallback chain
                self.tryFallbackChain(
                    candidates: fallbacks,
                    index: 0,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    primaryError: primaryError,
                    enableGoogleSearch: enableGoogleSearch,
                    completion: completion
                )
            }
        }
    }

    private func tryFallbackChain(
        candidates: [(provider: AIProvider, model: String, credential: String)],
        index: Int,
        systemPrompt: String,
        userPrompt: String,
        primaryError: AIServiceError,
        enableGoogleSearch: Bool = false,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        guard index < candidates.count else {
            // All fallback candidates exhausted
            completion(.failure(primaryError))
            return
        }

        let current = candidates[index]
        callProvider(
            provider: current.provider,
            model: current.model,
            credential: current.credential,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            enableGoogleSearch: (enableGoogleSearch && current.provider == .gemini)
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let text):
                let tag = "\(current.provider.displayName) (\(current.model))"
                completion(.success((text: text, fallbackUsed: tag)))
            case .failure:
                // Move to next candidate
                self.tryFallbackChain(
                    candidates: candidates,
                    index: index + 1,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    primaryError: primaryError,
                    enableGoogleSearch: enableGoogleSearch,
                    completion: completion
                )
            }
        }
    }

    // Helper dispatcher
    private func callProvider(
        provider: AIProvider,
        model: String,
        credential: String,
        systemPrompt: String,
        userPrompt: String,
        enableGoogleSearch: Bool = false,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        switch provider {
        case .gemini:
            callGemini(model: model, apiKey: credential, systemPrompt: systemPrompt, userPrompt: userPrompt, enableGoogleSearch: enableGoogleSearch, completion: completion)
        case .groq:
            callGroq(model: model, apiKey: credential, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case .openrouter:
            callOpenRouter(model: model, apiKey: credential, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case .openai:
            callOpenAI(model: model, apiKey: credential, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case .opencode:
            callOpenCodeCLI(binaryPath: credential, model: model, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case .antigravity:
            callAntigravityCLI(binaryPath: credential, model: model, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        }
    }

    // MARK: - CLI Providers (OpenCode & Antigravity)
    private func buildCLICombinedPrompt(systemPrompt: String, userPrompt: String) -> String {
        return """
        Follow these instructions carefully and reply directly with the final answer (do not inspect files or run tools):

        [Instructions]
        \(systemPrompt)

        [Request]
        \(userPrompt)
        """
    }

    private func callOpenCodeCLI(
        binaryPath: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        let prompt = buildCLICombinedPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        var args = ["run", "--format", "json", "--archived"]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty && trimmedModel != "default" {
            args.append(contentsOf: ["--model", trimmedModel])
        }
        args.append(prompt)

        runCLIProcess(executablePath: binaryPath, arguments: args, timeoutSeconds: 75) { result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let output):
                var collectedTexts: [String] = []
                var errorMessage: String? = nil

                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("{"),
                          let data = trimmed.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else { continue }

                    if type == "text",
                       let part = json["part"] as? [String: Any],
                       let text = part["text"] as? String {
                        collectedTexts.append(text)
                    } else if type == "error" {
                        if let errObj = json["error"] as? [String: Any],
                           let msg = errObj["message"] as? String {
                            errorMessage = msg
                        } else if let msg = json["message"] as? String {
                            errorMessage = msg
                        }
                    }
                }

                let joined = collectedTexts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    DispatchQueue.main.async { completion(.success(joined)) }
                } else if let errMsg = errorMessage {
                    DispatchQueue.main.async { completion(.failure(.cliError("OpenCode CLI error: \(errMsg)"))) }
                } else {
                    let fallbackText = self.stripANSI(output).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fallbackText.isEmpty {
                        DispatchQueue.main.async { completion(.success(fallbackText)) }
                    } else {
                        DispatchQueue.main.async { completion(.failure(.cliError("OpenCode CLI returned an empty response."))) }
                    }
                }
            }
        }
    }

    private func callAntigravityCLI(
        binaryPath: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        let prompt = buildCLICombinedPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        var args = [
            "--disable-slash-commands",
            "--output-format", "text",
            "--print-timeout=60s"
        ]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty && trimmedModel != "default" {
            args.append(contentsOf: ["--model", trimmedModel])
        }
        args.append("--print=\(prompt)")

        runCLIProcess(executablePath: binaryPath, arguments: args, timeoutSeconds: 75) { result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let output):
                let clean = self.stripANSI(output).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    DispatchQueue.main.async { completion(.success(clean)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.cliError("Antigravity CLI returned an empty response."))) }
                }
            }
        }
    }

    private func runCLIProcess(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            // Run inside an isolated empty sandbox directory so CLIs don't scan / or user home
            let sandboxDir = AppConfig.configDirectory.appendingPathComponent("cli_sandbox")
            try? FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
            process.currentDirectoryURL = sandboxDir

            // Ensure PATH includes common CLI locations when launched as a macOS GUI app
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let extraPaths = [
                "\(home)/.local/bin",
                "\(home)/.opencode/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin"
            ]
            let existingPath = env["PATH"] ?? ""
            env["PATH"] = (extraPaths + existingPath.components(separatedBy: ":").filter { !$0.isEmpty }).joined(separator: ":")
            env["NO_COLOR"] = "1"
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            var outData = Data()
            var errData = Data()
            let dataLock = NSLock()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    dataLock.lock()
                    outData.append(chunk)
                    dataLock.unlock()
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    dataLock.lock()
                    errData.append(chunk)
                    dataLock.unlock()
                }
            }

            let stateLock = NSLock()
            var didComplete = false

            let timeoutWork = DispatchWorkItem {
                stateLock.lock()
                if !didComplete {
                    didComplete = true
                    stateLock.unlock()
                    if process.isRunning {
                        process.terminate()
                    }
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    completion(.failure(.cliError("CLI timed out after \(Int(timeoutSeconds))s.")))
                } else {
                    stateLock.unlock()
                }
            }

            process.terminationHandler = { proc in
                timeoutWork.cancel()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                dataLock.lock()
                outData.append(remainingOut)
                errData.append(remainingErr)
                let stdoutStr = String(data: outData, encoding: .utf8) ?? ""
                let stderrStr = String(data: errData, encoding: .utf8) ?? ""
                dataLock.unlock()

                stateLock.lock()
                if didComplete {
                    stateLock.unlock()
                    return
                }
                didComplete = true
                stateLock.unlock()

                if proc.terminationStatus == 0 {
                    completion(.success(stdoutStr))
                } else {
                    let cleanErr = self.stripANSI(stderrStr.isEmpty ? stdoutStr : stderrStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    let msg = cleanErr.isEmpty ? "CLI exited with status \(proc.terminationStatus)" : cleanErr
                    completion(.failure(.cliError("CLI Error: \(msg)")))
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            do {
                try process.run()
            } catch {
                timeoutWork.cancel()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                stateLock.lock()
                if !didComplete {
                    didComplete = true
                    stateLock.unlock()
                    completion(.failure(.cliError("Failed to launch CLI: \(error.localizedDescription)")))
                } else {
                    stateLock.unlock()
                }
            }
        }
    }

    private func stripANSI(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    // MARK: - Gemini Implementation
    private func callGemini(
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        enableGoogleSearch: Bool = false,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            completion(.failure(.apiError("Invalid Gemini endpoint URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3
            ]
        ]

        if enableGoogleSearch {
            payload["tools"] = [["google_search": [:]]]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(.parseError("Failed to serialize Gemini request body")))
            return
        }
        request.httpBody = body

        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error.localizedDescription))) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { completion(.failure(.apiError("No response from Gemini"))) }
                return
            }

            if httpResponse.statusCode != 200 {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = errJson["error"] as? [String: Any],
                   let message = errorObj["message"] as? String {
                    DispatchQueue.main.async { completion(.failure(.apiError("Gemini Error (\(httpResponse.statusCode)): \(message)"))) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.apiError("Gemini returned HTTP \(httpResponse.statusCode)"))) }
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    DispatchQueue.main.async { completion(.success(text)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.parseError("Could not extract text from Gemini response"))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.parseError(error.localizedDescription))) }
            }
        }.resume()
    }

    // MARK: - Groq Implementation
    private func callGroq(
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        urlSession.dataTask(with: request) { data, response, error in
            self.handleOpenAIStyleResponse(data: data, response: response, error: error, providerName: "Groq", completion: completion)
        }.resume()
    }

    // MARK: - OpenRouter Implementation
    private func callOpenRouter(
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/platoreader", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("PlatoReader", forHTTPHeaderField: "X-Title")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        urlSession.dataTask(with: request) { data, response, error in
            self.handleOpenAIStyleResponse(data: data, response: response, error: error, providerName: "OpenRouter", completion: completion)
        }.resume()
    }

    // MARK: - OpenAI Implementation
    private func callOpenAI(
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        urlSession.dataTask(with: request) { data, response, error in
            self.handleOpenAIStyleResponse(data: data, response: response, error: error, providerName: "OpenAI", completion: completion)
        }.resume()
    }

    private func handleOpenAIStyleResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        providerName: String,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        if let error = error {
            DispatchQueue.main.async { completion(.failure(.networkError(error.localizedDescription))) }
            return
        }
        guard let httpResponse = response as? HTTPURLResponse, let data = data else {
            DispatchQueue.main.async { completion(.failure(.apiError("No response from \(providerName)"))) }
            return
        }

        if httpResponse.statusCode != 200 {
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                DispatchQueue.main.async { completion(.failure(.apiError("\(providerName) Error (\(httpResponse.statusCode)): \(msg)"))) }
            } else {
                DispatchQueue.main.async { completion(.failure(.apiError("\(providerName) returned HTTP \(httpResponse.statusCode)"))) }
            }
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                DispatchQueue.main.async { completion(.success(text)) }
            } else {
                DispatchQueue.main.async { completion(.failure(.parseError("Failed to extract completion message from \(providerName)"))) }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(.parseError(error.localizedDescription))) }
        }
    }
}
