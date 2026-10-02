"""Isolated regression tests; no real profile, credentials, or Codex process is used."""

import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import tomllib
import unittest


SPEC = importlib.util.spec_from_file_location(
    "cx_shared_plugins", Path(__file__).resolve().parents[1] / "scripts/cx_shared_plugins.py")
if SPEC is None or SPEC.loader is None:
    raise ImportError("could not load cx shared plugin sync module")
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)


class SharedPluginsTest(unittest.TestCase):
    def __init__(self, method_name: str = "runTest"):
        super().__init__(method_name)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / "shared"
        self.cache = self.source / "plugins/cache/sisyphuslabs"
        self.plugin = self.cache / "omo/1"
        self.profile = self.root / "account"
        self.original = ""

    def setUp(self):
        catalog = self.cache / ".agents/plugins"
        catalog.mkdir(parents=True)
        (catalog / "marketplace.json").write_text(json.dumps({"plugins": [
            {"name": "omo", "source": {"path": "./omo/1"}}]}))
        bundled = self.plugin / "components/ultrawork/agents"
        bundled.mkdir(parents=True)
        (bundled / "explorer.toml").write_text('name = "explorer"\n')
        (self.source / "agents").mkdir()
        (self.source / "agents/explorer.toml").write_text('name = "explorer"\n')
        (self.source / "config.toml").write_text(
            'model = "do-not-inherit"\napproval_policy = "never"\n'
            '[marketplaces.sisyphuslabs]\nsource_type = "local"\n'
            f'source = {json.dumps(str(self.cache))}\n'
            '[plugins."omo@sisyphuslabs"]\nenabled = true\n'
            '[plugins."omo@sisyphuslabs".mcp_servers.git_bash]\nenabled = false\n'
            '[hooks.state."omo@sisyphuslabs:trigger"]\ntrusted_hash = "sha256:fixture"\n'
            '[agents.explorer]\nconfig_file = "./agents/explorer.toml"\n')
        self.profile = self.root / "account"
        self.profile.mkdir(mode=0o700)
        self.original = ('model = "keep-account-model"\napproval_policy = "on-request"\n'
                         '[features]\nplugins = false\nunrelated = true\n'
                         '[plugins."other@store"]\nenabled = true\n'
                         '[agents.custom]\nconfig_file = "/private/custom.toml"\n')
        (self.profile / "config.toml").write_text(self.original)

    def shared(self):
        return sync.load_source(self.source)

    def test_dry_run_never_mutates(self):
        sync.apply_plan(sync.prepare(self.profile, self.shared()), quiet=True)
        self.assertEqual((self.profile / "config.toml").read_text(), self.original)
        self.assertEqual(sorted(p.name for p in self.profile.iterdir()), ["config.toml"])

    def test_merge_preserves_account_and_other_plugins(self):
        shared = self.shared()
        sync.apply_plan(sync.prepare(self.profile, shared), apply=True, quiet=True)
        result = tomllib.loads((self.profile / "config.toml").read_text())
        self.assertEqual(result["model"], "keep-account-model")
        self.assertEqual(result["approval_policy"], "on-request")
        self.assertTrue(result["plugins"]["other@store"]["enabled"])
        self.assertFalse(result["plugins"][sync.PLUGIN]["mcp_servers"]["git_bash"]["enabled"])
        self.assertEqual(result["agents"]["explorer"]["config_file"], str(self.source / "agents/explorer.toml"))
        self.assertEqual(result["agents"]["custom"]["config_file"], "/private/custom.toml")
        self.assertEqual((self.profile / "plugins/cache/sisyphuslabs").resolve(), self.cache)
        backup = next(self.profile.glob("config.toml.cx-backup-*"))
        self.assertEqual(backup.read_text(), self.original)
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((self.profile / "config.toml").stat().st_mode), 0o600)

    def test_second_sync_is_byte_identical_and_creates_no_backup(self):
        shared = self.shared()
        sync.apply_plan(sync.prepare(self.profile, shared), apply=True, quiet=True)
        before = (self.profile / "config.toml").read_bytes()
        files = sorted(str(p.relative_to(self.profile)) for p in self.profile.rglob("*"))
        sync.apply_plan(sync.prepare(self.profile, shared), apply=True, quiet=True)
        self.assertEqual(before, (self.profile / "config.toml").read_bytes())
        self.assertEqual(files, sorted(str(p.relative_to(self.profile)) for p in self.profile.rglob("*")))

    def test_existing_cache_is_backed_up_and_other_cache_untouched(self):
        target = self.profile / "plugins/cache/sisyphuslabs"
        target.mkdir(parents=True)
        (target / "old-install").write_text("old")
        other = target.parent / "another-plugin"
        other.mkdir()
        sync.apply_plan(sync.prepare(self.profile, self.shared()), apply=True, quiet=True)
        backup = next(target.parent.glob("sisyphuslabs.cx-backup-*"))
        self.assertEqual((backup / "old-install").read_text(), "old")
        self.assertTrue(other.is_dir())

    def test_new_profile_without_config(self):
        (self.profile / "config.toml").unlink()
        sync.apply_plan(sync.prepare(self.profile, self.shared()), apply=True, quiet=True)
        config = tomllib.loads((self.profile / "config.toml").read_text())
        self.assertNotIn("model", config)
        self.assertNotIn("approval_policy", config)
        self.assertFalse(list(self.profile.glob("config.toml.cx-backup-*")))

    def test_missing_agent_fails_before_mutation(self):
        (self.source / "agents/explorer.toml").unlink()
        with self.assertRaises(FileNotFoundError):
            self.shared()
        self.assertEqual((self.profile / "config.toml").read_text(), self.original)

    def test_symlink_account_config_is_rejected(self):
        target = self.profile / "config.toml"
        target.unlink()
        target.symlink_to(self.source / "config.toml")
        with self.assertRaises(ValueError):
            sync.prepare(self.profile, self.shared())

    def test_linked_cache_parent_is_rejected(self):
        (self.profile / "plugins").symlink_to(self.source / "plugins")
        with self.assertRaises(ValueError):
            sync.prepare(self.profile, self.shared())

    def test_multiline_content_is_preserved(self):
        original = ('instructions = """\n[features]\nplugins = false\n"""\n' + self.original)
        shared = self.shared()
        merged = sync.merge_config(original, shared[1], shared[2])
        self.assertEqual(tomllib.loads(original)["instructions"], tomllib.loads(merged)["instructions"])

    def test_source_update_replaces_old_hook_entries(self):
        shared = self.shared()
        original = self.original + '[hooks.state."omo@sisyphuslabs:old"]\ntrusted_hash = "old"\n'
        result = tomllib.loads(sync.merge_config(original, shared[1], shared[2]))
        self.assertNotIn(sync.PLUGIN + ":old", result["hooks"]["state"])
        self.assertIn(sync.PLUGIN + ":trigger", result["hooks"]["state"])

    def test_concurrent_config_change_is_not_overwritten(self):
        plan = sync.prepare(self.profile, self.shared())
        (self.profile / "config.toml").write_text(self.original + "# user edit\n")
        with self.assertRaises(ValueError):
            sync.apply_plan(plan, apply=True, quiet=True)
        self.assertTrue((self.profile / "config.toml").read_text().endswith("# user edit\n"))

    def launcher(self):
        """Run the real launcher with an isolated profile root and fake external commands."""
        repository = Path(__file__).resolve().parents[1]
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        source = (repository / "bin/cx").read_text().replace(
            'readonly CX_PROFILES_ROOT="${HOME:?HOME must be set}/.codex-profiles"',
            f'readonly CX_PROFILES_ROOT="{self.root}"')
        cx = bin_dir / "cx"
        cx.write_text(source)
        for name, body in {
            "python3": '#!/bin/sh\nprintf "sync:%s\\n" "$*" >> "$CX_TEST_LOG"\n',
            "codex": '#!/bin/sh\nprintf "launch:%s:%s\\n" "$CODEX_HOME" "$*" >> "$CX_TEST_LOG"\n'
        }.items():
            command = bin_dir / name
            command.write_text(body)
            command.chmod(0o700)
        log = self.root / "calls.log"
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"], CX_TEST_LOG=str(log))
        return cx, log, env

    def test_launcher_syncs_before_forwarding_args(self):
        cx, log, env = self.launcher()
        (self.root / sync.MARKER).write_text("enabled")
        subprocess.run(["bash", str(cx), "account", "--", "--model", "fixture-model"], env=env, check=True)
        calls = log.read_text().splitlines()
        self.assertIn("account --apply --quiet", calls[0])
        self.assertEqual(calls[1], f"launch:{self.profile}:--no-alt-screen --model fixture-model")

    def test_init_syncs_new_profile_only_after_opt_in(self):
        cx, log, env = self.launcher()
        subprocess.run(["bash", str(cx), "init", "first"], env=env, check=True, capture_output=True)
        self.assertFalse(log.exists())
        (self.root / sync.MARKER).write_text("enabled")
        subprocess.run(["bash", str(cx), "init", "second"], env=env, check=True, capture_output=True)
        self.assertIn("second --apply --quiet", log.read_text())
        self.assertEqual(stat.S_IMODE((self.root / "second").stat().st_mode), 0o700)


if __name__ == "__main__":
    unittest.main()
