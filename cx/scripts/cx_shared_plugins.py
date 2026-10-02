"""Share the installed LazyCodex plugin without sharing account state (Python 3.11+)."""

import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import tomllib
import uuid


PLUGIN = "omo@sisyphuslabs"
FEATURES = ("plugins", "plugin_hooks", "multi_agent", "unified_exec", "goals")
MARKER = ".cx-shared-plugins"
PROFILE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")


def private_directory(path):
    if path.is_symlink() or not path.is_dir():
        raise ValueError(f"expected a real private directory: {path}")
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError(f"directory must be owned by you and private: {path}")


def sections(text):
    """Split ordinary TOML tables, preserving comments and multiline string contents."""
    result, path, lines = [], (), []
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("["):
            try:
                tomllib.loads("".join(lines))
                node = tomllib.loads(line)
                candidate = []
                while isinstance(node, dict) and len(node) == 1:
                    key, node = next(iter(node.items()))
                    candidate.append(key)
                if node != {}:
                    raise ValueError("not an ordinary table header")
            except (ValueError, tomllib.TOMLDecodeError):
                pass
            else:
                result.append((path, "".join(lines)))
                path, lines = tuple(candidate), []
        lines.append(line)
    result.append((path, "".join(lines)))
    return result


def owned(path, agents):
    return (path[:2] == ("marketplaces", "sisyphuslabs")
            or path[:2] == ("plugins", PLUGIN)
            or (len(path) >= 3 and path[:2] == ("hooks", "state")
                and path[2].startswith(PLUGIN + ":"))
            or (len(path) >= 2 and path[0] == "agents" and path[1] in agents))


def unmanaged(data, agents):
    """Compare all non-plugin settings before writing; reject unsupported TOML layouts."""
    def visit(node, path=()):
        if owned(path, agents) or (len(path) == 2 and path[0] == "features" and path[1] in FEATURES):
            return None
        if isinstance(node, dict):
            result = {}
            for key, value in node.items():
                remaining = visit(value, path + (key,))
                if remaining is not None:
                    result[key] = remaining
            return result or None
        return node
    return visit(data)


def load_source(source):
    text = (source / "config.toml").read_text()
    source_sections = sections(text)
    # Only import the plugin's tables; unrelated default-profile settings are not shared.
    marketplace_text = next(block for path, block in source_sections
                            if path == ("marketplaces", "sisyphuslabs"))
    marketplace = tomllib.loads(marketplace_text)["marketplaces"]["sisyphuslabs"]
    cache = Path(marketplace["source"]).expanduser().resolve()
    if marketplace.get("source_type") != "local" or not cache.is_dir():
        raise ValueError("LazyCodex must use an existing local marketplace")
    catalog = json.loads((cache / ".agents/plugins/marketplace.json").read_text())
    entry = next(item for item in catalog["plugins"] if item["name"] == "omo")
    plugin_root = (cache / entry["source"]["path"]).resolve()
    plugin_root.relative_to(cache)
    agents = {p.stem for p in (plugin_root / "components/ultrawork/agents").glob("*.toml")}
    if not agents:
        raise ValueError("shared LazyCodex Agent definitions are missing")
    config = tomllib.loads("\n".join(block for path, block in source_sections if owned(path, agents)))
    if config.get("plugins", {}).get(PLUGIN, {}).get("enabled") is not True:
        raise ValueError("install and enable LazyCodex in ~/.codex first")
    blocks = []
    for path, block in source_sections:
        if not owned(path, agents):
            continue
        if len(path) == 2 and path[0] == "agents":
            agent_path = (source / config["agents"][path[1]]["config_file"]).resolve()
            tomllib.loads(agent_path.read_text())
            block, count = re.subn(r"(?m)^config_file\s*=.*$",
                                  lambda _: "config_file = " + json.dumps(str(agent_path)), block)
            if count != 1:
                raise ValueError("unsupported Agent config_file layout")
        blocks.append(block.rstrip() + "\n")
    generated = "\n".join(blocks)
    parsed = tomllib.loads(generated)
    if set(parsed.get("agents", {})) != agents:
        raise ValueError("shared config is missing registered LazyCodex Agents")
    if not any(key.startswith(PLUGIN + ":") for key in parsed.get("hooks", {}).get("state", {})):
        raise ValueError("shared config is missing LazyCodex Hook trust entries")
    return cache, agents, generated


