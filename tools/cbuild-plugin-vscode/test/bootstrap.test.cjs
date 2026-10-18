const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const test = require("node:test");
const vm = require("node:vm");

// Exercise public commands without VS Code, shell execution, or network access.
function loadExtension({ source = 0, variant = 0, confirm = true, custom = [], settings = {},
    scripts = [], localScripts = [], workspace = "/project", home = "/home/tester",
    windows = false, availableCommands = ["python3", "python"], pathCommands = {}, lookupPath, cancelPick } = {}) {
    const paths = windows ? path.win32 : path;
    const configured = (settings.installDirectory || "~/.cbuild").trim() || "~/.cbuild";
    const directory = configured === "~" ? home : paths.resolve(home, configured.replace(/^~[\\/]/, ""));
    const files = new Map(scripts.map((script) => [paths.join(directory, script), 1]));
    for (const script of localScripts) files.set(paths.join(workspace, script), 1);
    for (const filename of Object.values(pathCommands).flat()) {
        files.set(paths.resolve(workspace || home, filename), 1);
    }
    const commands = new Map();
    const sent = [];
    const errors = [];
    const warnings = [];
    const statRequests = [];
    const pathRequests = [];
    const terminals = [];
    const picks = [];
    const disposable = { dispose() {} };
    const vscode = {
        StatusBarAlignment: { Left: 1 },
        FileType: { File: 1, Directory: 2 },
        Uri: { file: (filename) => ({ fsPath: filename }) },
        commands: {
            registerCommand(name, handler) { commands.set(name, handler); return disposable; }
        },
        workspace: {
            workspaceFolders: workspace ? [{ uri: { fsPath: workspace } }] : [],
            getConfiguration() {
                return {
                    get(key, fallback) {
                        if (key === "bootstrapCommands") return custom;
                        if (Object.hasOwn(settings, key)) return settings[key];
                        if (key === "pythonCommand") return "python3";
                        return fallback;
                    }
                };
            },
            onDidChangeConfiguration() { return disposable; },
            onDidChangeWorkspaceFolders() { return disposable; },
            fs: {
                async stat(uri) {
                    statRequests.push(uri.fsPath);
                    if (files.has(uri.fsPath)) return { type: files.get(uri.fsPath) };
                    if (lookupPath !== undefined) {
                        const stat = await fs.promises.stat(uri.fsPath);
                        return { type: stat.isFile() ? 1 : 2 };
                    }
                    throw new Error("not found");
                }
            }
        },
        window: {
            terminals,
            createStatusBarItem() { return { show() {}, dispose() {} }; },
            onDidCloseTerminal() { return disposable; },
            createTerminal(options) {
                const terminal = { ...options, show() {}, sendText(line) { sent.push(line); } };
                terminals.push(terminal);
                return terminal;
            },
            async showQuickPick(items, options) {
                picks.push(items.map((item) => item.label));
                const isVariant = options.title === "CBuild bootstrap script";
                if (cancelPick === (isVariant ? "variant" : "source")) return undefined;
                return items[isVariant ? variant : source];
            },
            async showWarningMessage(message) { warnings.push(message); return confirm ? "运行" : "取消"; },
            showErrorMessage(message) { errors.push(message); }
        }
    };
    const filename = path.join(__dirname, "../out/extension.js");
    const exports = {};
    const cp = {
        execFile(command, args, ...rest) {
            const callback = rest.at(-1);
            if (lookupPath !== undefined) {
                return require("node:child_process").execFile(command, args,
                    { ...rest[0], env: { ...process.env, PATH: lookupPath } }, callback);
            }
            const pathOnly = command === "where" && args[0].startsWith("$PATH:");
            const name = command === "where" ? args[0].replace(/^\$PATH:/, "") : /command -v '([^']+)'/.exec(args[1])[1];
            pathRequests.push({ name, cwd: rest[0]?.cwd, command, args: [...args] });
            const matches = Object.hasOwn(pathCommands, name) ? [pathCommands[name]].flat() : [];
            // Model the cwd-first behavior of bare Windows `where`, rather
            // than assuming that all its output necessarily comes from PATH.
            if (command === "where" && !pathOnly && rest[0]?.cwd) {
                const local = paths.join(rest[0].cwd, name);
                if (files.get(local) === 1) matches.unshift(local);
            }
            const found = matches.length > 0 || availableCommands.includes(name);
            callback(found ? null : new Error("not found"), matches.join(windows ? "\r\n" : "\n"), "");
            return { on() {} };
        }
    };
    vm.runInNewContext(fs.readFileSync(filename, "utf8"), {
        exports,
        require(name) {
            if (name === "vscode") return vscode;
            if (name === "os") return { homedir: () => home };
            if (name === "path") return paths;
            if (name === "child_process") return cp;
            return require(name);
        },
        process: { platform: windows ? "win32" : "linux" },
        console
    }, { filename });
    exports.activate({ subscriptions: [] });
    return { commands, sent, errors, warnings, statRequests, pathRequests, terminals, picks, files, directory,
        install(script) { files.set(paths.join(directory, script), 1); } };
}

