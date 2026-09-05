import Foundation

enum DeepSeekClient {
    static let model = "deepseek-chat"

    static func translate(_ text: String, apiKey: String, completion: @escaping (Result<TranslationResult, Error>) -> Void) {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            completion(.failure(NSError(domain: "TranslateInstantly", code: 1)))
            return
        }

        let direction = TranslationPromptBuilder.direction(for: text)
        let prompt = TranslationPromptBuilder.prompt(for: text, direction: direction)
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                    completion(.failure(NSError(domain: "DeepSeek", code: 3, userInfo: [NSLocalizedDescriptionKey: message])))
                    return
                }
                guard let choices = json?["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let text = message["content"] as? String else {
                    completion(.failure(NSError(domain: "TranslateInstantly", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected response from DeepSeek"])))
                    return
                }
                completion(.success(TranslationPromptBuilder.parse(text, direction: direction)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
