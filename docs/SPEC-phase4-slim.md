# SPEC — Phase 4：集成 Slim 压缩（v0.5.0）

集成本地 PDF/PPTX/图片压缩工具 `slim` 为新动作「瘦身 / Slim」，采用 **bundle-embed** 架构：冻结后的 `slim` 二进制打进 `Scoot.app/Contents/Resources/`，Scoot 以子进程方式调用并解析其 JSON 输出。

## 架构：bundle-embed

- `slim` 代码在独立仓库 `/Users/kun/Projects/slim`；`make freeze` 产出自包含二进制 `dist/slim`（约 39MB，arm64，无需 Python 运行时，可在空环境运行）。
- `scripts/build-app.sh` 在装配 `.app` 时把该二进制拷入 `Contents/Resources/slim` 并 `chmod +x`。
- Scoot 运行时用 `Process` 启动它，走 `--json` 契约，只解析 stdout 的单个 JSON 对象，不依赖任何 slim 内部实现细节。
- 两个仓库运行时零耦合：Scoot 只依赖“调用约定”，不 import slim 代码，也不修改 `/Users/kun/Projects/slim` 下任何文件。

## 依赖的 slim CLI 契约

```
slim <INPUT> -o <OUTPUT> -q <high|balanced|extreme> --json
```

- `--json` 保证 stdout **只有一个 JSON 对象**，人类可读进度全部走 stderr。
- 退出码 `0` 成功；`1` 为已处理错误，此时 stdout 是 `{"error": "..."}`。
- 支持的扩展名（大小写不敏感）：`.pdf .pptx .jpg .jpeg .jpe .png .webp .tif .tiff .bmp .gif`
- 成功 JSON（依赖字段）：`format` `input_path` `output_path` `input_size_mb` `output_size_mb` `reduction_pct`；其余字段（`images_processed`、`output_dimensions`、`previews` 等）忽略不解析。
- 错误 JSON：`{"error":"..."}`。

契约已用真实二进制验证：`slim README.md --json` → 报未支持类型错误（exit 1）；`slim <真实 PNG> -o out.png -q balanced --json` → 成功 JSON，字段与文档一致。

## 新增/改动文件

### `Sources/ScootCore/SlimService.swift`（新增）
- `SlimError`：`.binaryNotFound` `.unsupportedType` `.compressionFailed` `.launchFailed` `.badOutput`，`LocalizedError` 中文文案，风格对齐 `LLM.swift` 的 `LLMError`。
- `SlimResult`：`inputSizeMB` `outputSizeMB` `reductionPct` `outputPath` `format`。
- `SlimService.slimmableExtensions` / `SlimService.canSlim(_:)`：扩展名白名单与判断。
- `SlimService.parseResult(stdout:exitCode:)`：**纯函数**，只做 JSON 解析与语义判断（`error` 字段优先于退出码；退出码非 0 时兜底为 `.compressionFailed`；缺字段为 `.badOutput`），不涉及进程，单测直接覆盖。
- `SlimService.locateBinary(bundle:environment:devFallback:)`：查找顺序 = app bundle `Contents/Resources/slim` → `SCOOT_SLIM_BIN` 环境变量 → 开发期兜底路径 `/Users/kun/Projects/slim/dist/slim`；参数可注入，测试不依赖真实 app bundle。
- `SlimService.compress(_:to:quality:)`：`Process` 子进程，`Pipe` 增量读 stdout（避免大输出撑满管道死锁），`withCheckedThrowingContinuation` + `terminationHandler` 桥接为 async；`withTaskCancellationHandler` 里 `onCancel` 终止子进程，返回后 `Task.checkCancellation()` 把已终止进程的“伪结果”转换成 `CancellationError`，不会被误判为压缩失败。
- Swift 6 严格并发：`Process`/`Pipe` 的 `readabilityHandler`、`terminationHandler` 闭包不捕获任何 `@MainActor` 状态，用局部 `NSLock` 封装的 `ProcessBox` / `LockedBox`（`@unchecked Sendable`）在后台线程安全传递结果，避免了此前 `SourceWatcher` 那类“MainActor 闭包被派发到后台线程导致 SIGTRAP”的坑（每次 `compress` 调用各自持有独立的 `ProcessBox`，互不影响，也支持并发调用各自取消）。

