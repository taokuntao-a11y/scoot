import ArgumentParser
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "列出来源文件夹中的文件和子目录（不递归，跳过隐藏项）"
    )

    @Argument(help: "来源名称或路径（省略则用当前活跃来源）") var source: String?
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let result = try await CLIRunner.list(sourceArg: source, cwd: cwd)
            if json {
                CLIOutput.printJSON(result)
            } else {
                print("\(result.source)  (\(result.count) 项)")
                for f in result.files {
                    let kind = f.isDirectory ? "dir " : "file"
                    print("  [\(kind)] \(f.name)\t\(f.size) bytes")
                }
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}
