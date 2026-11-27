function m --description 'wrapper for mise: up (update everything), out (preview), otherwise passthrough'
  if not using mise
    echo "Error: mise is not installed" >&2
    return 1
  end

  switch $argv[1]
    case up out
      # brew:kanata is withheld from every update: it is a HEAD build driving the keyboard
      # remapper LaunchDaemon, and a bottle pour would silently replace HEAD, so upgrading
      # it is always an explicit decision.
      #
      # brew:aisk/tap/timeout is withheld too: its only bottle is tagged arm64_sonoma,
      # so on a newer macOS mise resolves it to the source path and pours its
      # `depends_on "ghc" => :build` (2.2 GB) on every run, even though the formula
      # itself is already current. Upgrade it explicitly if that ever changes.
      set -l declared (mise bootstrap packages status --json \
        | jq -r 'to_entries[] | .key as $m | .value.packages[]? | "\($m):\(.package)"')

      if not set -q declared[1]
        echo "Error: could not read the package list from mise" >&2
        return 1
      end

      # mise's brew-cask manager only ensures a cask is *present*: `upgrade` reports
      # "installed and managed by Homebrew; leaving unchanged" for every cask, so casks
      # are never updated through it. Drive brew instead, but name only the casks that
      # are declared *and* actually outdated: brew warns once per up-to-date cask and
      # exits non-zero when a pinned one is named. `brew outdated` already omits pins,
      # which covers karabiner-elements and thebrowsercompany-dia on their own.
      set -l declared_casks (string replace 'brew-cask:' '' (string match 'brew-cask:*' $declared))
      set -l outdated_casks (brew outdated --cask --json=v2 2>/dev/null | jq -r '.casks[].name' 2>/dev/null)
      set -l casks
      for cask in $declared_casks
        if contains -- $cask $outdated_casks
          set -a casks $cask
        end
      end

      set -l packages (printf '%s\n' $declared \
        | grep -vxE 'brew:kanata|brew:aisk/tap/timeout|brew-cask:.*')

      if not set -q packages[1]
        echo "Error: could not read the package list from mise" >&2
        return 1
      end

      set -l preview false
      if test "$argv[1]" = out; or contains -- $argv[2] -n --dry-run
        set preview true
      end

      if $preview
        echo "==> mise tools"
        mise outdated
        echo "==> brew formulae"
        mise bootstrap packages upgrade --dry-run $packages
        if set -q casks[1]
          echo "==> brew casks"
          brew upgrade --cask --dry-run $casks
        end
      else
        mise upgrade
        mise bootstrap packages upgrade $packages
        if set -q casks[1]
          brew upgrade --cask $casks
        end
        brew cleanup
      end
    case '*'
      mise $argv
  end
end
