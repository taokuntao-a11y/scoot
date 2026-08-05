# Calling scoot from an agent

`scoot` is the command-line interface to Scoot, a local macOS file-sorting tool.
It shares state with the menu-bar GUI app — the same
`~/Library/Application Support/Scoot/{destinations,sources}.json` and
`history.jsonl` — so anything the CLI does shows up in the GUI (and vice versa)
immediately.

## Discover what it can do

```bash
scoot --capabilities   # one JSON object: commands, qualities, extensions, contract
scoot --version
```

Parse `--capabilities` instead of hard-coding assumptions — it's derived from
the code (e.g. `slimmable_extensions` comes straight from `SlimService`), so it
stays correct across versions.

## The `--json` contract

Pass `--json` on any subcommand when calling programmatically:

- **stdout** carries **exactly one JSON object and nothing else**.
- All human-readable text goes to **stderr** (or is simply not printed — errors
  in `--json` mode print nothing to stderr and go to stdout instead, see below).
- Exit code `0` = success; `1` = a handled error, with `{"error": "..."}` on
  stdout (in `--json` mode) or a plain message on stderr (without it).
- `scoot move` and `scoot slim` are the exception to "0 = success, 1 = error":
  partial success (some files moved/compressed, some failed) still exits `0`
  with the failures listed in an `errors` array. They only exit `1` when
  *nothing* succeeded and there were errors.

```bash
result=$(scoot dest list --json)   # parse $result; check $?
```

## Common invocations

```bash
scoot dest list --json                                   # configured destination folders
scoot dest add ~/Documents/Invoices --json
scoot dest remove Invoices --json                         # by name or path

scoot src list --json                                     # source folders + which is active
scoot src add ~/Downloads/Inbox --json                    # adds and activates
scoot src use Downloads --json                             # switch active source

scoot list --json                                          # files in the active source (non-recursive)
scoot list ~/Downloads --json                               # files in an explicit folder

scoot move report.pdf --to Invoices --json                 # one or more files, --to name-or-path
scoot rename report.pdf --name "2026-report.pdf" --json    # in-place rename

scoot slim photo.png --json                                 # -q high|balanced|extreme (default balanced)
scoot slim a.pdf b.pptx -q extreme --json

scoot log -n 20 --json                                      # recent operations, newest first
```

Full JSON shapes for every command are documented in `docs/SPEC-cli.md`.

## No `undo`

There is deliberately no `scoot undo`. `MoveEngine`'s undo stack lives in the
process's memory only — each CLI invocation is a fresh process, so there is
nothing to undo across calls. Undo is a GUI-only feature (the running app keeps
its stack alive between actions). If you need to reverse a CLI move, just
`scoot move <file> --to <original-folder>` back.

## Path arguments

Any path argument accepts `~` and relative paths (resolved against the CLI's
current working directory). Destination/source arguments that take a
"name-or-path" try an exact name match against the store first, then fall back
to a path comparison.

## Slimmable file discovery

`scoot slim` needs the `slim` binary. It's resolved in this order: (1) inside
`Scoot.app/Contents/Resources/slim` if running from the bundled app (not
relevant to the CLI), (2) the `SCOOT_SLIM_BIN` env var, (3) `slim` on `PATH`
(what you get after running slim's own `install.sh`), (4) a developer fallback
path. Run `scoot slim <file>` and check the error message if it can't find one.
