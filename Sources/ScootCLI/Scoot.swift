import ArgumentParser
import Foundation

@main
struct Scoot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scoot",
        abstract: "Scoot 文件分类工具的命令行接口 — 与菜单栏 App 共享同一份状态。",
        discussion: """
        大多数子命令支持 --json：加上后 stdout 只输出一个 JSON 对象，人类可读文本全部走 stderr；
        不加则打印人类可读的文本。用 `scoot capabilities` 获取完整的机器可读能力清单（供 agent 自发现）。
        CLI 与菜单栏 GUI 共享同一份状态文件（~/Library/Application Support/Scoot），互相之间是实时的。
        注意：CLI 不提供 `undo` —— MoveEngine 的撤销栈只在单次进程内存活，无法跨越多次 CLI 调用。
        """,
        version: ScootCLIVersion.string,
        subcommands: [
            DestCommand.self,
            SrcCommand.self,
            ListCommand.self,
            MoveCommand.self,
            RenameCommand.self,
            SlimCommand.self,
            LogCommand.self,
            CapabilitiesCommand.self,
        ]
    )

    @Flag(name: .long, help: "打印能力清单 JSON 并退出（等价于 `scoot capabilities`）")
    var capabilities: Bool = false

    func run() async throws {
        if capabilities {
            CLIOutput.printJSON(Capabilities.manifest)
            return
        }
        print(Scoot.helpMessage())
    }
}