test("real POSIX PATH lookup selects runnable scripts before falling back", { skip: process.platform === "win32" }, async (t) => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cbuild-path-test-"));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    const bin = path.join(root, "bin");
    fs.mkdirSync(bin);
    // Isolate PATH completely; sh is only needed to run the command -v builtin.
    fs.symlinkSync("/bin/sh", path.join(bin, "sh"));
    fs.writeFileSync(path.join(bin, "cb.py"), "# lookup fixture; never executed\n", { mode: 0o755 });
    const harness = loadExtension({ workspace: root, home: path.join(root, "home"), scripts: ["cb.sh"], lookupPath: bin });
    await harness.commands.get("cbuild.build")();
    assert.equal(harness.sent[0], `python3 ${path.join(bin, "cb.py")} -b`);
    fs.writeFileSync(path.join(bin, "cb.sh"), "# lookup fixture; never executed\n", { mode: 0o755 });
    await harness.commands.get("cbuild.build")();
    assert.equal(harness.sent[1], `bash ${path.join(bin, "cb.sh")} -b`);
    fs.unlinkSync(path.join(bin, "cb.py"));
    fs.chmodSync(path.join(bin, "cb.sh"), 0o644);
    await harness.commands.get("cbuild.build")();
    assert.equal(harness.sent[2], `bash ${path.join(root, "home/.cbuild/cb.sh")} -b`);
});

test("PATH Bash wins over PATH Python and both fallback variants", async () => {
    const harness = loadExtension({ scripts: ["cb.sh", "cb.py"],
        pathCommands: { "cb.sh": "/usr/local/bin/cb.sh", "cb.py": "/usr/bin/cb.py" } });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, ["bash /usr/local/bin/cb.sh -b"]);
    assert.deepEqual(harness.pathRequests.map((request) => request.name), ["cb.sh"]);
    assert.deepEqual(harness.statRequests, ["/usr/local/bin/cb.sh"]);
});

test("PATH Python wins over fallback Bash when PATH has no cb.sh", async () => {
    const harness = loadExtension({ scripts: ["cb.sh", "cb.py"], pathCommands: { "cb.py": "/usr/local/bin/cb.py" } });
    await harness.commands.get("cbuild.generate")();
    assert.deepEqual(harness.sent, ["python3 /usr/local/bin/cb.py -g"]);
    assert.deepEqual(harness.statRequests, ["/usr/local/bin/cb.py"]);
});

test("both PATH variants are checked before falling back to ~/.cbuild", async () => {
    const harness = loadExtension({ scripts: ["cb.sh"] });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.pathRequests.map((request) => request.name), ["cb.sh", "cb.py"]);
    assert.deepEqual(harness.sent, ["bash /home/tester/.cbuild/cb.sh -b"]);
});

for (const [executor, name, other, runner] of [["bash", "cb.sh", "cb.py", "bash"], ["python", "cb.py", "cb.sh", "python3"]]) {
    test(`explicit ${executor} selects its PATH variant before fallback`, async () => {
        const harness = loadExtension({ settings: { executor }, scripts: [name],
            pathCommands: { [name]: `/usr/local/bin/${name}`, [other]: `/usr/local/bin/${other}` } });
        await harness.commands.get("cbuild.build")();
        assert.deepEqual(harness.sent, [`${runner} /usr/local/bin/${name} -b`]);
        assert.deepEqual(harness.pathRequests.map((request) => request.name), [name]);
    });

    test(`explicit ${executor} falls back only to the requested variant`, async () => {
        const harness = loadExtension({ settings: { executor }, scripts: [name],
            pathCommands: { [other]: `/usr/local/bin/${other}` } });
        await harness.commands.get("cbuild.build")();
        assert.deepEqual(harness.sent, [`${runner} /home/tester/.cbuild/${name} -b`]);
        assert.deepEqual(harness.pathRequests.map((request) => request.name), [name]);
    });
}

