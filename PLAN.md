# Scoot — 快挪文件

macOS 菜单栏工具：下载文件快速分拣。左栏源文件夹（默认 ~/Downloads）最新文件，右栏自定义目标文件夹，点击或拖拽即移动。

分工：Fable（主会话）负责架构/评审/验收协调，Sonnet 4.6 coder subagent 负责代码实施。
**每个 Phase 交付后等用户验收，不自动续做下一阶段。**

## 迭代计划

### Phase 0 — 脚手架 ✅（并入 Phase 1）
- SPM 可执行目标 + build 脚本组装 .app（本机仅 CLT，无 Xcode）
- 菜单栏 MenuBarExtra 空壳跑通

### Phase 1 — MVP ✅（v0.1.0 发布，v0.2.0 验收通过 2026-07-16）
含 Phase 1.1 验收修复（NSOpenPanel 失焦灰度 bug、UX 引导动效）、Phase 1.2 UI 明晰化（三步状态条、双栏标题、操作日志、主窗口）、文件监控 MainActor 隔离闪退修复。

- SourceWatcher：监控源文件夹，最新文件倒序列表，过滤隐藏/未完成下载
- DestinationStore：目标文件夹增删，JSON 持久化
- MoveEngine：移动 + 重名自动加序号 + 撤销栈
- UI：左栏文件多选列表，右栏目标网格（点击移动 / drop target）
- 单元测试：重名处理、撤销
- 验收标准见 docs/SPEC-phase1.md

### Phase 2 — 顺手度（进行中，规格见 docs/SPEC-phase2.md）
- 全局快捷键呼出（KeyboardShortcuts + MenuBarExtraAccess，默认 ⌥⇧S）
- 多源文件夹切换（SourceStore，左栏头部下拉）
- ~~Finder 右键"发送到…"~~ → 顺延：FinderSync 扩展 target 无法用 CLT 构建，需先装完整 Xcode

### Phase 3 — 智能层（待验收后启动）
- LLM 归档目标建议（薄 adapter 调 API）
- 批量智能重命名，先预览确认再执行

## 约定
- 仓库推 GitHub 时必须 --private
- 技术栈：Swift 6 / SwiftUI，macOS 13+，无沙盒，ad-hoc 签名本地自用
