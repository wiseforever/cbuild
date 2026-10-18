import * as cp from "child_process";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";

type Executor = "auto" | "python" | "bash";
type BaseActionId = "conan" | "generate" | "build" | "run" | "switch" | "clean";

interface BaseAction {
    id: BaseActionId;
    label: string;
    tooltip: string;
    args: string[];
}

interface TargetConfig {
    label?: string;
    target?: string;
    tooltip?: string;
}

interface CommandConfig {
    label?: string;
    command?: string;
    tooltip?: string;
}

interface BootstrapCommandConfig {
    label?: string;
    command?: string;
    bashCommand?: string;
    description?: string;
}

interface ResolvedBootstrapCommand {
    label: string;
    command: string;
    bashCommand?: string;
    description: string;
}

interface ResolvedRunner {
    command: string;
    script: string;
}

const cbuildTerminalName = "cbuild";
const runTerminalName = "run";
const defaultBootstrapCommands: ResolvedBootstrapCommand[] = [
    {
        label: "GitHub",
        command: "curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --global --python",
        bashCommand: "curl -fsSL https://github.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --global --bash",
        description: "github.com/wiseforever/cbuild"
    },
    {
        label: "Gitee",
        command: "curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --global --python",
        bashCommand: "curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --global --bash",
        description: "gitee.com/wiseforever/cbuild"
    }
];

const baseActions: BaseAction[] = [
    {
        id: "conan",
        label: "$(archive)",
        tooltip: "conan",
        args: ["--conan"]
    },
    {
        id: "generate",
        label: "$(gear)",
        tooltip: "generate cmake cache",
        args: ["-g"]
    },
    {
        id: "build",
        label: "$(wrench)",
        tooltip: "build",
        args: ["-b"]
    },
    {
        id: "run",
        label: "$(run)",
        tooltip: "run",
        args: ["-r"]
    },
    {
        id: "switch",
        label: "$(arrow-swap)",
        tooltip: "Debug/Release switch",
        args: ["-t"]
    },
    {
        id: "clean",
        label: "$(trash)",
        tooltip: "clean",
        args: ["-c"]
    }
];

let statusItems: vscode.StatusBarItem[] = [];
let cbuildTerminal: vscode.Terminal | undefined;
let runTerminal: vscode.Terminal | undefined;

export function activate(context: vscode.ExtensionContext): void {
    for (const action of baseActions) {
        context.subscriptions.push(
            vscode.commands.registerCommand(`cbuild.${action.id}`, () => runBaseAction(action.id))
        );
    }

    context.subscriptions.push(
        vscode.commands.registerCommand("cbuild.runTarget", (target?: TargetConfig | string) => runTarget(target)),
        vscode.commands.registerCommand("cbuild.runCommand", (command?: CommandConfig | string) => runCustomCommand(command)),
        vscode.commands.registerCommand("cbuild.bootstrapProject", () => bootstrapProject()),
        vscode.commands.registerCommand("cbuild.installVscode", () => installProjectFiles("--vscode")),
        vscode.commands.registerCommand("cbuild.installConfig", () => installProjectFiles("--config")),
        vscode.commands.registerCommand("cbuild.refreshButtons", () => refreshButtons(context)),
        vscode.workspace.onDidChangeConfiguration((event) => {
            if (event.affectsConfiguration("cbuild")) {
                refreshButtons(context);
            }
        }),
        vscode.workspace.onDidChangeWorkspaceFolders(() => {
            refreshButtons(context);
        }),
        vscode.window.onDidCloseTerminal((closedTerminal) => {
            if (closedTerminal === cbuildTerminal) {
                cbuildTerminal = undefined;
            }
            if (closedTerminal === runTerminal) {
                runTerminal = undefined;
            }
        })
    );

    refreshButtons(context);
}

export function deactivate(): void {
    disposeStatusItems();
}

