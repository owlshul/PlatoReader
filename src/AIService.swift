import Foundation

public enum AIServiceError: LocalizedError {
    case missingApiKey(AIProvider)
    case invalidApiKey(String)
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
    public func fetchModels(provider: AIProvider, apiKey: String, completion: @escaping (Result<[ModelInfo], AIServiceError>) -> Void) {
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

    // MARK: - Generate Explanation with Automatic Fallback
    public func explain(
        selection: String,
        pageContext: String?,
        config: AppConfig,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        let primaryKey = config.currentKey()
        guard !primaryKey.isEmpty else {
            completion(.failure(.missingApiKey(config.selectedProvider)))
            return
        }

        let cleanContext = pageContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "[Page text extraction was unavailable for this document]"
        let userPrompt = config.activePromptTemplate()
            .replacingOccurrences(of: "{selection}", with: selection)
            .replacingOccurrences(of: "{page_context}", with: cleanContext)

        let systemPrompt = config.activeSystemPrompt()
        let primaryModel = config.currentModel()

        executeWithFallback(
            primaryProvider: config.selectedProvider,
            primaryModel: primaryModel,
            primaryKey: primaryKey,
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
        let primaryKey = config.currentKey().isEmpty ? (config.fallbackKey() ?? "") : config.currentKey()
        let primaryProvider = config.currentKey().isEmpty ? (config.fallbackProvider ?? config.selectedProvider) : config.selectedProvider
        let primaryModel = config.currentKey().isEmpty ? config.activeFallbackModel() : config.currentModel()

        guard !primaryKey.isEmpty else {
            completion(.failure(.missingApiKey(primaryProvider)))
            return
        }

        let userPrompt = config.activeFourFingerPromptTemplate()
            .replacingOccurrences(of: "{selection}", with: selection)
            .replacingOccurrences(of: "{internet_context}", with: "")

        let systemPrompt = config.activeFourFingerSystemPrompt()

        self.executeWithFallback(
            primaryProvider: primaryProvider,
            primaryModel: primaryModel,
            primaryKey: primaryKey,
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            enableGoogleSearch: false
        ) { result in
            switch result {
            case .success(let res):
                completion(.success((text: res.text, fallbackUsed: res.fallbackUsed)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Answer Doubt (Intellectual Cross-Questioning via Deep AI Knowledge)
    public func answerDoubt(
        selection: String,
        docName: String? = nil,
        pageContext: String?,
        previousExplanation: String,
        doubt: String,
        config: AppConfig,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        let primaryKey = config.currentKey().isEmpty ? (config.fallbackKey() ?? "") : config.currentKey()
        let primaryProvider = config.currentKey().isEmpty ? (config.fallbackProvider ?? config.selectedProvider) : config.selectedProvider
        let primaryModel = config.currentKey().isEmpty ? config.activeFallbackModel() : config.currentModel()

        guard !primaryKey.isEmpty else {
            completion(.failure(.missingApiKey(primaryProvider)))
            return
        }

        let cleanContext = pageContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let systemPrompt = """
        You are an insightful intellectual reading companion, mentor, and scholar.
        The reader has highlighted a passage in their reading and asked a follow-up doubt, question, or cross-examination.

        CRITICAL GUIDELINES:
        1. FULL INTELLECTUAL FREEDOM & WORLD KNOWLEDGE:
           Do NOT restrict yourself to only the text visible on the page. Use your deep knowledge of philosophy, history, science, literature, human nature, and broader ideas to give an intellectually rich, complete answer.
        2. EXPLAIN THE "WHY" & BROADER CONTEXT:
           If the reader asks why an author claims something, who a person is, what a concept means, or what historical/philosophical context shaped this thought, explain it thoroughly, clearly, and engagingly.
        3. GROUND IN THE PASSAGE:
           Tie your explanation back to the passage being read.
        4. FORMAT & TONE:
           Thoughtful, direct, conversational, and lucid (like an erudite conversation or a brilliant Redditor explaining complex ideas simply without dumbing them down). Avoid boilerplate openings ("Great question!", "Certainly!", etc.).
        """

        var userPrompt = """
        Original Passage:
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

        userPrompt += """

        Reader's Doubt / Cross-Question:
        \"\"\"\(doubt)\"\"\"

        Answer the reader's doubt directly, combining your intelligence and document context:
        """

        self.executeWithFallback(
            primaryProvider: primaryProvider,
            primaryModel: primaryModel,
            primaryKey: primaryKey,
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
        primaryKey: String,
        config: AppConfig,
        systemPrompt: String,
        userPrompt: String,
        enableGoogleSearch: Bool = false,
        completion: @escaping (Result<(text: String, fallbackUsed: String?), AIServiceError>) -> Void
    ) {
        var fallbacks: [(provider: AIProvider, model: String, key: String)] = []

        // 1. First priority: Configured fallback provider and model
        if let fbProvider = config.fallbackProvider, let fbKey = config.fallbackKey() {
            let primaryFbModel = config.activeFallbackModel()
            fallbacks.append((provider: fbProvider, model: primaryFbModel, key: fbKey))

            // Candidate backup models for this fallback provider (e.g. gpt-oss-120b, gpt-oss-20b for Groq)
            for m in config.candidateModels(for: fbProvider) {
                if m != primaryFbModel && !fallbacks.contains(where: { $0.provider == fbProvider && $0.model == m }) {
                    fallbacks.append((provider: fbProvider, model: m, key: fbKey))
                }
            }
        }

        // 2. Second priority: Any other provider configured with a valid API key
        for provider in AIProvider.allCases {
            if provider == primaryProvider || provider == config.fallbackProvider { continue }
            let key = config.apiKeys[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !key.isEmpty {
                for m in config.candidateModels(for: provider) {
                    if !fallbacks.contains(where: { $0.provider == provider && $0.model == m }) {
                        fallbacks.append((provider: provider, model: m, key: key))
                    }
                }
            }
        }

        // 3. Execute Primary Provider
        callProvider(
            provider: primaryProvider,
            model: primaryModel,
            apiKey: primaryKey,
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
        candidates: [(provider: AIProvider, model: String, key: String)],
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
            apiKey: current.key,
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
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        enableGoogleSearch: Bool = false,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        switch provider {
        case .gemini:
            callGemini(model: model, apiKey: apiKey, systemPrompt: systemPrompt, userPrompt: userPrompt, enableGoogleSearch: enableGoogleSearch, completion: completion)
        case .groq:
            callGroq(model: model, apiKey: apiKey, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case .openrouter:
            callOpenRouter(model: model, apiKey: apiKey, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        case .openai:
            callOpenAI(model: model, apiKey: apiKey, systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
        }
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
