#!/bin/sh
# Enforce the Homebrew pins declared in hooks/brew-pins.txt.
#
# A pin lives in machine state (a symlink under /opt/homebrew/var/homebrew/pinned
# for formulae, Caskroom metadata for casks), never in this repository, so a
# migration between dotfiles managers loses it silently. That is what happened
# between haven and mise: the kanata and karabiner-elements pins vanished and
# `brew upgrade` / `mise bootstrap packages` started floating them, which is how
# the kanata HEAD build got replaced by a bottle whose driver IPC does not match
# the installed Karabiner driver.
#
# The bootstrap hook runs this before the packages step (pin what is already
# installed, so an upgrade cannot move it) and again after it (pin what the step
# just installed). Pins that already match cost nothing.
#
# Pins outside the declared list are reported but never removed: unpinning is an
# explicit decision, exactly like upgrading one of these packages.
set -eu

list=${BREW_PINS_FILE:-$HOME/.dotfiles/hooks/brew-pins.txt}

if [ ! -f "$list" ]; then
	echo "ensure-brew-pins: $list is missing" >&2
	exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
	echo "ensure-brew-pins: brew is not on PATH, skipping"
	exit 0
fi

# Strip comments, blanks and trailing spaces; one package name per line.
declared=$(awk '{sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, "")} NF {print $1}' "$list")
pinned=$(brew list --pinned 2>/dev/null || true)
failed=0

for name in $declared; do
	if printf '%s\n' "$pinned" | grep -qxF "$name"; then
		continue
	fi

	# Resolve the package kind first: brew pin takes --formula or --cask, and
	# silently pinning the wrong namespace would leave the real package floating.
	if brew list --versions --formula "$name" >/dev/null 2>&1; then
		kind=--formula
	elif brew list --versions --cask "$name" >/dev/null 2>&1; then
		kind=--cask
	else
		echo "ensure-brew-pins: $name is declared but not installed yet; skipping"
		continue
	fi

	if brew pin "$kind" "$name" >/dev/null 2>&1; then
		echo "ensure-brew-pins: pinned $name ($kind)"
	else
		echo "ensure-brew-pins: could not pin $name ($kind)" >&2
		failed=1
	fi
done

for name in $pinned; do
	if ! printf '%s\n' "$declared" | grep -qxF "$name"; then
		echo "ensure-brew-pins: $name is pinned but not declared in brew-pins.txt" >&2
	fi
done

exit "$failed"
