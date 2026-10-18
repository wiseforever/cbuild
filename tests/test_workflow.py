"""Offline integration regressions; run: python3 -m unittest discover -s tests -v."""

import configparser
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
VARIANTS = ("python", "bash")
BUILD_TOOLS = all(shutil.which(tool) for tool in ("bash", "cmake", "ninja", "gcc", "g++"))


class TemporaryProjectTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cbuild-regression-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def invoke(self, project, variant, *args):
        runner = [sys.executable, str(REPO / "cb.py")] if variant == "python" else ["bash", str(REPO / "cb.sh")]
        return subprocess.run(
            runner + list(args), cwd=project, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45,
        )

    def succeeds(self, result):
        self.assertEqual(result.returncode, 0, result.stdout)

    def project(self, name, language="CXX", body=None, generator="Ninja"):
        project = self.root / name
        project.mkdir()
        extension = "c" if language == "C" else "cpp"
        (project / "cb.conf").write_text(
            "[build]\nbuild_type = Release\ngenerator = " + generator + "\n"
            "parallel_jobs = 2\n[conan]\nenable = 0\n", encoding="utf-8",
        )
        (project / ("main." + extension)).write_text(
            '#include <stdio.h>\nint main(void) { puts("probe-ok"); return 0; }\n', encoding="utf-8",
        )
        (project / "CMakeLists.txt").write_text(
            "cmake_minimum_required(VERSION 3.10)\nproject(probe LANGUAGES " + language + ")\n"
            + (body if body is not None else "add_executable(hello main." + extension + ")\n"),
            encoding="utf-8",
        )
        return project


