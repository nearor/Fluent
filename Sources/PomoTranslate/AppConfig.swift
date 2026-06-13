import Foundation
import AppKit

/// @entity_relationship 翻译配置
/// 用户可配置的 AI 服务参数，全部存在本机 UserDefaults，不上传任何服务器。
/// 支持两种协议：OpenAI 兼容（DeepSeek / 豆包 / 多数厂商）和 Anthropic（Claude 原生）。
enum AIProvider: String, CaseIterable {
    case openAICompatible   // DeepSeek、豆包、Kimi、以及任何 OpenAI 兼容端点
    case anthropic          // Claude 原生 /v1/messages

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容 (DeepSeek/豆包等)"
        case .anthropic: return "Anthropic (Claude)"
        }
    }
}

/// 支持的语言：label 用于界面下拉显示，name 用于发给 AI。
struct AppLanguage {
    let label: String
    let name: String
}

let supportedLanguages: [AppLanguage] = [
    AppLanguage(label: "中文",     name: "Chinese"),
    AppLanguage(label: "英语",     name: "English"),
    AppLanguage(label: "日语",     name: "Japanese"),
    AppLanguage(label: "韩语",     name: "Korean"),
    AppLanguage(label: "西班牙语", name: "Spanish"),
    AppLanguage(label: "德语",     name: "German"),
    AppLanguage(label: "法语",     name: "French"),
]

func languageLabel(forName name: String) -> String {
    supportedLanguages.first { $0.name == name }?.label ?? name
}

/// 翻译风格：label 用于界面下拉，instruction 是拼进 prompt 的英文指令（空=不加）。
struct TranslationStyle {
    let label: String
    let instruction: String
}

let translationStyles: [TranslationStyle] = [
    TranslationStyle(label: "默认", instruction: ""),
    TranslationStyle(label: "商务风", instruction: "Use a professional, polished, business-appropriate register, following the formal business conventions native to {LANG} (e.g. honorifics/keigo for Japanese, formal register for other languages)."),
    TranslationStyle(label: "口语风", instruction: "Use a casual, natural, conversational and colloquial register, the way native {LANG} speakers actually talk in daily life."),
    TranslationStyle(label: "学术风", instruction: "Use a formal, rigorous, academic register with precise terminology, following {LANG} academic writing conventions."),
]

func translationStyleInstruction(forLabel label: String) -> String {
    translationStyles.first { $0.label == label }?.instruction ?? ""
}

/// @entity_relationship 厂商预设
/// 把"协议 + baseURL + 模型列表 + 是否支持思考"打包成一个厂商选项。
struct ProviderPreset {
    let label: String          // UI 显示名（也作为持久化标识）
    let protocolType: AIProvider
    let baseURL: String        // 自动填入；自定义为空
    let modelHint: String      // 模型框占位提示
    let models: [String]       // 常见模型下拉列表（可手填覆盖，应对更新）
    let supportsThinking: Bool // 是否显示"思考强度"（目前 DeepSeek / 火山）
    let isCustom: Bool         // 自定义：协议/地址可手填，思考开关也显示
}

