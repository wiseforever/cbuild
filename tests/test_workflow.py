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
    def setUp(self):
        super().setUp()
        self.home = self.root / "home"
        self.home.mkdir()
        self.prefix = self.home / "installed tools"
        self.prefix.mkdir()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        curl = bin_dir / "curl"
        curl.write_text(
            '#!/usr/bin/env bash\nset -eu\n'
            '[[ "$2" == https://cbuild.test/* ]] || exit 22\n'
            'rel="${2#https://cbuild.test/}"\n'
            '[[ "$rel" != "${CBUILD_FAIL_DOWNLOAD:-}" ]] || exit 22\n'
            'cp "$CBUILD_TEST_REPO/$rel" "$4"\n'
        )
        curl.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), SHELL="/bin/bash",
                        PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                        CBUILD_TEST_REPO=str(REPO))

    def install(self, variant="bash", fail="", mode="global", project=None, installer=None):
        return subprocess.run(
            ["bash", str(installer or REPO / "install.sh"), "--" + mode, "--" + variant,
             "--prefix", str(self.prefix), "--base-url", "https://cbuild.test"],
            cwd=project or self.root, env=dict(self.env, CBUILD_FAIL_DOWNLOAD=fail), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        )

    def test_failed_required_download_preserves_entire_installation(self):
        for name in ("cb.sh", "cb.py", "cb_install.sh", "cb_uninstall.sh", ".install.cfg", "cb.conf"):
            (self.prefix / name).write_text("old " + name + "\n")
        before = {p.name: p.read_bytes() for p in self.prefix.iterdir()}
        for variant, fail in (("bash", "cb.sh"), ("python", "cb.py"), ("python", "install.sh")):
            with self.subTest(variant=variant, fail=fail):
                result = self.install(variant, fail)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual({p.name: p.read_bytes() for p in self.prefix.iterdir()}, before)
                self.assertFalse((self.home / ".bashrc").exists())

    def test_successful_variant_switch_preserves_config_and_updates_scripts(self):
        (self.prefix / "cb.conf").write_text("user configuration\n")
        for variant, selected, removed in (("bash", "cb.sh", "cb.py"),
                                           ("python", "cb.py", "cb.sh"),
                                           ("bash", "cb.sh", "cb.py")):
            with self.subTest(variant=variant):
                self.succeeds(self.install(variant))
                self.assertEqual((self.prefix / selected).read_bytes(), (REPO / selected).read_bytes())
                self.assertEqual((self.prefix / "cb_install.sh").read_bytes(), (REPO / "install.sh").read_bytes())
                self.assertTrue(os.access(self.prefix / selected, os.X_OK))
                self.assertFalse((self.prefix / removed).exists())
                self.assertEqual((self.prefix / "cb.conf").read_text(), "user configuration\n")
                self.assertFalse(list(self.prefix.glob(".cbuild-update.*")))
        self.assertEqual((self.home / ".bashrc").read_text().count("# Added by cbuild install"), 1)

    def test_installed_updater_can_replace_itself(self):
        self.succeeds(self.install())
        self.succeeds(self.install("python", installer=self.prefix / "cb_install.sh"))
        self.assertTrue((self.prefix / "cb.py").is_file())
        self.assertFalse((self.prefix / "cb.sh").exists())
        self.assertEqual((self.prefix / "cb_install.sh").read_bytes(), (REPO / "install.sh").read_bytes())
        self.assertFalse(list(self.prefix.glob(".cbuild-update.*")))

    def test_optional_uninstaller_download_failure_keeps_old_copy(self):
        (self.prefix / "cb_uninstall.sh").write_text("old uninstaller\n")
        self.succeeds(self.install(fail="cb_uninstall.sh"))
        self.assertEqual((self.prefix / "cb_uninstall.sh").read_text(), "old uninstaller\n")
        self.assertTrue((self.prefix / "cb.sh").is_file())
        self.assertFalse(list(self.prefix.glob(".cbuild-update.*")))

    def test_global_installer_project_setup_targets_and_backs_up_only_requested_files(self):
        self.succeeds(self.install())
        for mode in ("vscode", "config"):
            with self.subTest(mode=mode):
                project = self.root / (mode + " project")
                project.mkdir()
                (project / "cb.conf").write_text("old project config\n")
                (project / ".vscode").mkdir()
                (project / ".vscode" / "custom.json").write_text("old editor settings\n")
                result = subprocess.run(
                    ["bash", str(self.prefix / "cb_install.sh"), "--" + mode, str(project),
                     "--base-url", "https://cbuild.test"],
                    cwd=self.root, env=self.env, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
                )
                self.succeeds(result)
                backups = list((project / "cbuild_bak").glob("bak_*"))
                self.assertEqual(len(backups), 1)
                if mode == "config":
                    self.assertEqual((project / "cb.conf").read_bytes(), (REPO / "cb.conf").read_bytes())
                    self.assertEqual((backups[0] / "cb.conf").read_text(), "old project config\n")
                    self.assertEqual((project / ".vscode" / "custom.json").read_text(), "old editor settings\n")
                else:
                    self.assertTrue((project / ".vscode" / "settings.json").exists())
                    self.assertEqual((backups[0] / ".vscode" / "custom.json").read_text(), "old editor settings\n")
                    self.assertEqual((project / "cb.conf").read_text(), "old project config\n")
                self.assertFalse((project / "cb.sh").exists())
                self.assertFalse((project / "cb.py").exists())
        self.assertFalse((self.root / "cb.conf").exists())
        self.assertFalse((self.root / ".vscode").exists())

    def test_project_install_honors_explicit_variant(self):
        for variant, selected, absent in (("python", "cb.py", "cb.sh"), ("bash", "cb.sh", "cb.py")):
            with self.subTest(variant=variant):
                project = self.root / variant
                project.mkdir()
                self.succeeds(self.install(variant, mode="simple", project=project))
                self.assertTrue((project / selected).is_file())
                self.assertFalse((project / absent).exists())
                self.assertTrue((project / "cb.conf").is_file())
                self.assertTrue((project / ".vscode" / "settings.json").is_file())
                self.assertFalse((self.home / ".bashrc").exists())


if __name__ == "__main__":
    unittest.main()
