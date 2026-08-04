# Changelog

本项目版本变更记录。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 风格，
版本号遵循语义化版本（当前处于 0.x，主功能按 Phase 迭代）。

每个版本对应一个 git tag 和一个 GitHub Release。开发流水账见 Obsidian
`20_Areas/工作日志/agent 工作日志/`，项目档案见 `10_Projects/Scoot/`。

## [Unreleased]

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

[Unreleased]: https://github.com/taokuntao-a11y/scoot/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.5.1
[0.5.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.5.0
[0.4.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.4.0
[0.3.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.3.0
[0.2.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.2.0
[0.1.0]: https://github.com/taokuntao-a11y/scoot/releases/tag/v0.1.0