let providerPresets: [ProviderPreset] = [
    ProviderPreset(label: "DeepSeek", protocolType: .openAICompatible,
                   baseURL: "https://api.deepseek.com/v1",
                   modelHint: "可下拉选或手填",
                   models: ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner"],
                   supportsThinking: true, isCustom: false),
    ProviderPreset(label: "火山方舟（豆包）", protocolType: .openAICompatible,
                   baseURL: "https://ark.cn-beijing.volces.com/api/v3",
                   modelHint: "模型ID 或接入点ID ep-xxxx",
                   models: ["deepseek-v4-flash-260425", "deepseek-v4-pro-260425",
                            "doubao-seed-1-6-250615", "doubao-seed-2-0-pro-260215",
                            "doubao-seed-2-0-lite-260215"],
                   supportsThinking: true, isCustom: false),
    ProviderPreset(label: "Kimi（Moonshot）", protocolType: .openAICompatible,
                   baseURL: "https://api.moonshot.cn/v1",
                   modelHint: "可下拉选或手填",
                   models: ["kimi-k2.6", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"],
                   supportsThinking: false, isCustom: false),
    ProviderPreset(label: "阿里云通义（百炼）", protocolType: .openAICompatible,
                   baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                   modelHint: "可下拉选或手填",
                   models: ["qwen-plus", "qwen-max", "qwen-turbo", "qwen-mt-plus"],
                   supportsThinking: false, isCustom: false),
    ProviderPreset(label: "Claude（Anthropic）", protocolType: .anthropic,
                   baseURL: "https://api.anthropic.com/v1",
                   modelHint: "可下拉选或手填",
                   models: ["claude-sonnet-4-6", "claude-opus-4-8", "claude-haiku-4-5-20251001"],
                   supportsThinking: false, isCustom: false),
    ProviderPreset(label: "自定义", protocolType: .openAICompatible,
                   baseURL: "", modelHint: "手动填模型名",
                   models: [], supportsThinking: true, isCustom: true),
]

/// @business_rule 配置项
/// - provider:    选哪种 API 协议
/// - baseURL:     API 地址，比如 https://api.deepseek.com/v1
/// - apiKey:      用户自己的 key（本机存储）
/// - model:       模型名，比如 deepseek-chat / claude-3-5-sonnet-20241022
/// - targetLang:  目标语言，默认英语
/// - systemPrompt:翻译系统提示词，用户可自定义语气（商务/口语等）
final class AppConfig {
    static let shared = AppConfig()
    private let d = UserDefaults.standard

    private enum Key {
        static let provider = "provider"
        static let baseURL = "baseURL"
        static let apiKey = "apiKey"
        static let model = "model"
        static let targetLang = "targetLang"
    }

    var provider: AIProvider {
        get { AIProvider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .openAICompatible }
        set { d.set(newValue.rawValue, forKey: Key.provider) }
    }

    var baseURL: String {
        get { d.string(forKey: Key.baseURL) ?? "https://api.deepseek.com/v1" }
        set { d.set(newValue, forKey: Key.baseURL) }
    }

    var apiKey: String {
        get { d.string(forKey: Key.apiKey) ?? "" }
        set { d.set(newValue, forKey: Key.apiKey) }
    }

    var model: String {
        get { d.string(forKey: Key.model) ?? "deepseek-chat" }
        set { d.set(newValue, forKey: Key.model) }
    }

    /// 外语方向（存语言 name，如 "English"）
    var targetLang: String {
        get {
            let v = d.string(forKey: Key.targetLang) ?? ""
            return v.isEmpty ? "English" : v
        }
        set { d.set(newValue, forKey: Key.targetLang) }
    }

    /// 母语方向（存语言 name，如 "Chinese"）
    var nativeLang: String {
        get {
            let v = d.string(forKey: "nativeLang") ?? ""
            return v.isEmpty ? "Chinese" : v
        }
        set { d.set(newValue, forKey: "nativeLang") }
    }

    /// 额外风格要求（可选，如「商务正式语气」）。不控制翻译方向，只追加语气/风格。
    var stylePrompt: String {
        get { d.string(forKey: "stylePrompt") ?? "" }
        set { d.set(newValue, forKey: "stylePrompt") }
    }

    /// 翻译风格（存 label，如「商务风」，默认「默认」）。
    var style: String {
        get {
            let v = d.string(forKey: "style") ?? ""
            return v.isEmpty ? "默认" : v
        }
        set { d.set(newValue, forKey: "style") }
    }

    /// 翻译质量模式：true=反思工作流(高质量，3次调用)，false=快速(单次)。
    var useReflection: Bool {
        get {
            if d.object(forKey: "useReflection") == nil { return true }  // 默认高质量
            return d.bool(forKey: "useReflection")
        }
        set { d.set(newValue, forKey: "useReflection") }
    }

    /// 思考强度（仅 DeepSeek V4 / 火山豆包等支持思考的模型有效，其他厂商请保持 default）：
    /// "default"=不发送（跟随模型默认/兼容所有厂商）
    /// "off"=关闭思考（最快）  "low"=轻量  "medium"=中等  "high"=深度（最准最慢）
    var thinkingMode: String {
        get {
            let v = d.string(forKey: "thinkingMode") ?? ""
            return v.isEmpty ? "default" : v
        }
        set { d.set(newValue, forKey: "thinkingMode") }
    }

    /// 翻译快捷键 keyCode（默认 38 = J）。配合 hotkeyModifiers 使用。
    var hotkeyKeyCode: Int {
        get { d.object(forKey: "hotkeyKeyCode") == nil ? 38 : d.integer(forKey: "hotkeyKeyCode") }
        set { d.set(newValue, forKey: "hotkeyKeyCode") }
    }

    /// 翻译快捷键修饰键（存 NSEvent.ModifierFlags.rawValue，默认 ⌘⇧）。
    var hotkeyModifiers: UInt {
        get {
            if d.object(forKey: "hotkeyModifiers") == nil {
                return NSEvent.ModifierFlags([.command, .shift]).rawValue
            }
            return UInt(bitPattern: d.integer(forKey: "hotkeyModifiers"))
        }
        set { d.set(Int(bitPattern: newValue), forKey: "hotkeyModifiers") }
    }

    /// 当前选择的厂商预设（存 label）。空=按 baseURL 推断 / 自定义。
    var providerPreset: String {
        get { d.string(forKey: "providerPreset") ?? "" }
        set { d.set(newValue, forKey: "providerPreset") }
    }

    var isConfigured: Bool {
        !apiKey.isEmpty && !baseURL.isEmpty
    }

    /// 是否已完成首次引导（用户点过「完成」）。
    var onboardingDone: Bool {
        get { d.bool(forKey: "onboardingDone") }
        set { d.set(newValue, forKey: "onboardingDone") }
    }

    // MARK: - 剪贴板历史
    /// 是否启用剪贴板历史（默认开）。
    var clipboardEnabled: Bool {
        get { d.object(forKey: "clipboardEnabled") == nil ? true : d.bool(forKey: "clipboardEnabled") }
        set { d.set(newValue, forKey: "clipboardEnabled") }
    }
    /// 呼出历史面板的快捷键（默认 ⌥⌘V，避开常用的 ⇧⌘V 无格式粘贴）。
    var clipboardHotkeyKeyCode: Int {
        get { d.object(forKey: "clipHotkeyKey") == nil ? 9 : d.integer(forKey: "clipHotkeyKey") }  // 9 = V
        set { d.set(newValue, forKey: "clipHotkeyKey") }
    }
    var clipboardHotkeyModifiers: UInt {
        get {
            if d.object(forKey: "clipHotkeyMods") == nil {
                return NSEvent.ModifierFlags([.command, .option]).rawValue
            }
            return UInt(bitPattern: d.integer(forKey: "clipHotkeyMods"))
        }
        set { d.set(Int(bitPattern: newValue), forKey: "clipHotkeyMods") }
    }
    /// 历史保留条数（默认 50）。
    var clipboardHistorySize: Int {
        get { let v = d.integer(forKey: "clipHistorySize"); return v == 0 ? 50 : v }
        set { d.set(newValue, forKey: "clipHistorySize") }
    }

    // MARK: - 触发方式（统一：combo=组合键 / multitap=连击）
    // 连击的 key 取值：space / command / shift / control / option
    // 翻译触发（combo 复用 hotkeyKeyCode/Modifiers）
    var translateTriggerType: String {
        get { let v = d.string(forKey: "trTrigType") ?? ""; return v.isEmpty ? "multitap" : v }
        set { d.set(newValue, forKey: "trTrigType") }
    }
    var translateMultitapKey: String {
        get { let v = d.string(forKey: "trTapKey") ?? ""; return v.isEmpty ? "space" : v }
        set { d.set(newValue, forKey: "trTapKey") }
    }
    var translateMultitapCount: Int {
        get { let v = d.integer(forKey: "trTapCount"); return v == 0 ? 3 : v }
        set { d.set(newValue, forKey: "trTapCount") }
    }
    // 剪贴板触发（combo 复用 clipboardHotkeyKeyCode/Modifiers）
    var clipboardTriggerType: String {
        get { let v = d.string(forKey: "clTrigType") ?? ""; return v.isEmpty ? "combo" : v }
        set { d.set(newValue, forKey: "clTrigType") }
    }
    var clipboardMultitapKey: String {
        get { let v = d.string(forKey: "clTapKey") ?? ""; return v.isEmpty ? "command" : v }
        set { d.set(newValue, forKey: "clTapKey") }
    }
    var clipboardMultitapCount: Int {
        get { let v = d.integer(forKey: "clTapCount"); return v == 0 ? 2 : v }
        set { d.set(newValue, forKey: "clTapCount") }
    }

    // MARK: - 快照 / 还原
    // 用于「测试连接」：临时套用界面值测试后还原，避免覆盖用户尚未点保存的配置。
    struct Snapshot {
        let provider: AIProvider
        let baseURL: String
        let apiKey: String
        let model: String
        let targetLang: String
        let nativeLang: String
        let style: String
        let useReflection: Bool
        let thinkingMode: String
        let providerPreset: String
        let hotkeyKeyCode: Int
        let hotkeyModifiers: UInt
    }

    func makeSnapshot() -> Snapshot {
        Snapshot(provider: provider, baseURL: baseURL, apiKey: apiKey, model: model,
                 targetLang: targetLang, nativeLang: nativeLang, style: style,
                 useReflection: useReflection, thinkingMode: thinkingMode,
                 providerPreset: providerPreset,
                 hotkeyKeyCode: hotkeyKeyCode, hotkeyModifiers: hotkeyModifiers)
    }

    func restore(_ s: Snapshot) {
        provider = s.provider
        baseURL = s.baseURL
        apiKey = s.apiKey
        model = s.model
        targetLang = s.targetLang
        nativeLang = s.nativeLang
        style = s.style
        useReflection = s.useReflection
        thinkingMode = s.thinkingMode
        providerPreset = s.providerPreset
        hotkeyKeyCode = s.hotkeyKeyCode
        hotkeyModifiers = s.hotkeyModifiers
    }
}