function refreshButtons(context: vscode.ExtensionContext): void {
    disposeStatusItems();

    if (!getWorkspaceFolder()) {
        return;
    }

    for (const action of getVisibleBaseActions()) {
        const item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
        item.text = action.label;
        item.tooltip = action.tooltip;
        item.command = `cbuild.${action.id}`;
        item.show();
        statusItems.push(item);
    }

    for (const target of getTargets()) {
        const normalized = normalizeTarget(target);
        if (!normalized) {
            continue;
        }

        const item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 90);
        item.text = normalized.label;
        item.tooltip = normalized.tooltip;
        item.command = {
            command: "cbuild.runTarget",
            title: "CBuild: Run Custom Target",
            arguments: [normalized]
        };
        item.show();
        statusItems.push(item);
    }

    for (const command of getCommands()) {
        const normalized = normalizeCommand(command);
        if (!normalized) {
            continue;
        }

        const item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 80);
        item.text = normalized.label;
        item.tooltip = normalized.tooltip;
        item.command = {
            command: "cbuild.runCommand",
            title: "CBuild: Run Custom Command",
            arguments: [normalized]
        };
        item.show();
        statusItems.push(item);
    }
}

function disposeStatusItems(): void {
    for (const item of statusItems) {
        item.dispose();
    }
    statusItems = [];
}

async function runBaseAction(id: BaseActionId): Promise<void> {
    const action = baseActions.find((candidate) => candidate.id === id);
    if (!action) {
        void vscode.window.showErrorMessage(`Unknown cbuild action: ${id}`);
        return;
    }

    await runCbuild(action.args, action.id === "run" ? "run" : "cbuild");
}

async function runTarget(value?: TargetConfig | string): Promise<void> {
    const target = await resolveTarget(value);
    if (!target) {
        return;
    }

    await runCbuild(["-b", "--target", target]);
}

async function runCustomCommand(value?: CommandConfig | string): Promise<void> {
    const command = await resolveCommand(value);
    if (!command) {
        return;
    }

    runTerminalCommand(command);
}

async function bootstrapProject(): Promise<void> {
    const workspaceFolder = getWorkspaceFolder();
    if (!workspaceFolder) {
        void vscode.window.showErrorMessage("CBuild requires an open workspace folder.");
        return;
    }

    const bootstrapCommand = await pickBootstrapCommand();
    if (!bootstrapCommand) {
        return;
    }

    const selectedCommand = await pickBootstrapVariant(bootstrapCommand);
    if (!selectedCommand) {
        return;
    }

    await confirmInstall(selectedCommand, "是否全局安装或更新 cbuild？项目配置不会自动安装。");
}

async function installProjectFiles(option: "--vscode" | "--config"): Promise<void> {
    const workspaceFolder = getWorkspaceFolder();
    if (!workspaceFolder) {
        void vscode.window.showErrorMessage("CBuild requires an open workspace folder.");
        return;
    }

    const installer = await findGlobalScript(["cb_install.sh"]);
    if (!installer) {
        void vscode.window.showErrorMessage(
            `Global cbuild installer not found on PATH or in ${getGlobalInstallDirectory()}. Run 'CBuild: Install / Update Global cbuild' first, or configure cbuild.installDirectory.`
        );
        return;
    }

    const commandLine = `${getBashCommand()} ${[toShellPath(installer.filename), option, toShellPath(workspaceFolder.uri.fsPath)].map(quoteShellArg).join(" ")}`;
    const files = option === "--vscode" ? ".vscode 模板" : "cb.conf";
    await confirmInstall(commandLine, `是否为当前项目安装 ${files}？已有文件会先移入 cbuild_bak 备份。`);
}

async function confirmInstall(commandLine: string, message: string): Promise<void> {
    const runInstall = "运行";
    const picked = await vscode.window.showWarningMessage(
        `${message}\n\n${commandLine}`,
        {
            modal: true
        },
        runInstall,
        "取消"
    );

    if (picked === runInstall) {
        runTerminalCommand(commandLine);
    }
}

async function resolveTarget(value?: TargetConfig | string): Promise<string | undefined> {
    if (typeof value === "string") {
        return value.trim() || undefined;
    }

    if (value?.target?.trim()) {
        return value.target.trim();
    }

    const targets = getTargets()
        .map((target) => normalizeTarget(target))
        .filter((target): target is Required<TargetConfig> => Boolean(target));

    if (targets.length > 0) {
        const picked = await vscode.window.showQuickPick(
            targets.map((target) => ({
                label: target.label,
                description: target.target,
                detail: target.tooltip,
                target: target.target
            })),
            {
                title: "CBuild target",
                placeHolder: "Select a target to build"
            }
        );
        return picked?.target;
    }

    const input = await vscode.window.showInputBox({
        title: "CBuild target",
        prompt: "Target passed to cb.py/cb.sh with --target",
        placeHolder: "deploy"
    });
    return input?.trim() || undefined;
}

