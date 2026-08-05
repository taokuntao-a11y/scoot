import ArgumentParser
import Foundation

struct RenameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rename", abstract: "原地重命名一个文件")

    @Argument(help: "要重命名的文件路径") var file: String
    @Option(name: .customLong("name"), help: "新文件名") var name: String
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let result = try await CLIRunner.rename(file: file, newName: name, cwd: cwd)
            if json {
                CLIOutput.printJSON(result)
            } else {
                print("已重命名: \(result.renamed.from) → \(result.renamed.to)")
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}
