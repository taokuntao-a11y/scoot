import ArgumentParser
import Foundation

struct SlimCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "slim", abstract: "压缩一个或多个文件（PDF/PPTX/图片）")

    @Argument(help: "要压缩的文件路径（一个或多个）") var files: [String]

    @Option(name: [.customShort("q"), .customLong("quality")], help: "压缩质量: high | balanced | extreme（默认 balanced）")
    var quality: String = "balanced"

    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        guard !files.isEmpty else {
            CLIOutput.fail("至少需要指定一个文件", json: json)
        }
        do {
            let result = try await CLIRunner.slim(files: files, quality: quality, cwd: cwd)
            if json {
                CLIOutput.printJSON(result)
            } else {
                for c in result.compressed {
                    print(String(
                        format: "已压缩: %@ → %@ (%.2f MB → %.2f MB, -%.1f%%)",
                        c.input, c.output, c.input_mb, c.output_mb, c.reduction_pct
                    ))
                }
                for err in result.errors { print("失败: \(err.file) (\(err.error))") }
                print(String(format: "共省 %.1f MB", result.saved_mb))
            }
            if result.compressed.isEmpty && !result.errors.isEmpty {
                Foundation.exit(1)
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}