async function resolveCommand(value?: CommandConfig | string): Promise<string | undefined> {
    if (typeof value === "string") {
        return value.trim() || undefined;
    }

    if (value?.command?.trim()) {
        return value.command.trim();
    }

    const commands = getCommands()
        .map((command) => normalizeCommand(command))
        .filter((command): command is Required<CommandConfig> => Boolean(command));

    if (commands.length > 0) {
        const picked = await vscode.window.showQuickPick(
            commands.map((command) => ({
                label: command.label,
                description: command.command,
                detail: command.tooltip,
                command: command.command
            })),
            {
                title: "CBuild command",
                placeHolder: "Select a command to run"
            }
        );
        return picked?.command;
    }

    const input = await vscode.window.showInputBox({
        title: "CBuild command",
        prompt: "Shell command to run in the workspace root",
        placeHolder: "echo hello"
    });
    return input?.trim() || undefined;
}

async function runCbuild(args: string[], terminalKind: "cbuild" | "run" = "cbuild"): Promise<void> {
    const workspaceFolder = getWorkspaceFolder();
    if (!workspaceFolder) {
        void vscode.window.showErrorMessage("CBuild requires an open workspace folder.");
        return;
    }

    const runner = await resolveRunner();
    if (!runner) {
        return;
    }

    const commandLine = `${runner.command} ${[runner.script, ...args].map(quoteShellArg).join(" ")}`;
    runTerminalCommand(commandLine, terminalKind);
}

function runTerminalCommand(commandLine: string, terminalKind: "cbuild" | "run" = "cbuild"): void {
    const workspaceFolder = getWorkspaceFolder();
    if (!workspaceFolder) {
        void vscode.window.showErrorMessage("CBuild requires an open workspace folder.");
        return;
    }

    const activeTerminal = getOrCreateTerminal(workspaceFolder, terminalKind);
    activeTerminal.show();
    activeTerminal.sendText(commandLine);
}

function getGlobalInstallDirectory(): string {
    const configured = vscode.workspace.getConfiguration("cbuild").get<string>("installDirectory", "~/.cbuild").trim() || "~/.cbuild";
    if (configured === "~") {
        return os.homedir();
    }
    if (/^~[\\/]/.test(configured)) {
        return path.resolve(os.homedir(), configured.slice(2));
    }
    // Relative settings are home-relative, never workspace-relative.
    return path.resolve(os.homedir(), configured);
}

function toShellPath(value: string): string {
    return value.replace(/\\/g, "/");
}

async function findGlobalScript(names: string[]): Promise<{ name: string; filename: string } | undefined> {
    // Search the entire environment tier before considering any fallback file:
    // PATH cb.py must win over ~/.cbuild/cb.sh when PATH has no cb.sh.
    for (const name of names) {
        const filename = await findScriptOnPath(name);
        if (filename) {
            return { name, filename };
        }
    }
    for (const name of names) {
        const filename = path.join(getGlobalInstallDirectory(), name);
        if (await fileExists(filename)) {
            return { name, filename };
        }
    }
    return undefined;
}

async function resolveRunner(): Promise<ResolvedRunner | undefined> {
    const executor = vscode.workspace.getConfiguration("cbuild").get<Executor>("executor", "auto");
    const names = executor === "auto" ? ["cb.sh", "cb.py"] : [executor === "bash" ? "cb.sh" : "cb.py"];
    const located = await findGlobalScript(names);
    if (located) {
        if (located.name === "cb.sh") {
            return { command: getBashCommand(), script: toShellPath(located.filename) };
        }
        const command = await resolvePythonCommand();
        return command ? { command, script: toShellPath(located.filename) } : undefined;
    }

    void vscode.window.showErrorMessage(
        `Global ${names.join(" or ")} not found on PATH or in ${getGlobalInstallDirectory()}. Run 'CBuild: Install / Update Global cbuild' first, or configure cbuild.installDirectory.`
    );
    return undefined;
}