def merge_config(original, agents, generated):
    before = tomllib.loads(original)
    blocks, found_features = [], False
    for path, block in sections(original):
        if owned(path, agents):
            continue
        if path == ("features",):
            found_features = True
            for feature in FEATURES:
                pattern = rf"(?m)^\s*{feature}\s*=.*$"
                block, count = re.subn(pattern, f"{feature} = true", block)
                if not count:
                    block = block.rstrip() + f"\n{feature} = true\n"
        blocks.append(block.rstrip() + "\n")
    if not found_features:
        blocks.append("[features]\n" + "".join(f"{key} = true\n" for key in FEATURES))
    merged = "\n".join(blocks).strip() + "\n\n" + generated
    after = tomllib.loads(merged)
    if unmanaged(before, agents) != unmanaged(after, agents):
        raise ValueError("unsupported TOML layout: sync would change unrelated settings")
    desired = tomllib.loads(generated)
    for key in FEATURES:
        if after.get("features", {}).get(key) is not True:
            raise ValueError("unsupported features table layout")
    for key in ("marketplaces", "plugins", "agents"):
        for name, value in desired[key].items():
            if after.get(key, {}).get(name) != value:
                raise ValueError("plugin configuration validation failed")
    return merged


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".cx-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def prepare(profile, shared):
    private_directory(profile)
    config_path = profile / "config.toml"
    if config_path.is_symlink():
        raise ValueError(f"refusing linked account config: {config_path}")
    original = config_path.read_text() if config_path.exists() else ""
    cache, agents, generated = shared
    merged = merge_config(original, agents, generated)
    for path in (profile / "plugins", profile / "plugins/cache"):
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            raise ValueError(f"refusing unexpected cache parent: {path}")
    target = profile / "plugins/cache/sisyphuslabs"
    linked = target.is_symlink() and target.resolve() == cache
    return profile, original, merged, target, cache, linked


def apply_plan(plan, apply=False, quiet=False):
    profile, original, merged, target, cache, linked = plan
    changed = original != merged or not linked
    if not quiet:
        print(f"{profile.name}: {'apply' if apply else 'preview'} "
              f"config={'update' if original != merged else 'unchanged'}, "
              f"cache={'shared' if linked else 'link'}")
    if not apply or not changed:
        return
    suffix = ".cx-backup-" + uuid.uuid4().hex[:12]
    config_path = profile / "config.toml"
    # Recheck after preflight rather than overwriting a concurrently edited config.
    if (config_path.read_text() if config_path.exists() else "") != original:
        raise ValueError(f"config changed during sync: {profile.name}; retry")
    if original != merged and config_path.exists():
        atomic_write(profile / ("config.toml" + suffix), original)
    if not linked:
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if target.exists() or target.is_symlink():
            target.rename(target.with_name(target.name + suffix))
        target.symlink_to(cache, target_is_directory=True)
    if original != merged:
        atomic_write(config_path, merged)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", nargs="?")
    parser.add_argument("--all", action="store_true", help="include all profiles; --apply enables sync on launch/init")
    parser.add_argument("--apply", action="store_true", help="write backed-up config and shared cache links")
    parser.add_argument("--quiet", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if bool(args.profile) == args.all:
        parser.error("choose a profile or --all")
    root = Path.home() / ".codex-profiles"
    private_directory(root)
    if args.profile and not PROFILE_NAME.fullmatch(args.profile):
        parser.error("invalid profile name")
    profiles = ([root / args.profile] if args.profile else
                sorted(p for p in root.iterdir() if PROFILE_NAME.fullmatch(p.name) and p.is_dir() and not p.is_symlink()))
    shared = load_source(Path.home() / ".codex")
    plans = [prepare(profile, shared) for profile in profiles]
    for plan in plans:
        apply_plan(plan, args.apply, args.quiet)
    if args.all and args.apply:
        marker = root / MARKER
        if not marker.exists():
            atomic_write(marker, "LazyCodex sync on cx launch/init enabled by cx plugins sync --all --apply.\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, StopIteration) as error:
        # Do not print config contents or parser messages which may include private values.
        print(f"cx: shared plugin sync failed ({type(error).__name__}); check paths and TOML layout", file=sys.stderr)
        sys.exit(1)
