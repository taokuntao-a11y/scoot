import ArgumentParser
import Foundation

struct DestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dest",
        abstract: "管理目标文件夹（分类目的地）",
        subcommands: [DestListCommand.self, DestAddCommand.self, DestRemoveCommand.self]
    )
}

struct DestListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "列出所有目标文件夹")

    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let destinations = await CLIRunner.destList()
        if json {
            CLIOutput.printJSON(DestListOutput(destinations: destinations))
        } else if destinations.isEmpty {
            print("暂无目标文件夹。用 `scoot dest add <path>` 添加一个。")
        } else {
            for d in destinations { print("\(d.name)\t\(d.path)") }
        }
    }
}

struct DestAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "添加一个目标文件夹")

    @Argument(help: "要添加的文件夹路径") var path: String
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let added = try await CLIRunner.destAdd(path: path, cwd: cwd)
            if json {
                CLIOutput.printJSON(DestAddOutput(added: added))
            } else {
                print("已添加目标: \(added.name) → \(added.path)")
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}

struct DestRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "移除一个目标文件夹（按名称或路径匹配）"
    )

    @Argument(help: "目标文件夹名称或路径") var nameOrPath: String
    @Flag(name: .long, help: "以 JSON 输出") var json: Bool = false

    func run() async throws {
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let removed = try await CLIRunner.destRemove(nameOrPath: nameOrPath, cwd: cwd)
            if json {
                CLIOutput.printJSON(DestRemoveOutput(removed: removed))
            } else {
                print("已移除目标: \(removed.name) (\(removed.path))")
            }
        } catch {
            CLIOutput.fail(error.localizedDescription, json: json)
        }
    }
}