async function resolvePythonCommand(): Promise<string | undefined> {
    const configured = vscode.workspace.getConfiguration("cbuild").get<string>("pythonCommand", "").trim();
    if (configured) {
        return configured;
    }

    if (await commandExists("python3")) {
        return "python3";
    }

    if (await commandExists("python")) {
        return "python";
    }

    void vscode.window.showErrorMessage("Neither python3 nor python was found on PATH.");
    return undefined;
}

function getBashCommand(): string {
    const configured = vscode.workspace.getConfiguration("cbuild").get<string>("bashCommand", "bash").trim();
    return configured || "bash";
}

function getVisibleBaseActions(): BaseAction[] {
    const configured = vscode.workspace.getConfiguration("cbuild").get<string[]>("showButtons", []);
    if (!configured || configured.length === 0) {
        return baseActions;
    }

    const requested = new Set(configured);
    return baseActions.filter((action) => requested.has(action.id));
}

function getTargets(): TargetConfig[] {
    return vscode.workspace.getConfiguration("cbuild").get<TargetConfig[]>("targets", []);
}

function getCommands(): CommandConfig[] {
    return vscode.workspace.getConfiguration("cbuild").get<CommandConfig[]>("commands", []);
}

function getBootstrapCommands(): ResolvedBootstrapCommand[] {
    const configured = vscode.workspace.getConfiguration("cbuild").get<BootstrapCommandConfig[]>("bootstrapCommands", []);
    const normalized = configured
        .map((command) => normalizeBootstrapCommand(command))
        .filter((command): command is ResolvedBootstrapCommand => Boolean(command));

    if (normalized.length > 0) {
        return normalized;
    }

    const prefix = ` --prefix ${quoteShellArg(toShellPath(getGlobalInstallDirectory()))}`;
    return defaultBootstrapCommands.map((command) => ({
        ...command,
        command: command.command + prefix,
        bashCommand: command.bashCommand ? command.bashCommand + prefix : undefined
    }));
}

function normalizeTarget(target: TargetConfig): Required<TargetConfig> | undefined {
    const name = target.target?.trim();
    if (!name) {
        void vscode.window.showWarningMessage("Skipped a cbuild target button because its target is empty.");
        return undefined;
    }

    return {
        target: name,
        label: target.label?.trim() || `$(package) ${name}`,
        tooltip: target.tooltip?.trim() || `build ${name} target`
    };
}

function normalizeCommand(command: CommandConfig): Required<CommandConfig> | undefined {
    const commandLine = command.command?.trim();
    if (!commandLine) {
        void vscode.window.showWarningMessage("Skipped a cbuild command button because its command is empty.");
        return undefined;
    }

    return {
        command: commandLine,
        label: command.label?.trim() || "$(terminal)",
        tooltip: command.tooltip?.trim() || commandLine
    };
}

function normalizeBootstrapCommand(command: BootstrapCommandConfig): ResolvedBootstrapCommand | undefined {
    const commandLine = command.command?.trim();
    if (!commandLine) {
        void vscode.window.showWarningMessage("Skipped a cbuild bootstrap command because its command is empty.");
        return undefined;
    }

    return {
        command: commandLine,
        bashCommand: command.bashCommand?.trim() || undefined,
        label: command.label?.trim() || commandLine,
        description: command.description?.trim() || commandLine
    };
}

async function pickBootstrapCommand(): Promise<ResolvedBootstrapCommand | undefined> {
    const commands = getBootstrapCommands();
    if (commands.length === 1) {
        return commands[0];
    }

    const picked = await vscode.window.showQuickPick(
        commands.map((command) => ({
            label: command.label,
            description: command.description,
            detail: command.command,
            command
        })),
        {
            title: "CBuild bootstrap source",
            placeHolder: "Select install.sh source"
        }
    );
    return picked?.command;
}

