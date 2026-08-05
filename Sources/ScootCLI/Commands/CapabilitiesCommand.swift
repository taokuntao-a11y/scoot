import ArgumentParser
import Foundation

/// Always emits JSON — no `--json` flag needed here, unlike every other
/// subcommand. Mirrors slim's `--capabilities` contract.
struct CapabilitiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "capabilities", abstract: "打印机器可读的能力清单 JSON（供 agent 自发现）")

    func run() async throws {
        CLIOutput.printJSON(Capabilities.manifest)
    }
}
