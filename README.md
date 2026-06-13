# Fluent

<p align="center">
  <img src="Resources/AppIcon.iconset/icon_256x256.png" width="128" alt="Fluent" />
</p>

> 一个 macOS 菜单栏小工具：在任意输入框里 **AI 翻译** + **剪贴板历史**。
> A lightweight macOS menu bar app: inline **AI translation** in any text field, plus **clipboard history**.

原生 Swift / AppKit 编写，体积小、常驻菜单栏、不打扰。

## 功能

### 🌐 AI 翻译
- 在任意 app 的输入框里，触发后自动把内容翻译并回填。
- **双向翻译**：母语→外语；如果已经是外语，则翻回母语。
- **多厂商**（OpenAI 兼容 / Anthropic 协议）：DeepSeek、火山方舟（豆包）、Kimi、阿里云通义、Claude，或自定义。每个厂商带常见模型下拉，也可手填。
- **反思工作流**（可选高质量模式）：初翻 → 反思 → 改进，译文更地道。
- **思考强度**调节（DeepSeek V4 / 火山豆包）：关闭 / 轻量 / 中等 / 深度，平衡速度与质量。
- 翻译风格：默认 / 商务 / 口语 / 学术。

### 📋 剪贴板历史
- 自动记录复制过的**文本与图片**（系统剪贴板只留最后一条，这里补上历史）。
- 可搜索、可预览（文本看全文、图片看大图）、可单条删除。
- 选中历史项自动粘回当前输入框。
- 跳过密码类（concealed）内容；仅存内存，退出即清。

### ⌨️ 触发方式（两个功能各自可配）
- **组合键**：如 ⌘⇧J、⌥⌘V（可录制）。
- **连击**：同一个键快速连按 N 次，如「空格 ×3」「Command ×3」。

## 构建

需要 macOS 13+ 和 Swift 工具链（Xcode Command Line Tools 即可）。

```bash
./build-app.sh
```

脚本会编译通用二进制（arm64 + x86_64）、组装 `Fluent.app`、并做自签名。产物在项目根目录。

> 内部可执行文件名仍为 `PomoTranslate`（项目早期名），不影响显示名 Fluent。

## 使用

1. 打开 `Fluent.app`，到 **系统设置 > 隐私与安全性 > 辅助功能** 勾选 Fluent（全局监听 + 模拟粘贴需要）。授权后会自动重启生效。
2. 点菜单栏图标 > **设置**，选厂商、填入你自己的 API Key、选模型。
3. 在任意输入框里用触发方式（默认连击空格 ×3）翻译；用 ⌥⌘V 呼出剪贴板历史。

> API Key 存在本机 `UserDefaults`，不上传任何服务器。

## 技术说明

- 全局监听用 `CGEventTap`（keyDown + flagsChanged，后者支持修饰键连击）。
- 取字/回填走「辅助功能 API + 剪贴板模拟」双路径。
- 图标由 `tools/make-icon.swift` 生成。

## 截图

把截图放到 `docs/screenshots/` 下后即可在此显示（`settings.png` / `clipboard.png`）。

## License

MIT，见 [LICENSE](LICENSE)。
