# SPEC — CLI：`scoot` 命令行接口（v0.6.0）

新增可执行 target `ScootCLI`（二进制名 `ScootCLI`，安装后拷贝为 `scoot`），让 Claude Code /
OpenClaw 之类的 agent 以及用户本人可以从终端驱动 Scoot 的文件分类逻辑，与菜单栏 GUI **共享同一份状态**：
`~/Library/Application Support/Scoot/{destinations,sources}.json` + `history.jsonl`。CLI 直接复用
`ScootCore`（`DestinationStore` / `SourceStore` / `MoveEngine` / `MoveLog` / `SlimService`），不重复实现
业务逻辑。

## 架构

- `Package.swift` 新增依赖 `swift-argument-parser`（1.3+，纯 Swift 无宏，CLT 可编译）与可执行 target
  `ScootCLI`（`path: Sources/ScootCLI`）。
- `Sources/ScootCLI/Scoot.swift`：`@main struct Scoot: AsyncParsableCommand`，`commandName: "scoot"`，
  `version:` 读自 `Support/Version.swift` 的 `ScootCLIVersion.string` 常量（与
  `scripts/build-app.sh` 里的 `CFBundleShortVersionString` 一起手动保持同步）。
- `Sources/ScootCLI/Commands/*.swift`：每个子命令一个 `AsyncParsableCommand`，只负责参数解析 + 调用
  `CLIRunner` + JSON/人类可读双模式打印。
- `Sources/ScootCLI/Support/CLIRunner.swift`：`@MainActor enum CLIRunner`，每个函数各自新建所需的
  `DestinationStore()` / `SourceStore()` / `MoveLog()`（CLI 是短生命周期进程，不需要跨调用共享实例），
  执行操作，返回 `Codable` 结果 struct。所有触达 `@MainActor` store 的逻辑都在这里，通过
  `await CLIRunner.xxx(...)` 从各命令的 `run() async throws` 调用。
- `Sources/ScootCLI/Support/Resolvers.swift`：纯函数、不碰磁盘（除了标准化路径字符串）——
  `PathResolver.resolve`（展开 `~`、相对路径转绝对路径）、`matchDestination` / `matchSource`
  （name-or-path 匹配：先按名称精确匹配，退化为标准化路径比较）、`resolveMoveTarget`（`move --to` 的
  三级解析：store 按名称 → store 按路径 → 现有目录兜底，`fileManager` 参数可注入方便测试）。这些是
  `Tests/ScootTests/ScootCLIResolversTests.swift` 直接单测的对象，不需要跑子进程或触碰真实用户状态。
- `Sources/ScootCLI/Support/{Models,CLIOutput,CLIError,Capabilities}.swift`：JSON 输出结构体、
  统一的 stdout/stderr 打印规则、`CLIError`（`LocalizedError`，让 `error.localizedDescription`
  在两种模式下都给出干净的中文提示）、`capabilities` 清单构造。

## `--json` 契约（对齐 slim 的 CLI）

- 加 `--json`：stdout **只输出一个 JSON 对象**，不多不少；人类可读文字一律不打印（不占用 stdout，
  也不写 stderr——因为这类命令本身没有"进度"概念，一次调用就是一个结果）。
- 不加 `--json`：打印人类可读文本到 stdout。
- 退出码 `0` = 成功；`1` = 已处理错误：`--json` 模式下 stdout 输出 `{"error": "..."}`（仍然是唯一的
  JSON 对象，不会在此之外再打印别的东西）；非 `--json` 模式下错误文本写 stderr，前缀 `Error: `。
- **例外**：`scoot move` 与 `scoot slim` 支持部分成功——只要移动/压缩了至少一个文件，即使其余文件
  失败也退出 `0`，失败项列在结果的 `errors` 数组里；只有"一个都没成功 且 有失败"时才退出 `1`
  （这种情况仍然打印正常的结果 JSON，不是 `{"error":...}`——因为这不是一个无法解析请求的"硬错误"，
  只是全部尝试都失败了）。

