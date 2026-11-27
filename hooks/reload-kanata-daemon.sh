#!/bin/sh
# Reload the kanata system LaunchDaemon only when the installed plist changed
# since the last successful reload.
#
# Two things are checked before the stamp comparison, because both leave the
# daemon running a binary that cannot talk to the Karabiner driver:
#
# - /opt/homebrew/bin/kanata must point at the pinned HEAD keg. The 1.12.0
#   bottle bundles karabiner-driverkit 0.3.1, whose driver IPC differs from the
#   installed driver; pouring it silently stops the keyboard from being
#   remapped, and `brew upgrade`/`mise bootstrap packages` will pour it again
#   unless the pin from hooks/brew-pins.txt is in place.
# - A relink alone changes nothing for a running process, so it forces a reload.
#
# The stamp is the hash of the content that was last successfully reloaded.
# Comparing the installed plist against the desired render cannot work: mise
# applies [bootstrap.files] before the final hook, so by the time this runs the
# installed file already equals the render and a compare always says "same".
set -eu

plist=/Library/LaunchDaemons/com.example.kanata.plist
label=com.example.kanata
stamp_dir=${XDG_STATE_HOME:-$HOME/.local/state}/mise-hooks
stamp=$stamp_dir/kanata-plist.sha256
attempts=3

if [ ! -f "$plist" ]; then
	echo "reload-kanata-daemon: $plist is missing" >&2
	exit 1
fi

prefix=$(brew --prefix 2>/dev/null || echo /opt/homebrew)
linked=$prefix/bin/kanata
head_keg=
for keg in "$prefix"/Cellar/kanata/HEAD-*; do
	if [ -d "$keg" ]; then
		head_keg=$keg
	fi
done

relinked=0
if [ -z "$head_keg" ]; then
	echo "reload-kanata-daemon: no kanata HEAD keg installed; the daemon would run the release bottle, whose bundled driver IPC does not match the installed Karabiner driver. Install it with: brew install --HEAD kanata" >&2
elif [ "$(readlink "$linked" 2>/dev/null)" != "../${head_keg#"$prefix"/}/bin/kanata" ]; then
	echo "reload-kanata-daemon: relinking $linked to $head_keg"
	brew unlink kanata >/dev/null 2>&1 || true
	if ! brew link --HEAD kanata >/dev/null 2>&1; then
		echo "reload-kanata-daemon: brew link --HEAD kanata failed; the daemon would run a build whose driver IPC does not match" >&2
		exit 1
	fi
	relinked=1
fi

current=$(shasum -a 256 "$plist" | awk '{print $1}')
previous=$(if [ -f "$stamp" ]; then cat "$stamp"; else echo none; fi)

if [ "$relinked" -eq 0 ] && [ -f "$stamp" ] && [ "$previous" = "$current" ]; then
	exit 0
fi

echo "reload-kanata-daemon: $label plist sha256 $current, last reloaded $previous; reloading"

attempt=1
while [ "$attempt" -le "$attempts" ]; do
	# bootout is asynchronous, so launchd can refuse the new job for a moment after it
	sudo launchctl bootout "system/$label" >/dev/null 2>&1 || true
	if sudo launchctl bootstrap system "$plist"; then
		mkdir -p "$stamp_dir"
		printf '%s\n' "$current" >"$stamp"
		exit 0
	fi
	if [ "$attempt" -lt "$attempts" ]; then
		sleep 1
	fi
	attempt=$((attempt + 1))
done

echo "reload-kanata-daemon: could not load $label after $attempts attempts; stamp left at $previous so the next run retries" >&2
exit 1
