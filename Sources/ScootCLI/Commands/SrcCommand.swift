import ArgumentParser
import Foundation

struct SrcCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "src",
        abstract: "管理来源文件夹（被监控/分类的文件夹）",
        subcommands: [SrcListCommand.self, SrcAddCommand.self, SrcUseCommand.self]
    )
}

struct SrcListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "列出所有来源文件夹，标出当前活跃的一个")

    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let result = await CLIRunner.srcList()
        if json {
            CLIOutput.printJSON(result)
        } else {
            for s in result.sources {
                let marker = s.active ? "*" : " "
                print("\(marker) \(s.name)\t\(s.path)")
            }
        }
    }
}

struct SrcAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "添加一个来源文件夹，并将其设为活跃")

    @Argument(help: "要添加的文件夹路径") var path: String
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let result = try await CLIRunner.srcAdd(path: path, cwd: cwd)
            if json {
                CLIOutput.printJSON(result)
            } else {
                print("已添加来源: \(result.added.name) → \(result.added.path)（已设为活跃）")
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}

struct SrcUseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "将一个已存在的来源文件夹设为活跃（按名称或路径匹配）"
    )

    @Argument(help: "来源名称或路径") var nameOrPath: String
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let result = try await CLIRunner.srcUse(nameOrPath: nameOrPath, cwd: cwd)
            if json {
                CLIOutput.printJSON(result)
            } else {
                print("活跃来源: \(result.active)")
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}