test("configured fallback directory never overrides PATH", async () => {
    const harness = loadExtension({ settings: { installDirectory: "/opt/fallback" }, scripts: ["cb.sh"],
        pathCommands: { "cb.py": "/usr/local/bin/cb.py" } });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, ["python3 /usr/local/bin/cb.py -b"]);
});

for (const [command, option] of [["cbuild.installVscode", "--vscode"], ["cbuild.installConfig", "--config"]]) {
    test(`${option} prefers the PATH installer over the fallback installer`, async () => {
        const harness = loadExtension({ scripts: ["cb_install.sh"], workspace: "/my project",
            pathCommands: { "cb_install.sh": "/opt/global tools/cb_install.sh" } });
        await harness.commands.get(command)();
        assert.deepEqual(harness.sent, [`bash "/opt/global tools/cb_install.sh" ${option} "/my project"`]);
        assert.deepEqual(harness.statRequests, ["/opt/global tools/cb_install.sh"]);
    });
}

test("a PATH lookup result must be a file before it suppresses fallback", async () => {
    const harness = loadExtension({ scripts: ["cb.sh"], pathCommands: { "cb.sh": "/opt/not-a-file" } });
    harness.files.set("/opt/not-a-file", 2);
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, ["bash /home/tester/.cbuild/cb.sh -b"]);
});

test("relative PATH entries are resolved against the project discovery cwd", async () => {
    const harness = loadExtension({ pathCommands: { "cb.sh": "bin/cb.sh" } });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, ["bash /project/bin/cb.sh -b"]);
    assert.equal(harness.pathRequests[0].cwd, "/project");
});

for (const [script, runner] of [["cb.sh", "bash"], ["cb.py", "python3"]]) {
    test(`Windows ${script} in cwd cannot shadow the PATH script`, async () => {
        const harness = loadExtension({ windows: true, workspace: "D:\\project", home: "C:\\Users\\Tester",
            localScripts: ["cb.sh", "cb.py"], pathCommands: { [script]: `C:\\global tools\\${script}` } });
        await harness.commands.get("cbuild.build")();
        assert.deepEqual(harness.sent, [`${runner} "C:/global tools/${script}" -b`]);
        assert.ok(harness.pathRequests.every((request) => request.args[0] === `$PATH:${request.name}`));
        assert.ok(harness.statRequests.every((filename) => !filename.startsWith("D:\\project\\")));
    });

    test(`Windows cwd scripts do not prevent the ${script} directory fallback`, async () => {
        const harness = loadExtension({ windows: true, workspace: "D:\\project", home: "C:\\Users\\Tester",
            localScripts: ["cb.sh", "cb.py"], scripts: [script] });
        await harness.commands.get("cbuild.build")();
        assert.deepEqual(harness.sent, [`${runner} C:/Users/Tester/.cbuild/${script} -b`]);
    });
}

test("Windows cwd scripts alone do not count as a global installation", async () => {
    const harness = loadExtension({ windows: true, workspace: "D:\\project", home: "C:\\Users\\Tester",
        localScripts: ["cb.sh", "cb.py"] });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, []);
    assert.match(harness.errors[0], /not found on PATH/);
});

for (const [command, option] of [["cbuild.installVscode", "--vscode"], ["cbuild.installConfig", "--config"]]) {
    test(`Windows ${option} ignores the cwd installer when PATH has an installer`, async () => {
        const harness = loadExtension({ windows: true, workspace: "D:\\project", home: "C:\\Users\\Tester",
            localScripts: ["cb_install.sh"], pathCommands: { "cb_install.sh": "C:\\global\\cb_install.sh" } });
        await harness.commands.get(command)();
        assert.deepEqual(harness.sent, [`bash C:/global/cb_install.sh ${option} D:/project`]);
        assert.deepEqual(harness.pathRequests[0].args, ["$PATH:cb_install.sh"]);
    });

    test(`Windows ${option} falls back to the installed copy, not the cwd installer`, async () => {
        const harness = loadExtension({ windows: true, workspace: "D:\\project", home: "C:\\Users\\Tester",
            localScripts: ["cb_install.sh"], scripts: ["cb_install.sh"] });
        await harness.commands.get(command)();
        assert.deepEqual(harness.sent, [`bash C:/Users/Tester/.cbuild/cb_install.sh ${option} D:/project`]);
    });
}

