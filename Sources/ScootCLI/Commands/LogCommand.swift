import ArgumentParser
import Foundation

struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "log", abstract: "显示最近的操作记录（最新在前）")

    @Option(name: [.customShort("n"), .customLong("limit")], help: "显示条数（默认 20）")
    var limit: Int = 20

    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let result = await CLIRunner.log(limit: limit)
        if json {
            CLIOutput.printJSON(result)
        } else if result.entries.isEmpty {
            print("暂无操作记录。")
        } else {
            let formatter = ISO8601DateFormatter()
            for e in result.entries {
                let tag = e.undo ? " [撤销]" : ""
                print("\(formatter.string(from: e.date))  \(e.file) → \(e.dest)\(tag)")
            }
        }
    }
}
