# Changelog

本项目版本变更记录。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 风格，
版本号遵循语义化版本（当前处于 0.x，主功能按 Phase 迭代）。

每个版本对应一个 git tag 和一个 GitHub Release。开发流水账见 Obsidian
`20_Areas/工作日志/agent 工作日志/`，项目档案见 `10_Projects/Scoot/`。

## [Unreleased]

## [0.6.1] - 2026-08-06
### Fixed
- `scoot rename --name` 现在校验新名必须是**纯文件名**：拒绝包含路径分隔符 `/` 或为空 /
  `.` / `..` 的输入（此前 `--name ../x` 会被 `MoveEngine.rename` 解析到文件所在目录之外，
  可能把文件写出目标目录）。纯函数 `validatedBasename` 便于单测。
- `scoot slim` 不再**静默丢弃**不支持的文件：不支持的输入会作为 `errors` 项报告
  （`不支持的文件类型: .xxx`），而不是被过滤掉、只在"全部不支持"时才报一句笼统错误。
  混合输入时支持的照压、不支持的逐个列出。
- `scoot slim -q` 非法质量值提前给出明确错误（`high | balanced | extreme`），
  不再把非法值透传给底层引擎产生费解的输出。
### Changed
- 版本号 → 0.6.1（`CFBundleShortVersionString` 0.6.1 / `CFBundleVersion` 8）。

## [0.6.0] - 2026-08-05
### Added
- 新增命令行接口 `scoot`（可执行 target `ScootCLI`，安装后拷贝为 `scoot`），与菜单栏 GUI
  共享同一份状态文件（`destinations.json` / `sources.json` / `history.jsonl`），供 Claude Code /
  OpenClaw 等 agent 及用户本人从终端驱动文件分类。直接复用 `ScootCore`，未重复实现业务逻辑。
  子命令：`dest list/add/remove`、`src list/add/use`、`list [<source>]`、
  `move <file>... --to <dest>`、`rename <file> --name <newName>`、
  `slim <file>... [-q high|balanced|extreme]`、`log [-n N]`、`capabilities`。
- `--json` agent 契约（对齐 slim 的 CLI）：加了它 stdout 只输出一个 JSON 对象，人类文本走别处；
  退出码 0 成功、1 为已处理错误（`{"error":...}`）；`move`/`slim` 支持部分成功不算失败。
  `scoot capabilities`（恒定 JSON）/ `scoot --capabilities` / `scoot --version` 供 agent 自发现。
- `ScootCore/SlimService.locateBinary` 新增 PATH 查找：bundle Resources → `SCOOT_SLIM_BIN` →
  扫描 `PATH` 找 `slim`（不 shell out 到 `which`） → 开发期兜底路径。任何用 slim 自带
  `install.sh`（pipx）装过 slim 的 Mac，`scoot slim` 都能直接工作。
- `scripts/install.sh`：源码构建安装器（`curl | bash` 或从 clone 里跑），检测 CLT、
  clone/更新仓库、尽力装 slim、`make app` 构建、把 CLI 装到 `~/.local/bin/scoot`、
  把 `.app` 装到 `/Applications`。`Makefile` 新增 `cli` / `install-cli` target。
- `docs/SPEC-cli.md`：CLI 命令面 + 每个子命令的 JSON 形状文档。`AGENTS.md`：agent 调用指南。
### Changed
- `scripts/build-app.sh`：slim 二进制内嵌改为可选——找不到 `SLIM_BIN` 时打印警告并跳过内嵌
  （而不是 `exit 1`），运行时退到 PATH 查找；`.app` 仍然能在没有冻结 slim 二进制的全新 Mac 上构建。
- `CFBundleShortVersionString` → `0.6.0`，`CFBundleVersion` → `7`。

## [0.5.1] - 2026-08-04
### Fixed
- 可见性修复：此前为纯菜单栏 App（`LSUIElement`），双击后无 Dock 图标、无窗口，
  只有顶栏一个小图标，易被当成没启动。现在启动即打开主窗口（自定义 `MenuBarExtra`
  label 挂 launch `.task` 调 `openWindow(id:"main")`），`MainWindowObserverView`
  随即把进程升为 `.regular`（出 Dock 图标）；关闭窗口后回落到菜单栏常驻。
### Added
- 应用图标 `AppIcon.icns`（文档滑入托盘的蓝紫方角图），并设 `CFBundleIconFile`。

## [0.5.0] - 2026-08-04
### Added
- Phase 4：内置 `slim` 压缩。底栏「🗜 瘦身」菜单（高质量/均衡/极限），选中
  PDF/PPTX/图片即就地生成 `_slim` 副本。
- `ScootCore/SlimService`：子进程调用内置的冻结 `slim --json` 二进制，纯函数
  `parseResult` 便于单测，二进制发现（Bundle → env → dev 兜底），可取消，
  Swift 6 严格并发安全，stderr 走 `nullDevice` 防管道死锁。
- `build-app.sh` 把 `slim` 冻结二进制嵌入 `Contents/Resources/` 并先签内嵌再签 app。
- 15 个新 swift-testing 用例（含真实二进制集成测试）；`docs/SPEC-phase4-slim.md`。

## [0.4.0] - 2026-07-17
### Added
- Phase 3：AI 归档建议 + 批量智能重命名。Anthropic 薄 adapter，只传文件名，
  预览确认后执行。
### Note
- 当时状态为「交付待验收」，未单独发 Release；本 tag 为事后回填，保持版本线连续。

## [0.3.0] - 2026-07-17
### Added
- Phase 2：全局快捷键（⌥⇧S，可改）、多源文件夹切换（`sources.json` + 旧设置迁移）。

## [0.2.0] - 2026-07-16
### Added
- Phase 1 验收版：三步状态条、双栏标题、操作日志（JSONL 持久化）、主窗口。
### Fixed
- NSOpenPanel 失焦灰度 bug；移动后闪退（Swift 6 DispatchSource 回调 MainActor 隔离）。

## [0.1.0] - 2026-07-10
### Added
- Phase 1 MVP：菜单栏面板、源文件夹监控、目标网格、点击/拖拽移动、重名序号、撤销栈。

[Unreleased]: https://github.com/taokuntao-a11y/scoot/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.6.1
[0.6.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.6.0
[0.5.1]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.5.1
[0.5.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.5.0
[0.4.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.4.0
[0.3.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.3.0
[0.2.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.2.0
[0.1.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.1.0