async function pickBootstrapVariant(command: ResolvedBootstrapCommand): Promise<string | undefined> {
    const picked = await vscode.window.showQuickPick(
        [
            {
                label: "Bash (cb.sh)",
                description: command.bashCommand ? "Install global cb.sh (recommended)" : "Configure bashCommand for this source",
                detail: command.bashCommand || "No Bash bootstrap command is configured for this source.",
                command: command.bashCommand
            },
            {
                label: "Python (cb.py)",
                description: "Install global cb.py",
                detail: command.command,
                command: command.command
            }
        ],
        {
            title: "CBuild bootstrap script",
            placeHolder: "Select Python or Bash script"
        }
    );

    if (!picked) {
        return undefined;
    }
    if (!picked.command) {
        void vscode.window.showErrorMessage("This bootstrap source has no Bash command. Add cbuild.bootstrapCommands[].bashCommand first.");
        return undefined;
    }
    return picked.command;
}

function getWorkspaceFolder(): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.[0];
}

function getOrCreateTerminal(workspaceFolder: vscode.WorkspaceFolder, terminalKind: "cbuild" | "run"): vscode.Terminal {
    const existingTerminal = terminalKind === "run" ? runTerminal : cbuildTerminal;
    if (existingTerminal) {
        return existingTerminal;
    }

    const terminalName = terminalKind === "run" ? runTerminalName : cbuildTerminalName;
    const foundTerminal = vscode.window.terminals.find((candidate) => candidate.name === terminalName);
    if (foundTerminal) {
        if (terminalKind === "run") {
            runTerminal = foundTerminal;
        } else {
            cbuildTerminal = foundTerminal;
        }
        return foundTerminal;
    }

    const createdTerminal = vscode.window.createTerminal({
        name: terminalName,
        cwd: workspaceFolder.uri
    });
    if (terminalKind === "run") {
        runTerminal = createdTerminal;
    } else {
        cbuildTerminal = createdTerminal;
    }
    return createdTerminal;
}

async function fileExists(filename: string): Promise<boolean> {
    try {
        const stat = await vscode.workspace.fs.stat(vscode.Uri.file(filename));
        return (stat.type & vscode.FileType.File) !== 0;
    } catch {
        return false;
    }
}

async function findScriptOnPath(command: string): Promise<string | undefined> {
    const cwd = getWorkspaceFolder()?.uri.fsPath || os.homedir();
    const output = await new Promise<string>((resolve) => {
        const options = { cwd, windowsHide: true, timeout: 5000 };
        const completed = (error: Error | null, stdout: string) => resolve(error ? "" : stdout);
        // Some shells report non-executable files from command -v too.
        const posixLookup = `candidate=$(command -v ${quotePosix(command)})` +
            ` && [ -f "$candidate" ] && [ -x "$candidate" ] && printf '%s\\n' "$candidate"`;
        // Bare `where name` also searches cwd. Restrict it to PATH so a
        // leftover workspace script cannot shadow an installed global script.
        const child = process.platform === "win32"
            ? cp.execFile("where", [`$PATH:${command}`], options, completed)
            : cp.execFile("sh", ["-c", posixLookup], options, completed);
        child.on("error", () => resolve(""));
    });

    // Windows `where` can return multiple matches. Resolve relative PATH
    // entries against the same directory used for command discovery.
    for (const candidate of output.split(/\r?\n/)) {
        if (!candidate.trim()) {
            continue;
        }
        const filename = path.resolve(cwd, candidate.trim());
        if (await fileExists(filename)) {
            return filename;
        }
    }
    return undefined;
}

function commandExists(command: string): Promise<boolean> {
    return new Promise((resolve) => {
        const child = process.platform === "win32"
            ? cp.execFile("where", [command], { windowsHide: true }, (error) => resolve(!error))
            : cp.execFile("sh", ["-c", `command -v ${quotePosix(command)}`], (error) => resolve(!error));

        child.on("error", () => resolve(false));
    });
}

function quoteShellArg(value: string): string {
    if (/^[A-Za-z0-9_./:=@+-]+$/.test(value)) {
        return value;
    }
    return `"${value.replace(/(["\\$`])/g, "\\$1")}"`;
}

function quotePosix(value: string): string {
    return `'${value.replace(/'/g, "'\\''")}'`;
}
