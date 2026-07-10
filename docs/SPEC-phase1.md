# Scoot Phase 1 规格（架构：Fable / 实施：Sonnet coder）

## 构建形态

- Swift Package Manager **executable** target（本机只有 Command Line Tools，禁止依赖 Xcode 工程）。
- `Package.swift`：name `Scoot`，platforms `.macOS(.v13)`，单 executable target `Scoot`（Sources/Scoot/），test target `ScootTests`。
- `scripts/build-app.sh`：`swift build -c release` → 组装 `dist/Scoot.app`（Contents/MacOS/Scoot + Contents/Info.plist + PkgInfo）→ `codesign --force -s - dist/Scoot.app`。
- Info.plist 关键项：`LSUIElement = true`（不占 Dock）、`CFBundleIdentifier = com.kk.scoot`、`CFBundleName = Scoot`、`LSMinimumSystemVersion = 13.0`、`NSHighResolutionCapable`。
- `Makefile`：`make build`（含测试）、`make app`、`make run`（open dist/Scoot.app 前先 pkill 旧实例）。

## 模块

### App 入口（ScootApp.swift）
- `@main struct ScootApp: App`，`MenuBarExtra("Scoot", systemImage: "arrow.right.doc.on.clipboard")`，style `.window`。
- 面板固定尺寸约 640×420，HStack：左 FileListView（~340pt），右 DestinationGridView。
- 底栏：撤销按钮（显示上次动作摘要，无可撤销时禁用）、源文件夹选择（NSOpenPanel）、退出按钮。

### SourceWatcher（Core/SourceWatcher.swift）
- `@MainActor final class SourceWatcher: ObservableObject`，`@Published var files: [FileItem]`。
- 监控：`DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(path, O_EVTONLY), eventMask: .write)`，事件去抖 300ms 后重扫。源路径变更时重建 source，正确 close fd。
- 扫描：`contentsOfDirectory` 取 `.addedToDirectoryDateKey`（取不到 fallback `.contentModificationDateKey`）、`.fileSizeKey`、`.isDirectoryKey`；按添加时间倒序，最多 50 条。
- 过滤：隐藏文件、`.download` / `.crdownload` / `.part` / `.aria2` 未完成下载。目录**保留**（用户可能下载解压出文件夹）。
- `FileItem`: `{ url, name, addedAt, size, isDirectory }`，Identifiable by url。
- 源路径持久化在 UserDefaults（key `sourcePath`），默认 `~/Downloads`。

### DestinationStore（Core/DestinationStore.swift）
- `Destination: Codable, Identifiable { id: UUID, name: String, path: String }`，name 默认取文件夹名，允许重命名（Phase 1 可不做改名 UI）。
- JSON 持久化：`~/Library/Application Support/Scoot/destinations.json`，增删即写盘。
- 添加走 NSOpenPanel（canChooseDirectories）；删除走 tile 右键菜单（只移除钉选，不动磁盘）。

### MoveEngine（Core/MoveEngine.swift）
- `func move(_ items: [URL], to dir: URL) -> MoveResult`：逐个 `FileManager.moveItem`；跨卷时 fallback copy+remove 可以先不做（Phase 1 假定同卷，失败则该条目记入 errors 报告，不中断其余文件）。
- 重名：目标已存在时在扩展名前追加 ` 2`、` 3`…（`report.pdf` → `report 2.pdf`；目录同理）。
- 撤销：每次批量移动压入 `[(from: URL, to: URL)]` 一批，栈深 10，仅内存。undo 反向移动，反向也走重名策略。
- **纯逻辑与 UI 解耦，必须可单测。**

### UI
- FileListView：List 多选（`Set<URL>`），行 = NSWorkspace 文件图标 + 名称 + 相对时间（RelativeDateTimeFormatter）+ 大小（ByteCountFormatter）。行支持 `onDrag { NSItemProvider(contentsOf: url) }`（拖单个；选中多个时拖拽携带全部选中项）。双击 `NSWorkspace.shared.open`。空态提示"下载文件夹是空的 🎉"。
- DestinationGridView：LazyVGrid 两列 tile（文件夹图标 + 名称）。**点击 tile = 把左栏当前选中项移过去**；tile 同时 `onDrop(of: [.fileURL])`。末尾"+"tile 添加目标。移动成功后 tile 短暂高亮/显示"已移入 N 项"。
- 移动结果如有失败，面板底部显示一行错误摘要即可，不弹窗。

## 测试（ScootTests）
- MoveEngine：临时目录里验证 1) 正常移动 2) 重名自动 ` 2`/` 3` 3) undo 还原 4) undo 时原位被占用走重名 5) 部分失败不中断。
- 重名字符串逻辑单独函数单测（含无扩展名、目录、多重后缀 `.tar.gz` 按最后一个扩展名处理即可）。

## 验收标准（交付给用户的清单）
1. `make app && make run` 一次成功，菜单栏出现 Scoot 图标
2. 往 ~/Downloads 丢一个文件，1 秒内出现在左栏顶部
3. 添加两个目标文件夹；选中文件点击 tile，文件移动成功
4. 拖拽左栏文件到 tile 同样生效
5. 移动重名文件自动变成 `xxx 2.ext`
6. 撤销按钮把上一批移回原处
7. 退出重开，目标文件夹钉选仍在
