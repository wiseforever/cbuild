# CBuild Tools

Status bar buttons for cbuild projects, using a shared global cbuild installation. The extension does not read or execute `.vscode/tasks.json`.

## Global scripts

Install cbuild once, then use it across projects. Projects only need their own `cb.conf`; they do not need copies of `cb.sh` or `cb.py`.

The extension checks the environment first. In `auto` mode, the lookup order is:

1. `cb.sh` on `PATH`.
2. `cb.py` on `PATH`.
3. `cb.sh` in the fallback directory (default `~/.cbuild`).
4. `cb.py` in the fallback directory.

A PATH-provided `cb.py` therefore wins over `~/.cbuild/cb.sh`. Explicit `bash` / `python` executors search only the requested variant, first on PATH and then in the fallback directory.

- PATH lookup uses `command -v` on POSIX and `where $PATH:<filename>` on Windows (PATH only, without the implicit current-directory search of bare `where`), in the extension host's environment. Restart/reload VS Code after changing the environment if necessary.
- Found paths are resolved and passed to the selected Bash/Python interpreter; the fallback directory does not need to be on PATH.
- `cbuild.installDirectory` sets the fallback directory and the target for built-in global installation commands. It does not override a working script already on PATH.
- `cbuild.installRelease` selects the cbuild version for installation and project files. `latest` reads the selected source's `master/LATEST` value; a tag such as `v0.1.0` pins it directly. The installer resolves the tag once and reads all files from that tag.
- `~` expands to the home directory; relative fallback settings are home-relative, not workspace-relative.
- There is no separate workspace-root script search. A project directory is only searched if you explicitly put it on PATH.

The first workspace folder is the project. New terminals start there, so cbuild loads the project's `cb.conf`. Keep the dedicated terminals in that directory when reusing them. Conan, generate, build, switch, clean, custom targets, and custom commands use the `cbuild` terminal; run uses a separate `run` terminal so a running application cannot consume build commands.

## Install and configure a project

The following commands are available in the Command Palette and Explorer context menu. All ask for confirmation before sending an installation command to the terminal; nothing is installed silently at startup.

| Command | Action |
| --- | --- |
| `CBuild: Install / Update Global cbuild` | Select GitHub/Gitee, then Bash (offered first) or Python. Built-in commands download the selected source's `master/install.sh` (or the pinned tag's `install.sh`), then pass `--global`, `--source`, `--release`, and `--prefix` matching the settings. |
| `CBuild: Install VS Code Templates (--vscode)` | Find `cb_install.sh` on PATH, then in the fallback directory; run it with `--vscode <project-root> --release <version>`. |
| `CBuild: Install Project Config (--config)` | Find `cb_install.sh` in the same order; run it with `--config <project-root> --release <version>`. |

**Known limitation:** do not run installations or updates to the same directory concurrently, including from different VS Code windows or terminals. There is no installation lock; simultaneous Bash/Python installations can remove each other's scripts even when both report success. Wait for completion before starting another update. If this happens, wait for all installers to exit, then reinstall the desired variant once.

Recommended setup:

1. If cbuild is not already available on PATH or in the fallback directory, run **Install / Update Global cbuild** once. This requires the source's `master/LATEST` value (or set `cbuild.installRelease` to an existing tag).
2. Open the project and run **Install Project Config (--config)** if it lacks `cb.conf`.
3. Optionally run **Install VS Code Templates (--vscode)**.
4. Edit `cb.conf`, then use the generate/build/run buttons.

Global installation does not install project configuration or editor templates. Project setup commands explicitly target the first workspace folder, even if a terminal's current directory has changed. Existing `cb.conf` or `.vscode` is moved to `<project-root>/cbuild_bak/` before replacement. If scripts or `cb_install.sh` cannot be found on PATH or in the fallback directory, the extension reports both lookup locations and asks you to install cbuild or adjust `cbuild.installDirectory`.

Built-in installation commands require the source's `master/LATEST` value or an existing tag. Custom `cbuild.bootstrapCommands` are not modified, so custom mirrors or local installers remain possible.

The existing command ID `cbuild.bootstrapProject` is retained for global installation, so existing keybindings remain valid. Project setup IDs are `cbuild.installVscode` and `cbuild.installConfig`.

## Settings

- `cbuild.executor`: `auto` (Bash first), `bash`, or `python`.
- `cbuild.installDirectory`: fallback directory and built-in global installation target, default `~/.cbuild` (machine setting). PATH has priority.
- `cbuild.installRelease`: cbuild version for installation and project files, default `latest` (workspace setting). Accepts `latest` or a tag such as `v0.1.0`; invalid values are rejected before any command runs.
- `cbuild.pythonCommand`: optional Python command. Empty means prefer `python3`, then fall back to `python`.
- `cbuild.bashCommand`: Bash command, default `bash`; also used to invoke global `cb_install.sh`.
- `cbuild.bootstrapCommands`: custom global installation sources. Empty uses built-in GitHub/Gitee sources driven by `cbuild.installRelease`. `command` installs Python; optional `bashCommand` installs Bash. Custom commands are sent unchanged: perform a versioned global installation into `cbuild.installDirectory` yourself, including `--release` and `--prefix` when needed.
- `cbuild.showButtons`: base buttons to show. Empty means show all base buttons.
- `cbuild.targets`: custom CMake targets shown as additional buttons.
- `cbuild.commands`: custom shell commands shown as additional buttons.

User settings example (`cbuild.installDirectory` is machine-scoped, not a workspace setting):

```jsonc
{
    "cbuild.executor": "auto",
    "cbuild.installDirectory": "~/.cbuild",
    "cbuild.installRelease": "latest",
    "cbuild.targets": [
        {
            "label": "$(package)",
            "target": "deploy",
            "tooltip": "build deploy target"
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
npm ci --ignore-scripts
npm test
```

`npm test` compiles TypeScript and tests PATH-first discovery, fallback ordering, Bash priority within each lookup tier, explicit executors, release-pinned installation commands, invalid release rejection, project template/config commands, custom fallback directories, quoting, and cancellation using a mocked VS Code API. One POSIX regression uses an isolated temporary PATH and real command lookup to verify executable permissions and fallback; it never executes the fixture scripts. Tests do not open real terminals or execute installation commands. Windows-style paths are simulated; actual Windows/macOS shells and the VS Code UI still require manual testing.

## Package

See [docs/package.md](docs/package.md).
