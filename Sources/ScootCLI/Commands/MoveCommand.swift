import ArgumentParser
import Foundation

struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "move", abstract: "把一个或多个文件移动到目标文件夹")

    @Argument(help: "要移动的文件路径（一个或多个）") var files: [String]
    @Option(name: .customLong("to"), help: "目标名称或路径") var to: String
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        guard !files.isEmpty else {
            CLIOutput.fail("至少需要指定一个文件", json: json)
        }
        do {
            let result = try await CLIRunner.move(files: files, to: to, cwd: cwd)
            if json {
                CLIOutput.printJSON(result)
            } else {
                for pair in result.moved { print("已移动: \(pair.from) → \(pair.to)") }
                for err in result.errors { print("失败: \(err.file) (\(err.error))") }
                print("目标: \(result.destination)  成功 \(result.moved.count) 项，失败 \(result.errors.count) 项")
            }
            // Partial success (some moved, some failed) still exits 0; only a
            // total wipeout (nothing moved, but errors happened) exits 1.
            if result.moved.isEmpty && !result.errors.isEmpty {
                Foundation.exit(1)
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}
