import Foundation

enum ProtocolTranslator {
    static func toCanonicalOpenAIChat(from proto: MagpieProtocol, payload: [String: Any], path: String) -> [String: Any] {
        switch proto {
        case .openAIChat:
            return payload

        case .openAIResponses:
            var messages: [[String: Any]] = []
            if let instructions = payload["instructions"] as? String, !instructions.isEmpty {
                messages.append(["role": "system", "content": instructions])
            }
            if let inputStr = payload["input"] as? String {
                messages.append(["role": "user", "content": inputStr])
            } else if let inputArr = payload["input"] as? [[String: Any]] {
                for item in inputArr {
                    let role = (item["role"] as? String) ?? "user"
                    messages.append(["role": role, "content": extractText(item["content"])])
                }
            }
            return [
                "model": (payload["model"] as? String) ?? "gpt-4o",
                "messages": messages,
                "max_tokens": payload["max_output_tokens"] ?? 2048
            ]

        case .anthropicMessages:
            var messages: [[String: Any]] = []
            if let system = payload["system"] as? String, !system.isEmpty {
                messages.append(["role": "system", "content": system])
            }
            if let anthropicMsgs = payload["messages"] as? [[String: Any]] {
                for msg in anthropicMsgs {
                    let role = (msg["role"] as? String) ?? "user"
                    messages.append(["role": role, "content": extractText(msg["content"])])
                }
            }
            var out: [String: Any] = [
                "model": (payload["model"] as? String) ?? "claude-sonnet-4-5",
                "messages": messages
            ]
            if let maxTokens = payload["max_tokens"] { out["max_tokens"] = maxTokens }
            if let temp = payload["temperature"] { out["temperature"] = temp }
            return out

        case .geminiV1Beta:
            var messages: [[String: Any]] = []
            if let sysInst = payload["systemInstruction"] as? [String: Any] {
                let sysText = extractGeminiParts(sysInst["parts"])
                if !sysText.isEmpty {
                    messages.append(["role": "system", "content": sysText])
                }
            }
            if let contents = payload["contents"] as? [[String: Any]] {
                for item in contents {
                    let rawRole = (item["role"] as? String) ?? "user"
                    let role = (rawRole == "model") ? "assistant" : rawRole
                    messages.append(["role": role, "content": extractGeminiParts(item["parts"])])
                }
            }
            let modelFromPath = path
                .replacingOccurrences(of: "/v1beta/models/", with: "")
                .components(separatedBy: ":").first ?? "gemini-2.5-pro"
            return [
                "model": modelFromPath.isEmpty ? "gemini-2.5-pro" : modelFromPath,
                "messages": messages
            ]
        }
    }

    static func fromCanonicalOpenAIChat(_ chat: [String: Any], to proto: MagpieProtocol) -> [String: Any] {
        let messages = (chat["messages"] as? [[String: Any]]) ?? []
        let model = (chat["model"] as? String) ?? "claude-sonnet-4-5"

        switch proto {
        case .openAIChat:
            return chat

        case .openAIResponses:
            let inputItems: [[String: Any]] = messages.map { m in
                ["role": m["role"] ?? "user", "content": extractText(m["content"])]
            }
            return [
                "model": model,
                "input": inputItems,
                "max_output_tokens": chat["max_tokens"] ?? 2048
            ]

        case .anthropicMessages:
            var systemPrompts: [String] = []
            var converted: [[String: Any]] = []
            for m in messages {
                let role = (m["role"] as? String) ?? "user"
                let text = extractText(m["content"])
                if role == "system" {
                    systemPrompts.append(text)
                } else {
                    converted.append([
                        "role": role == "assistant" ? "assistant" : "user",
                        "content": [["type": "text", "text": text]]
                    ])
                }
            }
            var out: [String: Any] = [
                "model": model,
                "max_tokens": chat["max_tokens"] ?? 4096,
                "messages": converted
            ]
            if !systemPrompts.isEmpty {
                out["system"] = systemPrompts.joined(separator: "\n\n")
            }
            return out

        case .geminiV1Beta:
            var systemParts: [[String: Any]] = []
            var contents: [[String: Any]] = []
            for m in messages {
                let role = (m["role"] as? String) ?? "user"
                let text = extractText(m["content"])
                if role == "system" {
                    systemParts.append(["text": text])
                } else {
                    contents.append([
                        "role": role == "assistant" ? "model" : "user",
                        "parts": [["text": text]]
                    ])
                }
            }
            var out: [String: Any] = ["contents": contents]
            if !systemParts.isEmpty {
                out["systemInstruction"] = ["parts": systemParts]
            }
            return out
        }
    }

    static func responseToCanonicalOpenAIChat(from proto: MagpieProtocol, payload: [String: Any], model: String) -> [String: Any] {
        switch proto {
        case .openAIChat:
            return payload

        case .openAIResponses:
            var text = (payload["output_text"] as? String) ?? ""
            if text.isEmpty, let outputs = payload["output"] as? [[String: Any]] {
                for item in outputs {
                    if let contentArr = item["content"] as? [[String: Any]] {
                        for block in contentArr {
                            if let t = block["text"] as? String { text += t }
                        }
                    }
                }
            }
            return makeCanonicalResponse(text: text, model: model)

        case .anthropicMessages:
            let text = extractText(payload["content"])
            return makeCanonicalResponse(text: text, model: (payload["model"] as? String) ?? model)

        case .geminiV1Beta:
            var text = ""
            if let candidates = payload["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any] {
                text = extractGeminiParts(content["parts"])
            }
            return makeCanonicalResponse(text: text, model: model)
        }
    }

    static func responseFromCanonicalOpenAIChat(_ canonical: [String: Any], to proto: MagpieProtocol, model: String) -> [String: Any] {
        let text: String
        if let choices = canonical["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any] {
            text = extractText(msg["content"])
        } else {
            text = ""
        }

        switch proto {
        case .openAIChat:
            return canonical

        case .openAIResponses:
            return [
                "id": "resp_magpie_ios",
                "object": "response",
                "model": model,
                "output_text": text,
                "output": [[
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": text]]
                ]]
            ]

        case .anthropicMessages:
            return [
                "id": "msg_magpie_ios",
                "type": "message",
                "role": "assistant",
                "model": model,
                "content": [["type": "text", "text": text]],
                "stop_reason": "end_turn",
                "usage": ["input_tokens": 16, "output_tokens": 32]
            ]

        case .geminiV1Beta:
            return [
                "candidates": [[
                    "content": [
                        "role": "model",
                        "parts": [["text": text]]
                    ],
                    "finishReason": "STOP"
                ]]
            ]
        }
    }

    static func makeCanonicalResponse(text: String, model: String) -> [String: Any] {
        [
            "id": "chatcmpl-magpie-ios",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": text],
                "finish_reason": "stop"
            ]]
        ]
    }

    private static func extractText(_ value: Any?) -> String {
        if let str = value as? String { return str }
        if let arr = value as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private static func extractGeminiParts(_ value: Any?) -> String {
        guard let parts = value as? [[String: Any]] else { return "" }
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}