@unittest.skipUnless(BUILD_TOOLS, "requires Bash, CMake, Ninja, gcc and g++")
class BuildWorkflowTests(TemporaryProjectTest):
    def test_c_and_cpp_executables(self):
        for variant in VARIANTS:
            for language in ("C", "CXX"):
                for generator in ("Ninja", "Unix Makefiles"):
                    with self.subTest(variant=variant, language=language, generator=generator):
                        project = self.project(variant + language + generator, language, generator=generator)
                        self.succeeds(self.invoke(project, variant, "-g"))
                        self.succeeds(self.invoke(project, variant, "-b", "hello"))
                        self.succeeds(self.invoke(project, variant, "-b"))
                        result = self.invoke(project, variant, "--list-execs")
                        self.succeeds(result)
                        self.assertIn("hello", result.stdout)
                        for args in (("-r",), ("-r", "hello")):
                            result = self.invoke(project, variant, *args)
                            self.succeeds(result)
                            self.assertIn("probe-ok", result.stdout)

    def test_library_and_custom_targets_do_not_require_executables(self):
        for variant in VARIANTS:
            for unbuilt_executable in (False, True):
                with self.subTest(variant=variant, unbuilt_executable=unbuilt_executable):
                    body = (
                        "add_library(core STATIC main.cpp)\n"
                        'add_custom_target(deploy COMMAND ${CMAKE_COMMAND} -E touch "${CMAKE_BINARY_DIR}/deployed")\n'
                        "add_custom_target(fail COMMAND ${CMAKE_COMMAND} -E false)\n"
                    )
                    if unbuilt_executable:
                        body += "add_executable(unbuilt EXCLUDE_FROM_ALL main.cpp)\n"
                    project = self.project(variant + str(unbuilt_executable), body=body)
                    self.succeeds(self.invoke(project, variant, "-g"))
                    for args in (("-b", "--target", "deploy"), ("-b", "core"), ("-b",)):
                        self.succeeds(self.invoke(project, variant, *args))
                    self.assertTrue(list(project.glob("build/*/deployed")))
                    self.assertNotEqual(self.invoke(project, variant, "-r").returncode, 0)
                    self.assertNotEqual(self.invoke(project, variant, "-b", "fail").returncode, 0)

    def test_build_directory_tracks_final_type_after_vscode_updates(self):
        for variant in VARIANTS:
            with self.subTest(variant=variant):
                project = self.project(variant)
                vscode = project / ".vscode"
                vscode.mkdir()
                (vscode / "settings.json").write_text('{"clangd.arguments": ["--compile-commands-dir=old"]}\n')
                (vscode / "c_cpp_properties.json").write_text('{"compileCommands": "old"}\n')
                (vscode / "launch.json").write_text('{"program": "old"}\n')
                self.succeeds(self.invoke(project, variant, "-t", "Debug", "-g", "Release"))
                caches = list(project.glob("build/*/CMakeCache.txt"))
                self.assertEqual(len(caches), 1)
                self.assertTrue(caches[0].parent.name.endswith("-Release"))
                self.assertIn("CMAKE_BUILD_TYPE:STRING=Release", caches[0].read_text())
                self.assertIn("-Release", (vscode / "settings.json").read_text())
                self.assertIn("-Release", (vscode / "c_cpp_properties.json").read_text())
                config = configparser.ConfigParser()
                config.read(project / "cb.conf")
                self.assertEqual(config.get("build", "build_type"), "Debug")
                # Repeated persistent switches must invalidate the same cache too.
                self.succeeds(self.invoke(project, variant, "-t", "Release", "-t", "Debug"))
                self.assertIn("-Debug", (vscode / "settings.json").read_text())

    def test_clean_refuses_source_and_ancestors_including_symlinks(self):
        for variant in VARIANTS:
            for output in (".", "..", "../source-alias", "../parent-alias"):
                with self.subTest(variant=variant, output=output):
                    project = self.root / (variant + str(len(list(self.root.iterdir()))))
                    project.mkdir()
                    source = project / "src"
                    source.mkdir()
                    sentinel = source / "precious.cpp"
                    sentinel.write_text("must survive\n")
                    (project / "source-alias").symlink_to(source, target_is_directory=True)
                    (project / "parent-alias").symlink_to(project, target_is_directory=True)
                    (project / "cb.conf").write_text(
                        "[build]\nsource_dir = src\noutput_dir = " + output + "\n"
                        "use_output_auto_subdir = false\n"
                    )
                    result = self.invoke(project, variant, "-c")
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn("Refusing to clean", result.stdout)
                    self.assertEqual(sentinel.read_text(), "must survive\n")
                    self.assertTrue((project / "cb.conf").is_file())

    def test_missing_config_is_rejected_instead_of_using_another_directory(self):
        tools = self.root / "tools without config"
        tools.mkdir()
        for name in ("cb.py", "cb.sh"):
            shutil.copy2(REPO / name, tools / name)
        project = self.root / "project without config"
        project.mkdir()
        (project / "CMakeLists.txt").write_text(
            "cmake_minimum_required(VERSION 3.10)\nproject(no_config CXX)\n"
        )
        for variant, runner in (("python", [sys.executable, str(tools / "cb.py")]),
                                ("bash", ["bash", str(tools / "cb.sh")])):
            with self.subTest(variant=variant):
                result = subprocess.run(runner + ["-g"], cwd=project, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("Config file not found", result.stdout)
                self.assertFalse((project / "build").exists())
                result = subprocess.run(runner, cwd=project, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.succeeds(result)
                self.assertIn("Use -h for help.", result.stdout)
                for flag, marker in (("-h", "Usage:"), ("--help", "Usage:"),
                                     ("-V", "cbuild 0.1.0"), ("--version", "cbuild 0.1.0")):
                    with self.subTest(variant=variant, flag=flag):
                        result = subprocess.run(runner + [flag], cwd=project, text=True,
                                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                        self.succeeds(result)
                        self.assertIn(marker, result.stdout)
                result = subprocess.run(runner + ["--list-execs"], cwd=project, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("Config file not found", result.stdout)
        self.assertFalse((tools / "cb.conf").exists())

    def test_clean_allows_normal_build_directories(self):
        for variant in VARIANTS:
            for auto_subdir in (True, False):
                with self.subTest(variant=variant, auto_subdir=auto_subdir):
                    project = self.project(variant + str(auto_subdir))
                    if not auto_subdir:
                        config = project / "cb.conf"
                        config.write_text(config.read_text().replace(
                            "[build]\n", "[build]\nuse_output_auto_subdir = false\noutput_dir = output\n"
                        ))
                    self.succeeds(self.invoke(project, variant, "-g"))
                    caches = list(project.rglob("CMakeCache.txt"))
                    self.assertEqual(len(caches), 1)
                    build_dir = caches[0].parent
                    self.succeeds(self.invoke(project, variant, "-c"))
                    self.assertFalse(build_dir.exists())
                    self.assertTrue((project / "main.cpp").exists())
                    self.assertTrue((project / "cb.conf").exists())


@unittest.skipUnless(shutil.which("bash"), "requires Bash")
class InstallerTests(TemporaryProjectTest):
    """Exercise the release/tag installer against a local, offline curl stand-in."""

    def setUp(self):
        super().setUp()
        self.home = self.root / "home"
        self.home.mkdir()
        self.prefix = self.home / "installed tools"
        self.prefix.mkdir()
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.log = self.root / "downloads.log"
        self.env = dict(
            os.environ, HOME=str(self.home), SHELL="/bin/bash",
            PATH=str(self.bin_dir) + os.pathsep + os.environ.get("PATH", ""),
            CBUILD_TEST_REPO=str(REPO), CBUILD_TEST_LOG=str(self.log),
            CBUILD_TEST_BASE="https://cbuild.test/{tag}",
        )
        curl = self.bin_dir / "curl"
        curl.write_text(r'''#!/usr/bin/env bash
set -eu
url=""; dest=""
while (($#)); do
  case "$1" in
    -o) dest="$2"; shift 2 ;;
    --connect-timeout|--max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[[ -n "$url" && -n "$dest" ]] || exit 2
printf '%s\n' "$url" >> "$CBUILD_TEST_LOG"

fail_matches() {
  local list="$1" source="$2" tag="$3" rel="$4" item
  for item in $list; do
    [[ "$item" == "$rel" || "$item" == "$source:$rel" || "$item" == "$source:$tag:$rel" ]] && return 0
  done
  return 1
}

source=""; tag=""; rel=""
if [[ "$url" == "https://raw.githubusercontent.com/wiseforever/cbuild/master/LATEST" ]]; then
  [[ -z "${CBUILD_FAIL_LATEST:-}" ]] || exit 22
  printf '%s\n' "${CBUILD_TEST_LATEST:-v0.1.0}" > "$dest"
  exit 0
elif [[ "$url" == "https://gitee.com/wiseforever/cbuild/raw/master/LATEST" ]]; then
  [[ -z "${CBUILD_FAIL_GITEE_LATEST:-}" ]] || exit 22
  printf '%s\n' "${CBUILD_TEST_GITEE_LATEST:-${CBUILD_TEST_LATEST:-v0.1.0}}" > "$dest"
  exit 0
elif [[ "$url" =~ ^https://raw\.githubusercontent\.com/wiseforever/cbuild/([^/]+)/(.+)$ ]]; then
  source="github"; tag="${BASH_REMATCH[1]}"; rel="${BASH_REMATCH[2]}"
  fail_matches "${CBUILD_FAIL_GITHUB:-}" "$source" "$tag" "$rel" && exit 22
elif [[ "$url" =~ ^https://gitee\.com/wiseforever/cbuild/raw/([^/]+)/(.+)$ ]]; then
  source="gitee"; tag="${BASH_REMATCH[1]}"; rel="${BASH_REMATCH[2]}"
  fail_matches "${CBUILD_FAIL_GITEE:-}" "$source" "$tag" "$rel" && exit 22
else
  base="${CBUILD_TEST_BASE:-}"
  prefix="${base//\{tag\}/}"
  [[ -n "$prefix" && "$url" == "$prefix"* ]] || exit 22
  rest="${url#"$prefix"}"
  tag="${rest%%/*}"; rel="${rest#*/}"
  source="custom"
  fail_matches "${CBUILD_FAIL_CUSTOM:-}" "$source" "$tag" "$rel" && exit 22
fi

fail_matches "${CBUILD_FAIL_DOWNLOAD:-}" "$source" "$tag" "$rel" && exit 22
if [[ -n "${CBUILD_TEST_SCRIPT_VERSION:-}" && ( "$rel" == "cb.sh" || "$rel" == "cb.py" ) ]]; then
  if [[ "$rel" == "cb.sh" ]]; then
    printf '#!/bin/bash\nCBUILD_VERSION="%s"\n' "$CBUILD_TEST_SCRIPT_VERSION" > "$dest"
  else
    printf 'CBUILD_VERSION = "%s"\n' "$CBUILD_TEST_SCRIPT_VERSION" > "$dest"
  fi
elif [[ -f "$CBUILD_TEST_REPO/$rel" ]]; then
  cp "$CBUILD_TEST_REPO/$rel" "$dest"
else
  exit 22
fi
''', encoding="utf-8")
        curl.chmod(0o755)

    def run_installer(self, *args, installer=None, env=None, cwd=None, input_text=None):
        return subprocess.run(
            ["bash", str(installer or REPO / "install.sh"), *args], cwd=cwd or self.root,
            env=dict(self.env, **(env or {})), text=True, input=input_text,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )

    def install(self, variant="bash", mode="global", project=None, release=None, env=None, prefix=True, base_url=None, source=None):
        args = [f"--{variant}", f"--{mode}"]
        if prefix:
            args += ["--prefix", str(self.prefix)]
        if base_url:
            args += ["--base-url", base_url]
        if source:
            args += ["--source", source]
        if release:
            args += ["--release", release]
        return self.run_installer(*args, env=env, cwd=project)

    def downloads(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def assert_preserved(self, before):
        self.assertEqual({p.name: p.read_bytes() for p in self.prefix.iterdir()}, before)

    def seed_old_installation(self):
        for name in ("cb.sh", "cb.py", "cb_install.sh", "cb_uninstall.sh", ".install.cfg", "cb.conf"):
            (self.prefix / name).write_text("old " + name + "\n")
        return {p.name: p.read_bytes() for p in self.prefix.iterdir()}

    def test_installer_can_run_from_stdin_without_bash_source(self):
        result = subprocess.run(
            ["bash", "-s", "--", "--help"], input=(REPO / "install.sh").read_text(),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )
        self.succeeds(result)
        self.assertIn("Usage:", result.stdout)
        self.assertNotIn("BASH_SOURCE", result.stdout)
        self.assertNotIn("unbound variable", result.stdout)

    # --- version selection -------------------------------------------------

    def test_latest_reads_pointer_once_and_downloads_every_file_from_that_tag(self):
        (self.prefix / "cb.conf").write_text("user configuration\n")
        self.succeeds(self.install())
        pointer = "https://raw.githubusercontent.com/wiseforever/cbuild/master/LATEST"
        self.assertEqual(self.downloads().count(pointer), 1)
        required = ("cb.sh", "install.sh", "cb_uninstall.sh")
        for rel in required:
            self.assertIn(f"https://raw.githubusercontent.com/wiseforever/cbuild/v0.1.0/{rel}", self.downloads())
        self.assertFalse(any(("/master/" in url and not url.endswith("/master/LATEST")) or "api.github" in url
                        for url in self.downloads()))
        self.assertEqual((self.prefix / "cb.sh").read_bytes(), (REPO / "cb.sh").read_bytes())
        self.assertEqual((self.prefix / "cb_install.sh").read_bytes(), (REPO / "install.sh").read_bytes())
        self.assertFalse((self.prefix / "VERSION").exists())
        self.assertEqual((self.prefix / "cb.conf").read_text(), "user configuration\n")
        manifest = (self.prefix / ".install.cfg").read_text()
        self.assertIn('INSTALL_RELEASE="v0.1.0"', manifest)
        self.assertIn('INSTALL_VARIANT="bash"', manifest)
        self.assertIn('INSTALL_SOURCE="github"', manifest)
        self.assertFalse(list(self.prefix.glob(".cbuild-update.*")))

    def test_latest_pointer_can_be_resolved_from_gitee_only(self):
        self.succeeds(self.install(source="gitee", env={"CBUILD_TEST_GITEE_LATEST": "v0.1.0"}))
        urls = self.downloads()
        self.assertIn("https://gitee.com/wiseforever/cbuild/raw/master/LATEST", urls)
        self.assertIn("https://gitee.com/wiseforever/cbuild/raw/v0.1.0/cb.sh", urls)
        self.assertFalse(any("raw.githubusercontent.com" in url or "api.github" in url for url in urls))
        self.assertTrue((self.prefix / "cb.sh").is_file())

    def test_gitee_pointer_failure_does_not_borrow_the_github_pointer(self):
        before = self.seed_old_installation()
        result = self.install(source="gitee", env={"CBUILD_FAIL_GITEE_LATEST": "1"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Cannot read https://gitee.com/wiseforever/cbuild/raw/master/LATEST", result.stdout)
        self.assert_preserved(before)
        self.assertFalse(any("raw.githubusercontent.com" in url for url in self.downloads()))

    def test_explicit_release_skips_the_latest_pointer(self):
        self.succeeds(self.install(release="v0.1.0"))
        self.assertFalse(any("/master/LATEST" in url or "api.github" in url for url in self.downloads()))
        self.assertIn("https://raw.githubusercontent.com/wiseforever/cbuild/v0.1.0/cb.sh", self.downloads())

    def test_latest_rejects_missing_invalid_and_mismatched_tag_pointers(self):
        cases = [
            ({"CBUILD_FAIL_LATEST": "1"}, "Cannot read https://raw.githubusercontent.com/wiseforever/cbuild/master/LATEST"),
            ({"CBUILD_TEST_LATEST": "master"}, "Invalid LATEST"),
            ({"CBUILD_TEST_LATEST": "0.1.0"}, "Invalid LATEST"),
            ({"CBUILD_TEST_LATEST": "v0.1.0\nv0.2.0"}, "Invalid LATEST"),
            ({"CBUILD_TEST_LATEST": "v0.2.0"}, "does not match v0.2.0"),
        ]
        before = self.seed_old_installation()
        for env, message in cases:
            with self.subTest(env=env):
                result = self.install(env=env)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(message, result.stdout)
                self.assert_preserved(before)
                self.assertFalse((self.home / ".bashrc").exists())
        self.assertFalse(any("/v0.1.0/" in url for url in self.downloads()))

    def test_explicit_prerelease_tag_is_allowed(self):
        self.succeeds(self.install(release="v0.1.0-rc.1"))
        self.assertIn("https://raw.githubusercontent.com/wiseforever/cbuild/v0.1.0-rc.1/cb.sh", self.downloads())

    # --- integrity, mirrors, failure safety --------------------------------

    def test_downloaded_script_version_must_match_the_tag(self):
        before = self.seed_old_installation()
        for variant, mode in (("bash", "global"), ("python", "global"),
                              ("bash", "simple"), ("python", "simple")):
            with self.subTest(variant=variant, mode=mode):
                project = self.root / f"mismatch {variant} {mode}"
                project.mkdir()
                if mode == "simple":
                    (project / "cb.conf").write_text("project config\n")
                result = self.install(variant, mode=mode, project=project,
                                      env={"CBUILD_TEST_SCRIPT_VERSION": "9.9.9"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("does not match v0.1.0", result.stdout)
                if mode == "simple":
                    self.assertEqual((project / "cb.conf").read_text(), "project config\n")
                    self.assertFalse((project / "cbuild_bak").exists())
                else:
                    self.assert_preserved(before)

    def test_missing_required_file_preserves_old_installation_and_uninstaller(self):
        before = self.seed_old_installation()
        for rel in ("cb.sh", "cb.py", "install.sh"):
            with self.subTest(rel=rel):
                result = self.install("python" if rel == "cb.py" else "bash", env={"CBUILD_FAIL_DOWNLOAD": rel})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assert_preserved(before)
                self.assertFalse((self.home / ".bashrc").exists())
        self.assertFalse(list(self.prefix.glob(".cbuild-update.*")))

    def test_optional_uninstaller_wrapper_failure_does_not_block_install(self):
        before = self.seed_old_installation()
        result = self.install(env={"CBUILD_FAIL_DOWNLOAD": "cb_uninstall.sh"})
        self.succeeds(result)
        self.assertIn("compatibility cb_uninstall.sh unavailable", result.stdout)
        self.assertTrue((self.prefix / "cb.sh").is_file())
        self.assertEqual((self.prefix / "cb_uninstall.sh").read_bytes(), before["cb_uninstall.sh"])
        self.succeeds(self.run_installer("--uninstall", "--prefix", str(self.prefix), "--yes"))
        self.assertFalse(self.prefix.exists())

    def test_selected_source_does_not_fall_back_to_the_other_mirror(self):
        before = self.seed_old_installation()
        result = self.install(env={"CBUILD_FAIL_GITHUB": "cb.sh"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_preserved(before)
        urls = self.downloads()
        self.assertIn("https://raw.githubusercontent.com/wiseforever/cbuild/v0.1.0/cb.sh", urls)
        self.assertFalse(any("gitee.com" in url for url in urls))

    def test_custom_source_never_falls_back_to_public_repositories(self):
        before = self.seed_old_installation()
        result = self.install(env={"CBUILD_FAIL_CUSTOM": "cb.sh"},
                              base_url="https://cbuild.test/{tag}", release="v0.1.0")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_preserved(before)
        self.assertFalse(any("raw.githubusercontent.com" in url or "gitee.com" in url for url in self.downloads()))

    # --- modes -------------------------------------------------------------

    def test_global_install_supports_both_variants_and_replaces_the_other(self):
        for variant, selected, removed in (("bash", "cb.sh", "cb.py"), ("python", "cb.py", "cb.sh")):
            with self.subTest(variant=variant):
                self.succeeds(self.install(variant))
                self.assertTrue((self.prefix / selected).is_file())
                self.assertFalse((self.prefix / removed).exists())
                self.assertTrue(os.access(self.prefix / selected, os.X_OK))
                self.assertFalse((self.prefix / "VERSION").exists())

    def test_installed_updater_retains_the_selected_source(self):
        self.succeeds(self.install(source="gitee"))
        self.assertIn('INSTALL_SOURCE="gitee"', (self.prefix / ".install.cfg").read_text())
        self.log.unlink()
        result = self.run_installer("--release", "latest",
                                    installer=self.prefix / "cb_install.sh",
                                    env={"CBUILD_FAIL_LATEST": "1"})
        self.succeeds(result)
        urls = self.downloads()
        self.assertIn("https://gitee.com/wiseforever/cbuild/raw/master/LATEST", urls)
        self.assertFalse(any("raw.githubusercontent.com" in url for url in urls))

    def test_installed_updater_retains_prefix_and_variant_but_uses_requested_release(self):
        self.succeeds(self.install("bash", release="v0.1.0"))
        result = self.run_installer(
            "--python", "--release", "v0.1.0", "--base-url", "https://cbuild.test/{tag}",
            installer=self.prefix / "cb_install.sh", cwd=self.root,
        )
        self.succeeds(result)
        self.assertTrue((self.prefix / "cb.py").is_file())
        self.assertFalse((self.prefix / "cb.sh").exists())
        self.assertIn('INSTALL_RELEASE="v0.1.0"', (self.prefix / ".install.cfg").read_text())
        # A later invocation without --prefix or variant keeps both.
        result = self.run_installer("--release", "v0.1.0", "--base-url", "https://cbuild.test/{tag}",
                                    installer=self.prefix / "cb_install.sh")
        self.succeeds(result)
        self.assertTrue((self.prefix / "cb.py").is_file())
        self.assertIn('INSTALL_VARIANT="python"', (self.prefix / ".install.cfg").read_text())

    def test_simple_install_uses_tag_and_keeps_project_config_untouched(self):
        for variant, selected in (("bash", "cb.sh"), ("python", "cb.py")):
            with self.subTest(variant=variant):
                project = self.root / ("simple " + variant)
                project.mkdir()
                (project / "cb.conf").write_text("my config\n")
                self.succeeds(self.install(variant, mode="simple", project=project, release="v0.1.0"))
                self.assertEqual((project / "cb.conf").read_bytes(), (REPO / "cb.conf").read_bytes())
                self.assertEqual((project / selected).read_bytes(), (REPO / selected).read_bytes())
                self.assertTrue((project / ".vscode" / "settings.json").is_file())
                self.assertFalse((project / ("cb.py" if selected == "cb.sh" else "cb.sh")).exists())
                backups = list((project / "cbuild_bak").glob("bak_*"))
                self.assertEqual(len(backups), 1)
                self.assertEqual((backups[0] / "cb.conf").read_text(), "my config\n")
                self.assertIn("https://raw.githubusercontent.com/wiseforever/cbuild/v0.1.0/cb.sh", self.downloads())
    def test_config_and_vscode_modes_accept_explicit_versions_and_backup_only_their_files(self):
        for mode in ("config", "vscode"):
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                project = self.root / (mode + " project")
                project.mkdir()
                (project / "cb.conf").write_text("old project config\n")
                (project / ".vscode").mkdir()
                (project / ".vscode" / "custom.json").write_text("old editor settings\n")
                self.succeeds(self.install(mode=mode, project=project, release="v0.1.0", prefix=False))
                backups = list((project / "cbuild_bak").glob("bak_*"))
                self.assertEqual(len(backups), 1)
                if mode == "config":
                    self.assertEqual((project / "cb.conf").read_bytes(), (REPO / "cb.conf").read_bytes())
                    self.assertEqual((backups[0] / "cb.conf").read_text(), "old project config\n")
                    self.assertEqual((project / ".vscode" / "custom.json").read_text(), "old editor settings\n")
                else:
                    self.assertEqual((project / ".vscode" / "settings.json").is_file(), True)
                    self.assertEqual((backups[0] / ".vscode" / "custom.json").read_text(), "old editor settings\n")
                    self.assertEqual((project / "cb.conf").read_text(), "old project config\n")
                self.assertFalse((project / "cb.sh").exists())
                self.assertFalse((project / "cb.py").exists())
                self.assertTrue(any("/v0.1.0/" in url for url in self.downloads()))

    def test_project_download_failure_keeps_existing_files_without_backup(self):
        before = self.seed_old_installation()
        project = self.root / "project"
        project.mkdir()
        (project / "cb.conf").write_text("stable config\n")
        result = self.install(mode="config", project=project, env={"CBUILD_FAIL_DOWNLOAD": "cb.conf"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((project / "cb.conf").read_text(), "stable config\n")
        self.assertFalse((project / "cbuild_bak").exists())
        self.assert_preserved(before)

    def test_format_mode_follows_release(self):
        project = self.root / "format project"
        project.mkdir()
        (project / ".clang-format").write_text("old format\n")
        self.succeeds(self.install(mode="format", project=project, release="v0.1.0", prefix=False))
        self.assertEqual((project / ".clang-format").read_bytes(), (REPO / ".clang-format").read_bytes())
        backups = list((project / "cbuild_bak").glob("bak_*"))
        self.assertEqual((backups[0] / ".clang-format").read_text(), "old format\n")

    def test_version_flags_do_not_need_the_network_or_cb_conf(self):
        project = self.project("version-query")
        for variant in VARIANTS:
            result = self.invoke(project, variant, "--version")
            self.succeeds(result)
            self.assertIn("0.1.0", result.stdout)
        self.assertEqual(self.downloads(), [])

    def test_installer_has_no_self_version_flag(self):
        self.succeeds(self.install())
        result = self.run_installer("--version")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("was removed", result.stdout)

    def test_uninstall_via_compatibility_wrapper(self):
        self.succeeds(self.install())
        result = subprocess.run(["bash", str(self.prefix / "cb_uninstall.sh"), "--version"],
                                env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.succeeds(result)
        self.assertIn("0.1.0", result.stdout)
        result = subprocess.run(["bash", str(self.prefix / "cb_uninstall.sh"), "--yes"],
                                env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.succeeds(result)
        self.assertFalse(self.prefix.exists())

    def test_uninstall_via_installer_requires_yes_when_non_interactive(self):
        self.succeeds(self.install())
        result = self.run_installer("--uninstall", "--prefix", str(self.prefix), input_text="y\n")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("requires --yes", result.stdout)
        self.assertTrue((self.prefix / "cb.sh").is_file())
        result = self.run_installer("--uninstall", "--prefix", str(self.prefix), "--yes")
        self.succeeds(result)
        self.assertFalse(self.prefix.exists())

    def test_uninstall_via_installed_updater_targets_its_own_directory(self):
        self.succeeds(self.install())
        result = self.run_installer("--uninstall", "--yes", installer=self.prefix / "cb_install.sh")
        self.succeeds(result)
        self.assertFalse(self.prefix.exists())

    def test_repository_uninstall_wrapper_defaults_to_home_installation(self):
        home_prefix = self.home / ".cbuild"
        home_prefix.mkdir()
        (home_prefix / ".install.cfg").write_text("INSTALL_DIR=unused\n")
        (home_prefix / "cb.sh").write_text("#!/bin/bash\n")
        result = subprocess.run(["bash", str(REPO / "cb_uninstall.sh"), "--yes"],
                                env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.succeeds(result)
        self.assertFalse(home_prefix.exists())
        self.assertTrue((REPO / "install.sh").is_file())

    def test_uninstall_does_not_need_the_compatibility_wrapper(self):
        self.succeeds(self.install())
        (self.prefix / "cb_uninstall.sh").unlink()
        result = self.run_installer("--uninstall", "--prefix", str(self.prefix), "--yes")
        self.succeeds(result)
        self.assertFalse(self.prefix.exists())

    def test_uninstall_refuses_a_source_checkout(self):
        result = self.run_installer("--uninstall", "--prefix", str(REPO), "--yes")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Not a cbuild installation", result.stdout)
        self.assertTrue((REPO / "install.sh").is_file())

    def test_uninstall_refuses_home_root_and_unknown_directories(self):
        self.succeeds(self.install())
        for target in (self.home, "/"):
            with self.subTest(target=target):
                result = self.run_installer("--uninstall", "--prefix", str(target), "--yes")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("Refusing", result.stdout)
        unknown = self.root / "not cbuild"
        unknown.mkdir()
        result = self.run_installer("--uninstall", "--prefix", str(unknown), "--yes")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Not a cbuild installation", result.stdout)
        self.assertTrue(unknown.exists())
        self.assertTrue((self.prefix / "cb.sh").is_file())


@unittest.skipUnless(shutil.which("bash"), "requires Bash")
class VersionTests(TemporaryProjectTest):
    def test_all_version_sources_agree_and_tag_match_is_enforced(self):
        checker = REPO / "tools" / "check_version.sh"
        version = subprocess.check_output(["bash", str(REPO / "cb.sh"), "--version"], text=True).split()[-1]
        self.succeeds(subprocess.run(["bash", str(checker), f"v{version}"], text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT))
        for tag in ("v0.0.0", "master", f"v{version}-rc.1"):
            with self.subTest(tag=tag):
                result = subprocess.run(["bash", str(checker), tag], text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertRegex(result.stdout, "does not match (script version|LATEST)")


if __name__ == "__main__":
    unittest.main()
