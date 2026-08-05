import Foundation
import ScootCore

/// Machine-readable manifest so an agent can self-discover scoot. Printed by
/// `scoot capabilities` and `scoot --capabilities`. Derives what it can from the
/// code (SlimService.slimmableExtensions) rather than hard-coding lists that could
/// drift out of sync.
enum Capabilities {
    static var manifest: CapabilitiesOutput {
        CapabilitiesOutput(
            name: "scoot",
            version: ScootCLIVersion.string,
            description: "Scoot 菜单栏文件分类工具的命令行接口；与 GUI App 共享同一份状态"
                + "（~/Library/Application Support/Scoot 下的 destinations.json / sources.json / history.jsonl）。",
            commands: [
                "scoot dest list [--json]",
                "scoot dest add <path> [--json]",
                "scoot dest remove <name-or-path> [--json]",
                "scoot src list [--json]",
                "scoot src add <path> [--json]",
                "scoot src use <name-or-path> [--json]",
                "scoot list [<source-name-or-path>] [--json]",
                "scoot move <file>... --to <dest-name-or-path> [--json]",
                "scoot rename <file> --name <newName> [--json]",
                "scoot slim <file>... [-q high|balanced|extreme] [--json]",
                "scoot log [-n <N>] [--json]",
                "scoot capabilities",
            ],
            qualities: ["high", "balanced", "extreme"],
            slimmable_extensions: SlimService.slimmableExtensions.sorted(),
            json_contract: JSONContract(
                flag: "--json",
                stdout: "exactly one JSON object, nothing else",
                stderr: "human-readable progress",
                exit_codes: [
                    "0": "success",
                    "1": "handled error — {\"error\": \"...\"} on stdout (--json) or a message on stderr",
                ]
            ),
            state_dir: "~/Library/Application Support/Scoot"
        )
    }
}