## 子命令与 JSON 形状

### `scoot dest list [--json]`
```json
{"destinations":[{"name":"Invoices","path":"/Users/kun/Documents/Invoices"}]}
```

### `scoot dest add <path> [--json]`
路径展开 `~`/相对路径，必须是已存在的文件夹。
```json
{"added":{"name":"Invoices","path":"/Users/kun/Documents/Invoices"}}
```

### `scoot dest remove <name-or-path> [--json]`
按名称或路径匹配一个已存在的目标；无匹配报错。
```json
{"removed":{"name":"Invoices","path":"/Users/kun/Documents/Invoices"}}
```

### `scoot src list [--json]`
```json
{"active":"/Users/kun/Downloads","sources":[{"name":"Downloads","path":"/Users/kun/Downloads","active":true}]}
```

### `scoot src add <path> [--json]`
添加后自动设为活跃来源（`SourceStore.add` 的既有行为）。
```json
{"added":{"name":"Inbox","path":"/Users/kun/Downloads/Inbox"},"active":"/Users/kun/Downloads/Inbox"}
```

### `scoot src use <name-or-path> [--json]`
目标必须已在来源列表中（不会隐式添加）。
```json
{"active":"/Users/kun/Downloads"}
```

### `scoot list [<source-name-or-path>] [--json]`
省略参数则用当前活跃来源；给了就按名称/路径匹配已存在来源，都不匹配则要求是一个真实存在的目录。
非递归，跳过隐藏文件；对每一项给出 `name` / `size`（字节）/ `isDirectory` / `modified`（ISO8601）。
```json
{"source":"/Users/kun/Downloads","count":2,"files":[
  {"name":"report.pdf","size":102400,"isDirectory":false,"modified":"2026-08-05T10:00:00Z"},
  {"name":"Subfolder","size":0,"isDirectory":true,"modified":"2026-08-04T09:00:00Z"}
]}
```

### `scoot move <file>... --to <dest-name-or-path> [--json]`
`--to` 解析顺序：store 按名称 → store 按路径 → 若都不匹配但是一个真实存在的目录，直接使用
（名称取其 `lastPathComponent`）。用 `MoveEngine.move` 执行；成功的文件写入一条 `MoveLog` 批次
（单个 `batchID`，`destName` = 解析出的目标名，`isUndo:false`），与 `AppModel.move` 的日志语义一致。
```json
{"moved":[{"from":"/Users/kun/Downloads/report.pdf","to":"/Users/kun/Documents/Invoices/report.pdf"}],
 "errors":[],"destination":"Invoices"}
```

### `scoot rename <file> --name <newName> [--json]`
`MoveEngine.rename`，日志 `destName` = `"重命名"`（与 GUI 完全一致的中文标签，日志里两边混用不会有
歧义）。
```json
{"renamed":{"from":"/Users/kun/Downloads/report.pdf","to":"/Users/kun/Downloads/2026-report.pdf"}}
```

### `scoot slim <file>... [-q|--quality high|balanced|extreme] [--json]`
默认 `balanced`。过滤出 `SlimService.canSlim` 支持的文件，逐个用 `SlimService().compress` 压缩到
同目录 `<stem>_slim.<ext>`（`uniqueDestinationURL` 避免覆盖）；成功的写入一条 `MoveLog` 批次
（`destName` = `"压缩"`）。若一个可压缩文件都没有，报错退出（`所选文件均不支持压缩`）。
```json
{"compressed":[{"input":"/Users/kun/Downloads/photo.png","output":"/Users/kun/Downloads/photo_slim.png",
  "input_mb":4.2,"output_mb":0.9,"reduction_pct":78.6}],
 "errors":[],"saved_mb":3.3}
```

### `scoot log [-n|--limit N（默认 20）] [--json]`
`MoveLog.entries`（内存中已经是最新在前）取前 N 条。
```json
{"entries":[{"date":"2026-08-05T10:00:00Z","file":"report.pdf","dest":"Invoices","undo":false}]}
```

