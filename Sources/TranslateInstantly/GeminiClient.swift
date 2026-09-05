import Foundation

enum GeminiClient {
    static let model = "gemini-3.6-flash"

    static func translate(_ text: String, apiKey: String, completion: @escaping (Result<TranslationResult, Error>) -> Void) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            completion(.failure(NSError(domain: "TranslateInstantly", code: 1)))
            return
        }

        let direction = TranslationPromptBuilder.direction(for: text)
        let prompt = TranslationPromptBuilder.prompt(for: text, direction: direction)
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "TranslateInstantly", code: 2)))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let errorInfo = json?["error"] as? [String: Any], let message = errorInfo["message"] as? String {
                    completion(.failure(NSError(domain: "Gemini", code: 3, userInfo: [NSLocalizedDescriptionKey: message])))
                    return
                }
                guard let candidates = json?["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else {
                    completion(.failure(NSError(domain: "TranslateInstantly", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected response from Gemini"])))
                    return
                }
                completion(.success(TranslationPromptBuilder.parse(text, direction: direction)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
