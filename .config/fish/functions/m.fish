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
      set -l packages (mise bootstrap packages status --json \
        | jq -r 'to_entries[] | .key as $m | .value.packages[]? | "\($m):\(.package)"' \
        | grep -vxE 'brew:kanata|brew:aisk/tap/timeout')

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
        echo "==> brew packages"
        mise bootstrap packages upgrade --dry-run $packages
      else
        mise upgrade
        mise bootstrap packages upgrade $packages
        brew cleanup
      end
    case '*'
      mise $argv
  end
end
