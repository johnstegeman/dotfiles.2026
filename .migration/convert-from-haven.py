#!/usr/bin/env python3
"""Convert haven's magic-name source tree into a plain-name tree under ~/.dotfiles.

Copies (never moves) every file from ~/.local/share/haven/source to the path it
decodes to under $HOME, so the conversion can be re-run after a change to a
tracked file before the cutover.

Decoding mirrors haven's src/source.rs:
  private_ / executable_ / symlink_ / extdir_ / extfile_ / create_ / exact_ prefixes
  are stripped (any order, repeatedly); dot_<name> -> .<name>;
  a .tmpl suffix is stripped from a file name; extdir_ files are repo markers.
Like haven's scanner, hidden entries (names starting with '.') are never deployed
and are skipped here too, as are *.bak files.

Horizon: writes the [dotfiles] / [bootstrap.repos] TOML fragment to stdout so it
can be pasted into ~/.config/mise/config.macos.toml.
"""

import os
import shutil
import sys

SRC = os.path.expanduser("~/.local/share/haven/source")
DST = os.path.expanduser("~/.dotfiles")
PREFIXES = ("private_", "executable_", "symlink_", "extdir_", "extfile_", "create_", "exact_")


def decode_component(name, is_file):
    flags = set()
    rest = name
    changed = True
    while changed:
        changed = False
        for prefix in PREFIXES:
            if rest.startswith(prefix):
                flags.add(prefix[:-1])
                rest = rest[len(prefix):]
                changed = True
                break
    if rest.startswith("dot_"):
        rest = "." + rest[4:]
    template = False
    if is_file and rest.endswith(".tmpl"):
        template = True
        rest = rest[: -len(".tmpl")]
    return rest, flags, template


def decode_rel(rel):
    """Return (decoded components, flags of the final component, template, dir flags)."""
    parts = rel.split(os.sep)
    decoded, dir_private, dirs = [], [], []
    for comp in parts[:-1]:
        name, flags, _ = decode_component(comp, False)
        decoded.append(name)
        dirs.append(name)
        if "private" in flags:
            dir_private.append(os.path.join(*dirs))
    name, flags, template = decode_component(parts[-1], True)
    decoded.append(name)
    return decoded, flags, template, dir_private


def read_repo_marker(path):
    url = ref = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip().strip('"')
            if key == "url":
                url = value
            elif key == "ref":
                ref = value
    return url, ref


def main():
    stats = {
        "walked": 0,
        "copied": 0,
        "hidden": 0,
        "bak": 0,
        "repos": 0,
        "mise_config": 0,
    }
    entries = {}  # tilde target -> dict of table fields
    private_dirs = set()
    notes = []

    for root, dirnames, filenames in os.walk(SRC):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for dirname in dirnames:
            # Directories carry the private_ flag too, and one of them is empty,
            # so collect them from the walk rather than from file paths.
            rel_dir = os.path.relpath(os.path.join(root, dirname), SRC)
            if "private" in decode_component(dirname, False)[1]:
                decoded_dir = [decode_component(p, False)[0] for p in rel_dir.split(os.sep)]
                private_dirs.add("/".join(decoded_dir))
        for filename in sorted(filenames):
            abs_path = os.path.join(root, filename)
            rel = os.path.relpath(abs_path, SRC)
            stats["walked"] += 1
            if filename.startswith("."):
                stats["hidden"] += 1
                notes.append(f"skipped hidden (never deployed by haven): {rel}")
                continue
            if filename.endswith(".bak"):
                stats["bak"] += 1
                notes.append(f"skipped backup: {rel}")
                continue

            decoded, flags, template, dir_private = decode_rel(rel)
            private_dirs.update(dir_private)
            target = "~/" + "/".join(decoded)

            if target == "~/.config/mise" or target.startswith("~/.config/mise/"):
                # The live mise config was moved into the tree by hand and made
                # authoritative; copying the tracked copy back would revert it.
                stats["mise_config"] += 1
                notes.append(f"kept live mise config over tracked copy: {target}")
                continue

            if "extdir" in flags:
                url, ref = read_repo_marker(abs_path)
                stats["repos"] += 1
                entries[target] = {"__repo__": (url, ref)}
                continue

            os.makedirs(os.path.dirname(os.path.join(DST, *decoded)), exist_ok=True)
            dest_path = os.path.join(DST, *decoded)
            shutil.copy2(abs_path, dest_path)
            # haven sets the deployed mode from the flags, not from the source mode
            # (src/fs.rs): private+executable 0700, private 0600, executable 0755, else 0644.
            mode = 0o644
            if "private" in flags and "executable" in flags:
                mode = 0o700
            elif "private" in flags:
                mode = 0o600
            elif "executable" in flags:
                mode = 0o755
            os.chmod(dest_path, mode)
            stats["copied"] += 1

            fields = {}
            if "symlink" in flags:
                fields["mode"] = "symlink"
                fields["relative"] = True
                if "private" in flags:
                    notes.append(
                        f"private_ on a symlink is not expressible as permissions: {target}"
                    )
            elif template:
                fields["mode"] = "template"
            if "private" in flags and "symlink" not in flags:
                fields["permissions"] = "0600"
            entries[target] = {"__file__": fields}

    for d in sorted(private_dirs):
        entries["~/" + d] = {"__file__": {"permissions": "0700"}}

    def is_mise_config(target):
        return target == "~/.config/mise" or target.startswith("~/.config/mise/")

    out = []
    out.append("# dotfiles: plain-name tree mirroring $HOME, root = ~/.dotfiles")
    out.append("[dotfiles]")
    for target in sorted(entries):
        if is_mise_config(target):
            continue
        (key, value), = entries[target].items()
        if key == "__repo__":
            continue
        if not value:
            out.append(f'"{target}" = {{}}')
        else:
            body = ", ".join(
                f"{k} = {str(v).lower()}" if isinstance(v, bool) else f'{k} = "{v}"'
                for k, v in value.items()
            )
            out.append(f'"{target}" = {{ {body} }}')

    repos = {t: v["__repo__"] for t, v in entries.items() if "__repo__" in v}
    if repos:
        out.append("")
        out.append("[bootstrap.repos]")
        for target in sorted(repos):
            url, ref = repos[target]
            out.append(f'"{target}" = {{ url = "{url}"' + (f', ref = "{ref}"' if ref else "") + " }")

    print("\n".join(out))
    print("\n# ---- report ----", file=sys.stderr)
    for key, value in stats.items():
        print(f"# {key}: {value}", file=sys.stderr)
    print(f"# dotfiles entries: {sum(1 for t in entries if '__file__' in entries[t] and not is_mise_config(t))}", file=sys.stderr)
    print(f"# private dirs: {len(private_dirs)}", file=sys.stderr)
    print(f"# repos: {len(repos)}", file=sys.stderr)
    for note in notes:
        print(f"# note: {note}", file=sys.stderr)


if __name__ == "__main__":
    main()
