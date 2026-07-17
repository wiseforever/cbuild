# CBuild Tools

Status bar buttons for cbuild projects.

The extension runs `cb.py` or `cb.sh` directly in the current workspace root. It does not read or execute `.vscode/tasks.json`.

## Settings

- `cbuild.executor`: `auto`, `python`, or `bash`.
- `cbuild.pythonCommand`: optional Python command. Empty means prefer `python3`, then fall back to `python`.
- `cbuild.bashCommand`: Bash command, default `bash`.
- `cbuild.bootstrapCommand`: command used by `CBuild: Bootstrap Project` when `cb.py` / `cb.sh` is missing.
- `cbuild.showButtons`: base buttons to show. Empty means show all base buttons.
- `cbuild.targets`: custom CMake targets shown as additional buttons.
- `cbuild.commands`: custom shell commands shown as additional buttons.

Example:

```jsonc
{
    "cbuild.executor": "auto",
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

When a workspace does not contain `cb.py` or `cb.sh`, the extension prompts before running `install.sh`. It does not run the bootstrap command silently.

## Development

```sh
npm install
npm run compile
```

## Package

See [docs/package.md](docs/package.md).