### `scoot capabilities`（恒定输出 JSON，不需要 `--json`）／`scoot --capabilities`
机器可读能力清单，供 agent 自发现，字段尽量从代码派生而非手写（如 `slimmable_extensions` 取自
`SlimService.slimmableExtensions`）：`name` `version` `description` `commands` `qualities`
`slimmable_extensions` `json_contract` `state_dir`。

### `scoot --version`
ArgumentParser 内置，读 `ScootCLIVersion.string`。

## 不做的事

- **没有 `scoot undo`**：`MoveEngine` 的撤销栈只存在于单次进程内存里，CLI 每次调用都是全新进程，
  跨调用没有栈可言，做了也没有语义。GUI 内的撤销不受影响（它本来就是同一个长驻进程里的
  `MoveEngine` 实例）。

## `SlimService` 的 PATH 发现（`Sources/ScootCore/SlimService.swift`）

`locateBinary` 新增第三级查找：在 bundle Resources、`SCOOT_SLIM_BIN` 环境变量之后，插入
"扫描 `PATH` 目录找可执行文件 `slim`"（不 shell out 到 `which`，直接遍历
`environment["PATH"]` 按 `:` 分割的每个目录，`FileManager.isExecutableFile` 判断），
再落到开发期兜底路径。这样任何用 slim 自己的 `install.sh`（pipx 安装）装过 slim 的 Mac，
`scoot slim` 都能直接工作，不依赖 `Scoot.app` 内嵌了 slim 二进制。

## `scripts/build-app.sh`：slim 内嵌改为可选

之前 `SLIM_BIN` 指向的文件不存在会直接 `exit 1`。现在改为：存在则内嵌 + 单独签名（行为不变）；
不存在则打印警告并跳过内嵌，`make app` 仍然成功产出 `.app`（运行时 `SlimService.locateBinary`
会退到 PATH 查找）。

## `scripts/install.sh`：源码构建安装器

参照 `/Users/kun/Projects/slim/install.sh` 的风格（`set -euo pipefail`、彩色 `say/warn/die`）。
`curl | bash` 或从已有 clone 里跑：检测 `swift`（CLT）与 `git`；复用当前 clone 或
clone/`git pull` 到 `${SCOOT_SRC:-$HOME/.cache/scoot-src}`；尽力（非致命失败）用 pipx 装 slim；
`make app` 构建（slim 内嵌现在是可选的，全新 Mac 上也能成功）；把 `.build/release/ScootCLI`
拷贝安装为 `${PREFIX:-$HOME/.local/bin}/scoot`；把 `dist/Scoot.app` 装到 `/Applications`
（不可写则退到 `$HOME/Applications`）。

## 测试

- `Tests/ScootTests/SlimServiceTests.swift`：新增 `findsBinaryOnPATH`（PATH 指向含虚拟可执行文件
  `slim` 的临时目录，`SCOOT_SLIM_BIN` 未设、devFallback 指向不存在路径，验证只能靠 PATH 分支命中）
  与 `envOverrideWinsOverPATH`（两者都命中时验证优先级）。
- `Tests/ScootTests/ScootCLIResolversTests.swift`：`PathResolver`（绝对路径直通、相对路径拼接、
  `~` 展开）、`matchDestination`/`matchSource`（按名称、按绝对路径、按 cwd 相对路径、无匹配返回
  `nil`）、`resolveMoveTarget`（store 命中、真实存在目录兜底、两者都不命中、路径存在但是文件而非
  目录时返回 `nil`）。全部不依赖子进程，`resolveMoveTarget` 的目录兜底用例用临时目录，不触碰真实
  用户的 Application Support 状态。

## 构建 / 验证方式

```bash
swift build                        # debug，含 ScootCLI
swift build -c release             # release，含 ScootCLI
swift test                         # 全绿（92 个测试，含本次新增的 CLI/PATH 用例）
.build/release/ScootCLI --version
.build/release/ScootCLI capabilities
.build/release/ScootCLI dest list --json
bash -n scripts/install.sh
bash -n scripts/build-app.sh
```
