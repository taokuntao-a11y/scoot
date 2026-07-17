# SPEC — Phase 3.1 验收修复（v0.4.0 内）

Kyle 验收 Phase 3 反馈四条，根因与修复方案如下。

## F1 AI 建议触发钥匙串系统弹窗

**根因**：app 是 ad-hoc 签名，每次 `make app` 重建后二进制身份都变，Keychain ACL 无法长期信任本 app；CLI 写入的钥匙串项还有分区表问题。结果是读 key 就弹系统授权窗，且每次发版后复发。

**修复**：API Key 改存本地文件（~/.ssh 模型）：
- 路径 `Application Support/Scoot/credentials.json`，内容 `{"apiKey": "..."}`
- 写入后强制 POSIX 权限 **0600**（仅当前用户可读写）；读取时若权限过宽先收紧
- `AIConfigStore` 的 setKey/clearKey/hasKey/makeLLMService 全部改走该文件；**删除 KeychainHelper.swift**
- 设置 UI 文案改为「Key 保存在本机 Application Support，仅当前用户可读；不会上传」
- 不做 Keychain 迁移（迁移读取本身就会弹窗）；主会话负责在部署时手工写好文件并清掉旧钥匙串项

## F2 文件移动缺少动画反馈

**要求**：无论真实耗时多短，移动必须有可感知的视觉反馈。

- **乐观移除**：`SourceWatcher` 加 `removeImmediately(_ urls: [URL])`——移动/重命名成功后由 AppModel 立即调用，从 `files` 中移除对应项，不等 FS 事件回扫；配合列表动画产生"飞走"效果
- **列表动画**：`FileListView` 的 List 挂 `.animation(.easeInOut(duration: 0.25), value: sourceWatcher.files)`（FileItem 已 Equatable）
- **成功 toast**：AppModel 加 `@Published toastMessage: String?`，move 成功置「已移动 N 项 → 目标名」、rename 置「已重命名 N 项」、undo 置「已撤销 N 项」，1.6s 后自动清除（Task 防抖，参考现有 completionMoveCount 模式）
- ContentView 底部叠加 toast 视图：胶囊底、✓ 图标 + 文案，出现/消失带 .spring 过渡，不挡操作（allowsHitTesting(false)）
- 目标 tile 已有的弹跳动效保留

## F3 AI 等待缺少进度感

**要求**：请求期间给读数缓解焦虑，且可取消。

- AppModel：`aiIsBusy` 之外加 `@Published aiElapsedSeconds: Int`，busy 置 true 时每秒 +1（Task 循环，busy 结束取消归零）
- `AIActionsView`：请求 Task 存入 `@State aiTask: Task<Void, Never>?`
- ContentView 全面板 overlay（aiIsBusy 时显示）：半透明遮罩 + ProgressView + 「AI 思考中… N 秒」+ 「取消」按钮（cancel aiTask；URLSession 尊重 Task 取消）；取消后不报错静默复位
- 两个 AI 按钮原地 spinner 保留

## F4 操作完成后短暂无响应

**根因**（三处主线程阻塞叠加）：
1. `SourceWatcher.reload()` 在主线程同步 `contentsOfDirectory` + 逐文件 `resourceValues`，Downloads 文件多时卡顿
2. `FileRowView` 每次渲染同步调 `NSWorkspace.shared.icon(forFile:)`（磁盘 IO），列表刷新时逐行执行
3. `MoveLog.record` 每条日志一次 FileHandle 写盘，批量移动 N 项写 N 次

**修复**：
1. 扫描异步化：把目录扫描抽成 `nonisolated static func scan(path:) -> [FileItem]`（纯函数，FileItem Sendable），`reload()` 改为在后台 `Task.detached` 执行 scan、回主线程发布；用自增 generation 计数丢弃过期结果（防乱序覆盖）。注意项目已知坑：闭包别交给 GCD 后台队列，用 structured Task
2. 图标缓存：`FileIconCache`（@MainActor，[String: NSImage]，key = 目录用 "folder"、文件用小写扩展名、无扩展名用 "file"），FileRowView 走缓存；上限 200 清空重建
3. `MoveLog` 加 `record(batch: [LogEntry])`：内存插入 + 单次追加写盘；AppModel 的 move/undo/rename 改用批量接口

## 测试

- MoveLog batch：批量记录顺序正确、单次写盘后 load round-trip、超 500 截断
- SourceWatcher.scan 纯函数：临时目录建文件验证过滤/排序逻辑（隐藏文件、未完成下载后缀、倒序）
- AIConfigStore 文件存取：set/get/clear round-trip、权限 0600 校验（可注入存储目录）

## 验收清单

1. 点 AI 分拣/重命名：**无任何系统钥匙串弹窗**
2. 移动文件：列表行有动画消失 + 底部 toast「已移动 N 项 → xx」；撤销同理
3. AI 请求期间：面板遮罩 + 秒数读数 + 可取消，取消后界面立即恢复
4. 在 Downloads 有大量文件时连续移动：无可感知卡顿
5. `swift test` 全绿；旧功能回归正常
