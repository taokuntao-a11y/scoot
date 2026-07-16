# SPEC — Phase 2 顺手度（v0.3.0）

范围：全局快捷键呼出 + 多源文件夹切换。
FinderSync 右键扩展顺延（构建扩展 target 需完整 Xcode，本机仅 CLT）。

## 2.1 全局快捷键呼出

### 依赖（缝合匠原则，不自研热键/面板呼出）

- `sindresorhus/KeyboardShortcuts`（Carbon RegisterEventHotKey，无需辅助功能权限，自带 SwiftUI Recorder）
- `orchetect/MenuBarExtraAccess`（MenuBarExtra 没有官方编程呼出 API，该库提供 `isPresented` binding）

两者均支持 macOS 13、纯 SPM，可在 CLT 环境构建。

### 行为

- 快捷键名：`KeyboardShortcuts.Name.togglePanel`，默认 **⌥⇧S**
- 按下：切换 MenuBarExtra 面板显隐（toggle）
  - 呼出时 `NSApp.activate(ignoringOtherApps: true)`，保证面板立即可交互
  - 面板已显示时按下 → 收起
- 主窗口（"main"）不受快捷键影响，仍走底栏按钮
- 设置入口：底栏新增齿轮按钮 → popover，内含 `KeyboardShortcuts.Recorder("呼出面板", name: .togglePanel)`，用户可自定义/清除
- 快捷键持久化由 KeyboardShortcuts 库负责（UserDefaults）

## 2.2 多源文件夹切换

### 数据层（ScootCore）

新增 `SourceStore`（@MainActor ObservableObject），镜像 `DestinationStore` 模式：

```swift
public struct SourceFolder: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String   // 默认 lastPathComponent
    public var path: String
}
```

- 持久化：`Application Support/Scoot/sources.json`，结构 `{ "sources": [...], "activeID": UUID }`，atomic 写
- `@Published public var sources: [SourceFolder]`
- `@Published public var activeSource: SourceFolder`（setter 持久化 activeID）
- `add(url:)`：重复 path 不重复添加，改为激活已有项
- `remove(_:)`：**最后一个源不可删**；删除当前激活源时自动切到第一项
- 首次初始化 / 迁移：
  1. 默认植入 `~/Downloads`
  2. 读旧 UserDefaults key `"sourcePath"`：存在且 != Downloads 则追加为第二项并设为激活，然后**删除该 key**（迁移一次性）

### SourceWatcher 改造

- 变为纯监控器：删除内部 UserDefaults 读写与默认路径逻辑，`sourcePath` 由外部注入（didSet 仍 rebuild + reload，不再写 UserDefaults）
- `init(path: String)` 接收初始路径；App 层用 `store.activeSource.path` 构造
- App 层监听 activeSource 变化 → 更新 `watcher.sourcePath`，同时清空 SelectionStore

### UI

- **左栏头部**：标题"选中文件"替换为源切换 `Menu`：
  - label 显示当前源文件夹名 + chevron.down，样式与 PaneHeader 标题一致
  - 菜单项：每个源一行（激活项 checkmark），点击切换
  - 分隔线后："添加源文件夹…"（走 `pickFolder`）；源数 > 1 时提供"移除当前源"
  - badge（已选 n / 共 n 项）保留
- **底栏**：移除原"源文件夹"按钮（职责已上移），新增齿轮按钮（快捷键设置 popover）
- 切源后文件列表刷新、选择清空，StepperBar 状态不变

## 测试（swift-testing，ScootCore）

- SourceStore：add 去重、remove 最后一项被拒、remove 激活项自动切换、持久化 round-trip、旧 sourcePath 迁移（含 = Downloads 与 != Downloads 两种）
- 迁移测试需可注入 storage 目录与 UserDefaults（suiteName 隔离）

## 验收清单

1. `make app` 产出 dist/Scoot.app，启动无闪退
2. 默认 ⌥⇧S 在任意 App 前台时呼出/收起 Scoot 面板，呼出后可直接点选文件
3. 齿轮 popover 里改快捷键立即生效，重启后保留
4. 左栏头部可添加第二个源文件夹并切换，列表随之刷新
5. 切源后原选择被清空；移除激活源自动落到第一项；仅剩一个源时移除入口不可用
6. 升级场景：旧版本自定义过源文件夹的用户，首启后该文件夹出现在源列表且为激活项
7. `swift test` 全绿
