# CBuild Tools

Status bar buttons for cbuild projects.

The extension runs `cb.py` or `cb.sh` directly in the current workspace root. It does not read or execute `.vscode/tasks.json`.

`CBuild: Bootstrap Project` is always available from the Command Palette and the Explorer context menu. It asks you to select an install source, then the Python (`cb.py`) or Bash (`cb.sh`) script, and finally confirm the command before running it in the `cbuild` terminal. The extension does not show a startup prompt or run an install command silently.

Conan, generate, build, switch, clean, custom targets, and custom commands use the `cbuild` terminal. The run button uses a separate `run` terminal so a running application cannot consume later build commands.

## Settings

- `cbuild.executor`: `auto`, `python`, or `bash`.
- `cbuild.pythonCommand`: optional Python command. Empty means prefer `python3`, then fall back to `python`.
- `cbuild.bashCommand`: Bash command, default `bash`.
- `cbuild.bootstrapCommands`: bootstrap source list. Empty means use the built-in GitHub and Gitee sources. `command` installs Python; optional `bashCommand` installs Bash.
- `cbuild.showButtons`: base buttons to show. Empty means show all base buttons.
- `cbuild.targets`: custom CMake targets shown as additional buttons.
- `cbuild.commands`: custom shell commands shown as additional buttons.

Example:

```jsonc
{
    "cbuild.executor": "auto",
    "cbuild.bootstrapCommands": [
        {
            "label": "GitHub",
            "command": "curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash",
            "bashCommand": "curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --bash",
            "description": "github.com/wiseforever/cbuild"
        },
        {
            "label": "Gitee",
            "command": "curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash",
            "bashCommand": "curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --bash",
            "description": "gitee.com/wiseforever/cbuild"
        }
    ],
    "cbuild.targets": [
        {
            "label": "$(package)",
            "target": "deploy",
            "tooltip": "build deploy target"
        },
        {
            "label": "$(beaker)",
            "target": "test",
            "tooltip": "build test target"
        }
    ],
    "cbuild.commands": [
        {
            "label": "$(terminal)",
            "command": "echo hello",
            "tooltip": "run custom command"
        }
    ]
}
```

## Development

```sh
npm install
npm run compile
```

## Package

See [docs/package.md](docs/package.md).
