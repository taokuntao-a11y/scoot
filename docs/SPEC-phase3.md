# SPEC — Phase 3 智能层（v0.4.0）

范围：LLM 归档目标建议（AI 分拣）+ 批量智能重命名。
原则：薄 adapter（缝合匠），只传**文件名**不传文件内容；一切 AI 操作先预览确认再执行。

## 3.0 AI 配置

### 存储

- API Key → **Keychain**（generic password，service `com.scoot.app`，account `anthropic-api-key`），严禁进 UserDefaults / 代码 / 仓库
- Base URL（默认 `https://api.anthropic.com`）、模型名（默认 `claude-haiku-4-5`）→ UserDefaults
- `AIConfigStore`（@MainActor ObservableObject，Scoot target）：@Published baseURL / model / hasKey；setKey/clearKey 走 KeychainHelper

### 设置 UI

- 现 ShortcutSettingsView 扩成 `SettingsView`：上节"快捷键"（原 Recorder），下节"AI 配置"：
  - SecureField 粘贴 API Key（保存后显示"已配置 ●●●●"+ 清除按钮）
  - Base URL、模型名 TextField（留空恢复默认）
  - 说明文字：「AI 功能只发送文件名和目标文件夹名，不读取文件内容」

## 3.1 LLM adapter（ScootCore，零第三方依赖）

```swift
public protocol LLMService: Sendable {
    func complete(system: String, user: String) async throws -> String
}
public struct AnthropicClient: LLMService { /* URLSession + Messages API */ }
```

- POST `{baseURL}/v1/messages`，headers：`x-api-key`、`anthropic-version: 2023-06-01`
- body：model、max_tokens 2048、temperature 0、system、单条 user message
- 超时 60s；非 2xx 抛带 status + body 摘要的 error（`LLMError`）
- 响应取 `content[0].text`

### Suggester 层（ScootCore，可测试核心）

- `ArchiveSuggester`：输入 `[文件名]` + `[目标名]`，构造 prompt（要求返回严格 JSON `[{"file":...,"dest":目标名或null}]`），解析容错（剥 ```json fence），丢弃 dest 不在目标列表内的项
- `RenameSuggester`：输入 `[文件名]`，要求返回 `[{"file":...,"new_name":...}]`，命名风格：语义清晰、保留原扩展名、无 `/:` 等非法字符、不超 80 字符
  - 解析后强制校验：扩展名不符 → 用原扩展名替换；含路径分隔符/空名/重名 → 丢弃该项
- prompt 全中文说明文件语境（下载文件夹分拣场景）
- 单元测试用 mock LLMService：prompt 含全部输入、JSON 解析、fence 剥离、非法项过滤、扩展名强制保留

## 3.2 AI 分拣（归档建议）

- 入口：底栏新增「✨ AI 分拣」按钮——有选中文件时对选中项，无选中时对当前列表全部（上限 30 个）；目标数 < 1 或未配 key 时点击弹设置 popover
- 流程：请求中按钮转 spinner → 结果弹 **sheet**：
  - 每行：文件名 → 建议目标（Picker 可改成任意目标）+ 勾选框；LLM 返回 null（不确定）的行默认不勾
  - 底部「移动 N 项」确认 / 取消
- 执行：按目标分组调既有 `appModel.move(items:to:)`（复用日志/撤销/完成动效；多目标 = 多个撤销批次，可接受）

## 3.3 AI 重命名

- 入口：底栏「✎ AI 重命名」按钮，需有选中文件（上限 30 个）
- sheet：每行 原名 → 新名（TextField 可编辑）+ 勾选；确认「重命名 N 项」
- 执行：`MoveEngine` 新增 `rename(_ pairs: [(url: URL, newName: String)]) -> MoveResult`：
  - 同目录 move，重名冲突复用既有序号逻辑
  - 压入**同一个撤销栈**（底栏撤销按钮统一生效），MoveLog 记录（destName 用"重命名"）
- 校验在执行前再兜底一次：非法字符、空名、与未选中文件撞名

## 通用

- 请求期间禁用两个 AI 按钮；失败走 `appModel.errorMessage`（现有红字条）
- Swift 6：AnthropicClient 为 Sendable struct；UI 侧 `Task { @MainActor ... }` 包 async 调用
- 版本 bump 0.4.0（CFBundleVersion 4）

## 测试

- Suggester：prompt 构造、JSON/fence 解析、非法 dest 过滤、扩展名强制、重名丢弃
- MoveEngine.rename：基本重命名、冲突序号、撤销恢复原名、与 move 混合撤销顺序
- 不测真网络（AnthropicClient 不写单测，靠验收实测）

## 验收清单

1. 设置里粘贴 API Key（可填中转 Base URL），显示已配置；重启保留；`strings` 查 app 二进制不含 key
2. 选几个文件点「AI 分拣」→ sheet 给出合理目标建议，可改可去勾，确认后文件移动、日志记录、可撤销
3. 无选中时「AI 分拣」对整个列表生效
4. 「AI 重命名」→ sheet 预览新名可编辑，确认后重命名生效、扩展名不变、可撤销
5. 未配 key 点 AI 按钮 → 引导到设置而不是报错
6. 断网/错 key → 红字错误提示，UI 不卡死
7. `swift test` 全绿
