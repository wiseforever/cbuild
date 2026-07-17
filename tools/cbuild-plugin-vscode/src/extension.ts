import * as cp from "child_process";
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

interface ResolvedRunner {
    command: string;
    script: "cb.py" | "cb.sh";
}

const terminalName = "cbuild";

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
let terminal: vscode.Terminal | undefined;

export function activate(context: vscode.ExtensionContext): void {
    for (const action of baseActions) {
        context.subscriptions.push(
            vscode.commands.registerCommand(`cbuild.${action.id}`, () => runBaseAction(action.id))
        );
    }

    context.subscriptions.push(
        vscode.commands.registerCommand("cbuild.runTarget", (target?: TargetConfig | string) => runTarget(target)),
        vscode.commands.registerCommand("cbuild.refreshButtons", () => refreshButtons(context)),
        vscode.workspace.onDidChangeConfiguration((event) => {
            if (event.affectsConfiguration("cbuild")) {
                refreshButtons(context);
            }
        }),
        vscode.window.onDidCloseTerminal((closedTerminal) => {
            if (closedTerminal === terminal) {
                terminal = undefined;
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

    await runCbuild(action.args);
}

async function runTarget(value?: TargetConfig | string): Promise<void> {
    const target = await resolveTarget(value);
    if (!target) {
        return;
    }

    await runCbuild(["-b", "--target", target]);
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

async function runCbuild(args: string[]): Promise<void> {
    const workspaceFolder = getWorkspaceFolder();
    if (!workspaceFolder) {
        void vscode.window.showErrorMessage("CBuild requires an open workspace folder.");
        return;
    }

    const runner = await resolveRunner(workspaceFolder);
    if (!runner) {
        return;
    }

    const commandLine = `${runner.command} ${[runner.script, ...args].map(quoteShellArg).join(" ")}`;
    const activeTerminal = getOrCreateTerminal(workspaceFolder);
    activeTerminal.show();
    activeTerminal.sendText(commandLine);
}

async function resolveRunner(workspaceFolder: vscode.WorkspaceFolder): Promise<ResolvedRunner | undefined> {
    const config = vscode.workspace.getConfiguration("cbuild");
    const executor = config.get<Executor>("executor", "auto");

    const hasPythonScript = await fileExists(workspaceFolder, "cb.py");
    const hasBashScript = await fileExists(workspaceFolder, "cb.sh");

    if (executor === "python") {
        if (!hasPythonScript) {
            void vscode.window.showErrorMessage("cbuild.executor is python, but cb.py was not found in the workspace root.");
            return undefined;
        }
        const command = await resolvePythonCommand();
        if (!command) {
            return undefined;
        }
        return {
            command,
            script: "cb.py"
        };
    }

    if (executor === "bash") {
        if (!hasBashScript) {
            void vscode.window.showErrorMessage("cbuild.executor is bash, but cb.sh was not found in the workspace root.");
            return undefined;
        }
        return {
            command: getBashCommand(),
            script: "cb.sh"
        };
    }

    if (hasPythonScript) {
        const command = await resolvePythonCommand();
        if (!command) {
            return undefined;
        }
        return {
            command,
            script: "cb.py"
        };
    }

    if (hasBashScript) {
        return {
            command: getBashCommand(),
            script: "cb.sh"
        };
    }

    void vscode.window.showErrorMessage("No cb.py or cb.sh was found in the workspace root.");
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

function getWorkspaceFolder(): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.[0];
}

function getOrCreateTerminal(workspaceFolder: vscode.WorkspaceFolder): vscode.Terminal {
    if (terminal) {
        return terminal;
    }

    terminal = vscode.window.terminals.find((candidate) => candidate.name === terminalName);
    if (terminal) {
        return terminal;
    }

    terminal = vscode.window.createTerminal({
        name: terminalName,
        cwd: workspaceFolder.uri
    });
    return terminal;
}

async function fileExists(workspaceFolder: vscode.WorkspaceFolder, filename: string): Promise<boolean> {
    try {
        await vscode.workspace.fs.stat(vscode.Uri.joinPath(workspaceFolder.uri, filename));
        return true;
    } catch {
        return false;
    }
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
