# Scoot Phase 1.2 — UI 明晰化（架构：Fable / 实施：Sonnet coder）

验收反馈驱动：把"选中 → 目标 → 完成"的使用流程显性化，增加操作日志和主窗口入口。

## 布局线框（面板与主窗口共用 ContentView）

```
┌────────────────────────────────────────────────────┐
│   ① 选中文件 ─────── ② 点击目标 ─────── ③ 完成      │  ← StepperBar
├───────────────────────────┬────────────────────────┤
│ 选中文件  [已选 2]        │ 目标位置            [+] │  ← 双栏标题
│ ┌───────────────────────┐ │ ┌──────┐ ┌──────┐     │
│ │ 文件列表（多选）       │ │ │ 合同 │ │ 发票 │     │
│ │                       │ │ └──────┘ └──────┘     │
│ └───────────────────────┘ │                        │
├───────────────────────────┴────────────────────────┤
│ ▸ 操作日志（最近：report.pdf → 合同）              │  ← 可展开抽屉
├─────────────────────────────────────────────────────┤
│ [撤销] [⤢ 窗口打开] [源文件夹] [退出]               │  ← 底栏
└─────────────────────────────────────────────────────┘
```

## 1. StepperBar（三步状态流，顶部通栏）

三段式步骤条，用系统色和 SF Symbols，状态驱动：

| 应用状态 | ① 选中文件 | ② 点击目标 | ③ 完成 |
|---|---|---|---|
| 无选中（初始） | **高亮**（accentColor，圆点脉动） | 灰 | 灰 |
| 有选中 N 项 | ✓ 已完成态（绿勾 + "已选 N"） | **高亮**，目标栏 tile 边框轻微强调 | 灰 |
| 移动完成瞬间 | 灰（重置前） | ✓ | **绿色 "✓ 已移入 N 项"**，保持 2s 后整体回初始态 |

- 段间用渐变连接线，状态切换 withAnimation(.easeInOut(0.25))
- StepperBar 取代 Phase 1.1 底栏的 hint 文案职责（误点无选中时：步骤①短暂闪烁 accent 提醒 + tile 抖动保留）
- 高度 ~36pt，不喧宾夺主

## 2. 双栏标题

- 左：`选中文件` + 选中数 badge（`已选 N`，无选中时显示文件总数 `共 N 项`）
- 右:`目标位置` + 右对齐 `+` 小按钮（添加目标从网格末尾 tile 移到标题栏；目标为空时的引导卡保留）

## 3. 操作日志

- ScootCore 新增 `MoveLog`：`LogEntry { id, date, fileName, destName, batchID }`
- MoveEngine 每次成功移动逐文件记录；撤销也记录（`fileName ← destName` 方向标记 undo）
- 持久化 JSONL：`~/Library/Application Support/Scoot/history.jsonl`，上限 500 条自动截断，跨启动保留
- UI：底栏上方一行 DisclosureGroup「操作日志」，默认收起时显示最近一条摘要；展开为高 ~120pt 的滚动列表，条目格式 `HH:mm  report.pdf → 合同`（undo 条目用 `↩` 前缀灰色显示），倒序
- 日志只读，不提供逐条撤销（现有批量撤销保留在底栏）
- MoveLog 逻辑放 ScootCore，必须带单测（记录、截断、undo 方向、JSONL 读写）

## 4. 主窗口

- `Window("Scoot", id: "main")` scene，复用 ContentView，`defaultSize 720×480`，可缩放（minWidth 640, minHeight 420）
- 入口：底栏新增 `⤢` 按钮（openWindow(id:"main")），打开时关闭菜单栏面板焦点问题同 pickFolder 处理
- 激活策略：窗口出现时 `NSApp.setActivationPolicy(.regular)`（出现 Dock 图标、可 Cmd-Tab），窗口全部关闭时还原 `.accessory`。用 NSWindow.willCloseNotification 或 onDisappear 监听
- 菜单栏入口不变，两个入口同时可用，状态共享（同一批 EnvironmentObject，注意 scene 间共享用 @StateObject 提升到 App 层——现状如已在 App 层则无需动）

## 完成定义

1. swift build -c release 零 error / swift test 全绿（原 13 项 + MoveLog 新测试）
2. make app 成功，open 后进程存活 3s 验证后 pkill
3. git commit 分两个：`feat: stepper flow, pane headers and move log` / `feat: main window with dock activation policy`

## 验收清单（给 Kyle）

1. 打开面板：步骤①高亮；选中文件后②高亮且左栏标题显示"已选 N"
2. 点击目标：③亮绿"已移入 N 项"，2 秒后回初始态
3. 操作日志展开可见历史，重启应用日志仍在
4. 底栏 ⤢ 打开主窗口，Dock 出现图标可 Cmd-Tab；关窗后 Dock 图标消失
5. 主窗口与面板操作互通（一边移动，另一边列表/日志同步）