### `Sources/Scoot/AppModel.swift`（改动）
- 新增独立状态：`@Published slimIsBusy`、`slimCancelAction`（与 `aiIsBusy` 完全分开，互不阻塞）。
- 新增 `func slim(_ items: [URL], quality: String = "balanced")`：
  - 过滤出可压缩文件，全部不支持时给 `errorMessage` 并返回；
  - 顺序调用 `SlimService.compress`，输出路径用 `uniqueDestinationURL(for: "<stem>_slim.<ext>", in: sameDir)` 避免覆盖已有文件；
  - 成功批次写 `moveLog.record(batch:)`（`destName` = "压缩"），toast 文案「已压缩 N 项，共省 X.X MB」；
  - **不调用** `watcher?.removeImmediately`——slim 生成的是同目录新文件（`_slim` 后缀），原文件未被删除/移动，FS watcher 会自然把新文件带出来；
  - 用户取消（`CancellationError`）静默返回，不报错。

### `Sources/Scoot/SlimActionsView.swift`（新增）
- 底部栏「🗜 瘦身」`Menu` 按钮，三档质量（高质量/均衡/极限压缩）对应 `high` / `balanced` / `extreme`。
- 仅当选区中存在至少一个可压缩文件时启用；`.help` 区分「未选择」/「所选不支持」/「可压缩」三种提示；`slimIsBusy` 时按钮位置显示 spinner。
- `ContentView.swift` 的 `BottomBarView` 里紧邻 `AIActionsView()` 放置。

### `scripts/build-app.sh`（改动）
- 装配 `MacOS/` 之后新建 `Contents/Resources/`，从 `SLIM_BIN`（默认 `/Users/kun/Projects/slim/dist/slim`）拷贝二进制进去并 `chmod +x`；源路径不存在时打印清晰错误并 `exit 1`（提示去 slim 仓库跑 `make freeze`）。
- 先对 `Contents/Resources/slim` 单独 `codesign --force -s -`，再对整个 `.app` 签名（嵌套代码必须先签）。
- `CFBundleShortVersionString` → `0.5.0`，`CFBundleVersion` → `5`。

### `Tests/ScootTests/SlimServiceTests.swift`（新增）
- `parseResult`：成功 JSON（含图片专属多余字段的场景）、`{"error":...}` + exit 1 → `.compressionFailed` 携带原文、exit 0 但含 `error` 字段仍抛错、非 JSON + 非零退出码抛错、有效 JSON 但无 `error` 键 + 非零退出码抛 `.compressionFailed`、缺字段抛 `.badOutput`。
- `canSlim` / `slimmableExtensions`：白名单精确匹配（含大小写不敏感）、黑名单（`.txt` `.md`）。
- `locateBinary`：注入的 `SCOOT_SLIM_BIN` 优先、空字符串覆盖值应被忽略并回落、开发期兜底路径命中、全部落空时返回 `nil`。
- 集成测试 `compressesARealPNG`：若 `/Users/kun/Projects/slim/dist/slim` 不存在则直接跳过（不失败）；存在时用纯 Swift 手搓一张最小合法 PNG（zlib stored block，无需 AppKit/ImageIO），实际跑一次 `compress`，断言 `reductionPct >= 0` 且输出文件存在。本机验证：**跑通**，耗时约 5–8 秒（含子进程冷启动 + `--json` 往返）。

## 构建 / 验证方式

```bash
swift build -c release   # 无警告、无并发错误
swift test                # 76 个测试全绿（含新增 15 个 Slim 相关用例）
make app                  # 产出 dist/Scoot.app，内嵌已签名 slim 二进制
codesign --verify --deep --verbose=2 dist/Scoot.app   # valid on disk
```

若 `dist/Scoot.app/Contents/Resources/slim` 缺失或 `SLIM_BIN` 指向的文件不存在，`make app` 会在装配前直接失败并给出修复提示，不会产出半成品 `.app`。

## 已知取舍

- `compress` 目前串行处理选中的多个文件（spec 允许，避免子进程并发抢占 CPU/PDF 渲染库的资源竞争）；`SlimService` 本身按调用隔离取消状态，天然支持未来切并发不需要重构。
- UI 层没有为「瘦身」单独做全屏遮罩/倒计时覆盖层（AI 动作有的那种）；按钮 spinner + `.disabled` + toast 已经足够表达忙碌状态，且规格只要求「busy spinner」，未要求遮罩，保持改动面小。
