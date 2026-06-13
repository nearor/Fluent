import Foundation

/// @business_rule AI 翻译调用
/// 采用 Andrew Ng「translation-agent」反思工作流（已转述适配）：
///   1. 初翻  2. 反思(准确性/流畅度/风格/术语)  3. 按反思改进
/// 来源思路：https://github.com/andrewyng/translation-agent
/// 可在设置里切「高质量(反思)」/「快速(单次)」。
enum AIClientError: Error, LocalizedError {
    case notConfigured
    case badResponse(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没配置 API key，请先打开设置填写"
        case .badResponse(let s): return "翻译失败：\(s)"
        case .emptyResult: return "翻译返回为空"
        }
    }
}

struct AIClient {

    /// 翻译入口。
    static func translate(_ text: String) async throws -> String {
        let cfg = AppConfig.shared
        guard cfg.isConfigured else { throw AIClientError.notConfigured }

        let target = cfg.targetLang
        let native = cfg.nativeLang
        let styleDesc = styleDescription(cfg.style, lang: target)

        // 第 1 步：初翻
        let initial = try await initialTranslation(text, target: target, native: native, style: styleDesc)
        Log.write("translate[1-初翻]: \"\(initial)\"")

        if !cfg.useReflection {
            return initial
        }

        // 第 2 步：反思
        let reflection = try await reflectOnTranslation(source: text, translation: initial, target: target, style: styleDesc)
        Log.write("translate[2-反思]: \"\(reflection)\"")

        // 第 3 步：改进
        let improved = try await improveTranslation(source: text, translation: initial, reflection: reflection, target: target, native: native, style: styleDesc)
        Log.write("translate[3-改进]: \"\(improved)\"")
        return improved
    }

    // MARK: - 三步 Prompt

    private static func initialTranslation(_ text: String, target: String, native: String, style: String) async throws -> String {
        let system = "You are an expert translator helping the user compose a message."
        let prompt = """
        Translate the message below into \(target). \
        If the entire message is already written in \(target), translate it into \(native) instead. \
        You MUST actually translate — never output the original text unchanged in its source language. \
        Preserve the original meaning, intent and tone (a request stays a request, a question stays a question). \
        \(style) \
        Output ONLY the translation — no quotes, no explanations, no original text.

        MESSAGE:
        \(text)
        """
        return try await chat(system: system, user: prompt)
    }

    private static func reflectOnTranslation(source: String, translation: String, target: String, style: String) async throws -> String {
        let system = "You are an expert translator reviewing a draft translation into \(target)."
        let prompt = """
        Read the source message and its draft translation, then give specific, constructive suggestions to improve it. \
        Focus on: (1) accuracy — no additions, omissions, mistranslations, or untranslated text (the translation must be fully in \(target), never left in the source language); \
        (2) fluency & grammar — natural, idiomatic \(target) as a native speaker would actually say it, with no padding or over-elaboration, \
        and grammatically correct (e.g. a yes/no question must use a proper interrogative form such as "Do you...?", not a declarative sentence with just a question mark); \
        (3) tone & register — keep the source's tone; \(style) \
        (4) terminology — consistent, context-appropriate.
        Be concise. Output only the list of suggestions.

        SOURCE:
        \(source)

        DRAFT TRANSLATION:
        \(translation)
        """
        return try await chat(system: system, user: prompt)
    }

    private static func improveTranslation(source: String, translation: String, reflection: String, target: String, native: String, style: String) async throws -> String {
        let system = "You are an expert translation editor for \(target)."
        let prompt = """
        Improve the draft translation using the expert suggestions. \
        Keep it accurate, natural, idiomatic and grammatically correct \
        (a question must use a proper interrogative form); \(style) \
        Do not over-elaborate or add words beyond the source's meaning. \
        Output ONLY the final improved translation — no quotes, no explanations.

        SOURCE:
        \(source)

        DRAFT TRANSLATION:
        \(translation)

        EXPERT SUGGESTIONS:
        \(reflection)
        """
        return try await chat(system: system, user: prompt)
    }

    /// 风格的人类可读描述（拼进各步 prompt）。
    private static func styleDescription(_ label: String, lang: String) -> String {
        let raw = translationStyleInstruction(forLabel: label)
        guard !raw.isEmpty else { return "" }
        return raw.replacingOccurrences(of: "{LANG}", with: lang)
    }

    // MARK: - 传输层：按协议发一次 chat

    private static func chat(system: String, user: String) async throws -> String {
        let cfg = AppConfig.shared
        switch cfg.provider {
        case .openAICompatible:
            return try await callOpenAICompatible(system: system, user: user, cfg: cfg)
        case .anthropic:
            return try await callAnthropic(system: system, user: user, cfg: cfg)
        }
    }

    // MARK: - OpenAI 兼容（DeepSeek / 豆包 / 多数厂商）
    private static func callOpenAICompatible(system: String, user: String, cfg: AppConfig) async throws -> String {
        let url = endpoint(cfg.baseURL, path: "/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model": cfg.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        var mutableBody = body
        // 思考强度：DeepSeek V4 / 火山豆包等支持。仅用户显式设置时发送（default 不发，兼容其他厂商）
        // 关闭→thinking.type=disabled（两家都稳）；轻量/中等/深度→reasoning_effort（火山真分级，DeepSeek 会把 low/medium 映射为 high）
        switch cfg.thinkingMode {
        case "off", "disabled":
            mutableBody["thinking"] = ["type": "disabled"]
        case "low":
            mutableBody["reasoning_effort"] = "low"
        case "medium":
            mutableBody["reasoning_effort"] = "medium"
        case "high", "enabled":
            mutableBody["reasoning_effort"] = "high"
        default:
            break   // "default"：跟随模型默认，不发送任何思考参数
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: mutableBody)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIClientError.badResponse(String(data: data, encoding: .utf8) ?? "无法解析响应")
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIClientError.emptyResult }
        return result
    }

    // MARK: - Anthropic（Claude 原生）
    private static func callAnthropic(system: String, user: String, cfg: AppConfig) async throws -> String {
        let url = endpoint(cfg.baseURL, path: "/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model": cfg.model,
            "max_tokens": 1024,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentArr = json["content"] as? [[String: Any]],
            let first = contentArr.first,
            let text = first["text"] as? String
        else {
            throw AIClientError.badResponse(String(data: data, encoding: .utf8) ?? "无法解析响应")
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIClientError.emptyResult }
        return result
    }

    // MARK: - Helpers
    private static func endpoint(_ base: String, path: String) -> URL {
        var b = base
        if b.hasSuffix("/") { b.removeLast() }
        return URL(string: b + path) ?? URL(string: "https://api.deepseek.com/v1\(path)")!
    }

    private static func checkHTTP(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIClientError.badResponse("HTTP \(http.statusCode) - \(msg)")
        }
    }
}