test("Windows still honors a workspace directory explicitly included in PATH", async () => {
    const harness = loadExtension({ windows: true, workspace: "D:\\project", home: "C:\\Users\\Tester",
        localScripts: ["cb.sh"], pathCommands: { "cb.sh": "D:\\project\\cb.sh" } });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, ["bash D:/project/cb.sh -b"]);
    assert.deepEqual(harness.pathRequests[0].args, ["$PATH:cb.sh"]);
});

test("Windows where results support multiple CRLF-separated paths and spaces", async () => {
    const harness = loadExtension({ windows: true, home: "C:\\Users\\Test User", workspace: "D:\\project",
        pathCommands: { "cb.sh": ["C:\\missing\\cb.sh", "C:\\global tools\\cb.sh"] } });
    harness.files.delete("C:\\missing\\cb.sh");
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, ['bash "C:/global tools/cb.sh" -b']);
    assert.equal(harness.pathRequests[0].command, "where");
});

test("PATH Python with a missing interpreter is reported, not hidden by fallback Bash", async () => {
    const harness = loadExtension({ scripts: ["cb.sh"], pathCommands: { "cb.py": "/opt/cb.py" },
        settings: { pythonCommand: "" }, availableCommands: [] });
    await harness.commands.get("cbuild.build")();
    assert.deepEqual(harness.sent, []);
    assert.match(harness.errors[0], /Neither python3 nor python/);
});

for (const [source, host] of [[0, "github.com"], [1, "gitee.com"]]) {
    for (const [variant, name, script, runner] of [[0, "bash", "cb.sh", "bash"], [1, "python", "cb.py", "python3"]]) {
        test(`${host} installs global ${name}, then buttons use its absolute path`, async () => {
            const harness = loadExtension({ source, variant });
            await harness.commands.get("cbuild.bootstrapProject")();
            assert.equal(harness.sent.length, 1);
            assert.ok(harness.sent[0].includes(host));
            assert.ok(harness.sent[0].endsWith(`| bash -s -- --global --${name} --prefix /home/tester/.cbuild`));
            assert.equal(harness.picks[1][0], "Bash (cb.sh)");
            harness.install(script);
            await harness.commands.get("cbuild.generate")();
            assert.equal(harness.sent[1], `${runner} /home/tester/.cbuild/${script} -g`);
            assert.equal(harness.terminals[0].cwd.fsPath, "/project");
            assert.deepEqual(harness.errors, []);
        });
    }
}

test("auto prefers global Bash even if Python and workspace scripts exist", async () => {
    const harness = loadExtension({ scripts: ["cb.sh", "cb.py"], localScripts: ["cb.sh", "cb.py"] });
    await harness.commands.get("cbuild.build")();
    await harness.commands.get("cbuild.run")();
    assert.deepEqual(harness.sent, ["bash /home/tester/.cbuild/cb.sh -b", "bash /home/tester/.cbuild/cb.sh -r"]);
    assert.deepEqual(harness.terminals.map((terminal) => terminal.name), ["cbuild", "run"]);
    assert.ok(harness.statRequests.every((filename) => filename.startsWith(harness.directory + "/")));
});

test("explicit Python overrides Bash preference", async () => {
    const harness = loadExtension({ scripts: ["cb.sh", "cb.py"], settings: { executor: "python" } });
    await harness.commands.get("cbuild.generate")();
    assert.deepEqual(harness.sent, ["python3 /home/tester/.cbuild/cb.py -g"]);
});

for (const executor of ["bash", "python"]) {
    test(`explicit ${executor} does not silently switch to the other variant`, async () => {
        const harness = loadExtension({ scripts: [executor === "bash" ? "cb.py" : "cb.sh"], settings: { executor } });
        await harness.commands.get("cbuild.build")();
        assert.deepEqual(harness.sent, []);
        assert.match(harness.errors[0], /Global .* not found/);
    });
}

test("workspace-local scripts are never used as fallback", async () => {
    const harness = loadExtension({ localScripts: ["cb.sh", "cb.py"] });
    await harness.commands.get("cbuild.generate")();
    assert.deepEqual(harness.sent, []);
    assert.match(harness.errors[0], /Global cb.sh or cb.py not found/);
});

test("a directory named cb.sh is not treated as a script", async () => {
    const harness = loadExtension({ scripts: ["cb.py"] });
    harness.files.set(path.join(harness.directory, "cb.sh"), 2);
    await harness.commands.get("cbuild.generate")();
    assert.deepEqual(harness.sent, ["python3 /home/tester/.cbuild/cb.py -g"]);
});

