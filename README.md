# dotfiles

This repo is the mise-managed source of truth for this machine's shell and app
configuration. It lives at `~/.dotfiles` and its layout mirrors `$HOME`, so the
file at `.config/fish/config.fish` here deploys to `~/.config/fish/config.fish`.
It also declares the Homebrew formulae, casks and App Store apps in
`[bootstrap.packages]` and the tool versions in `[tools]`, one file per
environment. `~/.config/mise` is a symlink into this repo
(`~/.config/mise -> ../.dotfiles/.config/mise`), so editing the live mise config
is editing the repo. Nothing here is generated: there is no merge step and no
second copy to drift. Deployment is `mise dot apply`.

Where things live: binary `/opt/m/bin/mise` (curl install, so `mise self-update` upgrades
it), tool installs and mise's data both under `/opt/m`, shims `/opt/m/shims`, state
`~/.local/state/mise`, and package/version declarations in this repo under `.config/mise/`.

## Verify and deploy

```
mise dot status --missing    # exits 0 when every entry is where it should be
mise dot diff                # exact content diff per entry
mise dot apply               # write what differs
```

`mise dot apply` refuses to overwrite a target it has written before and that has been
edited since. It prints `nothing keeps the current content` and points at `mise dot add`;
`--yes` accepts the overwrite anyway. A *tracked* target (see
[History and rollback](#history-and-rollback)) instead warns and overwrites, and the old
content stays in the history repo.

The asymmetry is worth knowing before a first `mise dot apply` on a new machine: a target
mise has *no* record of writing, such as one that predates its entry, is not warned about
and is overwritten silently. `mise dot diff` is the only pre-flight check for that case.

## Updating everything

Two fish functions, `m out` and `m up`, both wrapping mise. `m out` previews,
`m up` acts:

| step | preview (`m out`, `m up -n`) | act (`m up`) |
|---|---|---|
| mise tools | `mise outdated` | `mise upgrade` |
| brew packages | `mise bootstrap packages upgrade --dry-run <list>` | `mise bootstrap packages upgrade <list>` |
| leftovers | — | `brew cleanup` |

Two packages are withheld from mise's list. **`brew:kanata`** is a HEAD build
(`HEAD-f1ea695`) driving the keyboard remapper LaunchDaemon: unfiltered, mise wants to
pour the `kanata/1.12.0` bottle, silently replacing HEAD, and Homebrew itself leaves
it alone. **`brew:aisk/tap/timeout`** declares only an `arm64_sonoma` bottle, so on a
newer macOS mise takes its source path and pours its `depends_on "ghc" => :build` --
2.2 GB, installed as an unneeded dependency and flagged by `brew autoremove` -- on
every run, even though the formula itself is already current. Filtering it is what
stops that; Homebrew's own `brew upgrade` still covers it. Upgrading either one
remains an explicit decision, never part of a bulk run.

mise itself is not in the list either, because it is no longer a Homebrew package: it is
the curl install at `/opt/m/bin/mise` and upgrades with `mise self-update`.

## Adding a package or tool

```
m run pkg <manager:package> <env>     # e.g. m run pkg brew-cask:zed macos
m run tool <tool[@version]> <env>     # e.g. m run tool node@22 shell
```

Environment names, from `miserc.toml`: `shell`, `utilities`, `vcs`, `cloud`,
`k8s`, `macos`, `ai`. The task appends the name to the file convention
`config.<env>.toml` under the mise config dir, and both commands reach that
exact file with `-p/--path`. `-g/--global` is not per-environment, and
`-e/--env` writes `./mise.<env>.toml` in the current directory — neither can
target `~/.config/mise/config.<env>.toml`, which is why `-p` is the mechanism.

Package keys take a manager prefix: `brew:`, `brew-cask:`, `mas:<adam-id>`,
`nix:` and so on. Version pins are `@`-suffixed for most managers, but Homebrew
puts versions in the name (`brew:postgresql@17`) and mas takes a numeric App
Store id only.

## Removing a package

Delete the declaration from the env file, then:

```
mise bootstrap packages prune --dry-run     # review first — always
mise bootstrap packages prune
```

**Prune is global.** It proposes removing every installed package that no config
declares, not just the one you deleted, so the dry-run is mandatory. An
installed package with no declaration may simply be under evaluation — bare
`brew install` is a deliberate trial path on this machine — so do not read an
undeclared package as oversight and do not prune it without asking.

## Trial, then formalize

```
brew install <x>                # evaluate it
m run pkg brew:<x> <env>        # keep it
```

mise counts a formula Homebrew installed as installed, so formalizing writes the
declaration and installs nothing.

## Searching

```
mise search <q>     # tools
brew search <q>     # formulae and casks
```

No wrapper wraps both. Two commands for seven uses in five months is not worth
a third function.

## History and rollback

`mise dot paths` lists the tracked files — the ones actually edited live and pushed
back into the repo with `mise dot add`. A watcher service checkpoints them as they
change:

```
mise bootstrap services status         # confirm the watcher is running
mise dot history                       # checkpoints, newest first
mise dot undo                          # reverse the last operation's tracked-file changes
mise dot rollback --to <ref> --all     # return everything a checkpoint covers
```

The history repository is local (`~/.local/state/mise/history/repo.git`) with no
origin; `mise dot sync`/`pull` only become relevant once one is set.

Everything else in `[dotfiles]` is deployed but not tracked, and is versioned by
this git repo instead. Tracked files are edited in place and pulled back; the
rest are edited here and deployed out.

## New machine

```
mise bootstrap --dry-run     # what would be cloned, installed, linked, hooked
mise bootstrap
```

`mise bootstrap` never runs on its own; neither `mise install` nor
`mise dot apply` covers it.

One deployed file is root-owned and needs sudo: the kanata LaunchDaemon plist at
`/Library/LaunchDaemons/com.example.kanata.plist`, declared in
`[bootstrap.files]` with `owner = "root"`. Its reload hook
(`hooks/reload-kanata-daemon.sh`) runs on every bootstrap but reloads the daemon
only when the plist content hash changes, so an unchanged run costs no sudo and
does not restart the keyboard remapper.

## Known warts

- **mise's directories are environment variables, and mise is not on every PATH.** The
  binary is the curl install at `/opt/m/bin/mise`; installs and data both live under
  `/opt/m` via `MISE_INSTALLS_DIR` and `MISE_DATA_DIR`, which are set only in
  `fish/conf.d/00_mise.fish`, `.bashrc` and `.zshenv`. Nothing else provides them — a
  launchd job, GUI app or non-interactive shell that invokes mise falls back to
  `~/.local/share/mise`, finds no tools there and, because `auto_install = true`, can
  rebuild a whole second tool tree. A reappearing `~/.local/share/mise/installs` is a
  bug signal, not a curiosity. Shims are pinned to `/opt/m/shims` by `shims_dir`, so at
  least those are context-independent.
- **`mise dotfiles` is a young subsystem.** Pin the mise version and read the
  release notes before upgrading it.
