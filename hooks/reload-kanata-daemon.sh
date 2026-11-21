#!/bin/sh
# Reload the kanata system LaunchDaemon only when the installed plist changed
# since the last successful reload.
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

current=$(shasum -a 256 "$plist" | awk '{print $1}')
previous=$(if [ -f "$stamp" ]; then cat "$stamp"; else echo none; fi)

if [ -f "$stamp" ] && [ "$previous" = "$current" ]; then
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