test("Python command probing falls back to python", async () => {
    const harness = loadExtension({ scripts: ["cb.py"], settings: { pythonCommand: "" }, availableCommands: ["python"] });
    await harness.commands.get("cbuild.generate")();
    assert.deepEqual(harness.sent, ["python /home/tester/.cbuild/cb.py -g"]);
});

test("missing Python interpreter does not send a command", async () => {
    const harness = loadExtension({ scripts: ["cb.py"], settings: { pythonCommand: "" }, availableCommands: [] });
    await harness.commands.get("cbuild.generate")();
    assert.deepEqual(harness.sent, []);
    assert.match(harness.errors[0], /Neither python3 nor python/);
});

test("custom global directory is used by both installation and execution", async () => {
    const harness = loadExtension({ settings: { installDirectory: "/opt/global tools" }, scripts: ["cb.sh"] });
    await harness.commands.get("cbuild.bootstrapProject")();
    await harness.commands.get("cbuild.runTarget")("deploy");
    assert.ok(harness.sent[0].endsWith('--global --bash --prefix "/opt/global tools"'));
    assert.equal(harness.sent[1], 'bash "/opt/global tools/cb.sh" -b --target deploy');
});

test("relative global directory settings are home-relative", async () => {
    const harness = loadExtension({ settings: { installDirectory: "tools/cbuild" }, scripts: ["cb.sh"] });
    await harness.commands.get("cbuild.build")();
    assert.equal(harness.sent[0], "bash /home/tester/tools/cbuild/cb.sh -b");
});

for (const [command, option] of [["cbuild.installVscode", "--vscode"], ["cbuild.installConfig", "--config"]]) {
    test(`${option} uses the global installer and an explicit project directory`, async () => {
        const harness = loadExtension({ scripts: ["cb_install.sh"], workspace: "/my project" });
        await harness.commands.get(command)();
        assert.deepEqual(harness.sent, [`bash /home/tester/.cbuild/cb_install.sh ${option} "/my project"`]);
        assert.match(harness.warnings[0], /cbuild_bak/);
    });

    test(`${option} requires confirmation`, async () => {
        const harness = loadExtension({ scripts: ["cb_install.sh"], confirm: false });
        await harness.commands.get(command)();
        assert.deepEqual(harness.sent, []);
    });

    test(`${option} reports a missing global installer`, async () => {
        const harness = loadExtension();
        await harness.commands.get(command)();
        assert.deepEqual(harness.sent, []);
        assert.match(harness.errors[0], /Global cbuild installer not found/);
    });
}

test("Windows paths are passed with forward slashes and spaces quoted", async () => {
    const harness = loadExtension({ windows: true, home: "C:\\Users\\Test User", workspace: "D:\\my project",
        scripts: ["cb.sh", "cb_install.sh"] });
    await harness.commands.get("cbuild.build")();
    await harness.commands.get("cbuild.installConfig")();
    assert.deepEqual(harness.sent, [
        'bash "C:/Users/Test User/.cbuild/cb.sh" -b',
        'bash "C:/Users/Test User/.cbuild/cb_install.sh" --config "D:/my project"'
    ]);
});

for (const cancelPick of ["source", "variant"]) {
    test(`cancelled ${cancelPick} selection sends no command`, async () => {
        const harness = loadExtension({ cancelPick });
        await harness.commands.get("cbuild.bootstrapProject")();
        assert.deepEqual(harness.sent, []);
    });
}

test("cancelled global installation sends no command", async () => {
    const harness = loadExtension({ confirm: false });
    await harness.commands.get("cbuild.bootstrapProject")();
    assert.deepEqual(harness.sent, []);
});

test("custom installation commands are not rewritten", async () => {
    const harness = loadExtension({ custom: [{ command: "custom-python-installer", bashCommand: "custom-bash-installer" }] });
    await harness.commands.get("cbuild.bootstrapProject")();
    assert.deepEqual(harness.sent, ["custom-bash-installer"]);
});

test("global and project setup commands require a workspace", async () => {
    const empty = loadExtension({ workspace: null });
    for (const command of ["cbuild.bootstrapProject", "cbuild.installVscode", "cbuild.installConfig", "cbuild.build"]) {
        await empty.commands.get(command)();
    }
    assert.deepEqual(empty.sent, []);
    assert.equal(empty.errors.length, 4);
});
