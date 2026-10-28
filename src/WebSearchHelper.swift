import Foundation

public class WebSearchHelper {
    public static let shared = WebSearchHelper()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 4.0
        self.session = URLSession(configuration: config)
    }

    /// Asynchronously searches live internet and encyclopedia sources for information relevant to the user's doubt or highlighted text.
    public func search(query: String, subjectHint: String? = nil, completion: @escaping (String?) -> Void) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\n", with: " ")

        guard !clean.isEmpty else {
            completion(nil)
            return
        }

        var searchQuery = clean
        if let rawHint = subjectHint, !rawHint.isEmpty {
            let cleanHint = rawHint.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if clean.count < 35 && !clean.lowercased().contains(cleanHint.lowercased()) && !cleanHint.lowercased().contains("preview") && !cleanHint.lowercased().contains("chrome") && !cleanHint.lowercased().contains("safari") {
                searchQuery = "\(clean) \(cleanHint)"
            }
        }

        executeWikipediaSearch(query: searchQuery) { [weak self] result in
            if let result = result, !result.isEmpty {
                completion(result)
                return
            }

            // Fallback for long sentences: extract core substantive terms
            guard let self = self else { completion(nil); return }
            let words = clean.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 }
            let stopWords: Set<String> = [
                "this", "that", "with", "from", "were", "been", "have", "they", "them",
                "what", "when", "where", "which", "will", "would", "could", "should",
                "more", "some", "such", "than", "then", "into", "only", "also", "about",
                "there", "their", "other", "after", "first", "great", "these", "those"
            ]
            let substantive = words.filter { !stopWords.contains($0.lowercased()) }
            if substantive.count >= 2 {
                let fallbackSnippet = substantive.prefix(5).joined(separator: " ")
                self.executeWikipediaSearch(query: fallbackSnippet, completion: completion)
            } else {
                completion(nil)
            }
        }
    }

    private func executeWikipediaSearch(query: String, completion: @escaping (String?) -> Void) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&utf8=1&srlimit=2") else {
            completion(nil)
            return
        }

        var req = URLRequest(url: searchUrl)
        req.setValue("PlatoReader/1.0 (academic reading companion)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: req) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let queryObj = json["query"] as? [String: Any],
                  let searchItems = queryObj["search"] as? [[String: Any]],
                  !searchItems.isEmpty else {
                completion(nil)
                return
            }

            let group = DispatchGroup()
            var results: [String] = []
            let lock = NSLock()

            for item in searchItems.prefix(2) {
                guard let title = item["title"] as? String else { continue }
                guard let encTitle = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let sumUrl = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encTitle)") else { continue }

                group.enter()
                var sumReq = URLRequest(url: sumUrl)
                sumReq.setValue("PlatoReader/1.0 (academic reading companion)", forHTTPHeaderField: "User-Agent")

                let subTask = self.session.dataTask(with: sumReq) { (sData: Data?, _: URLResponse?, sErr: Error?) in
                    defer { group.leave() }
                    if let sData = sData, sErr == nil,
                       let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any] {
                        let desc = sJson["description"] as? String
                        let extract = sJson["extract"] as? String ?? ""

                        var entry = "• **\(title)**"
                        if let d = desc, !d.isEmpty {
                            entry += " (\(d))"
                        }
                        if !extract.isEmpty {
                            let truncated = extract.count > 350 ? String(extract.prefix(330)) + "…" : extract
                            entry += ":\n  \(truncated)"
                        }

                        lock.lock()
                        results.append(entry)
                        lock.unlock()
                    }
                }
                subTask.resume()
            }

            group.notify(queue: .global()) {
                if results.isEmpty {
                    completion(nil)
                } else {
                    let formatted = "🌐 Live Internet Knowledge & Research:\n" + results.joined(separator: "\n\n")
                    completion(formatted)
                }
            }
        }
        task.resume()
    }
}
