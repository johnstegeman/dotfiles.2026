# mise is the curl install at /opt/m/bin/mise; its installs/data roots are env-only.
export MISE_INSTALLS_DIR=/opt/m
export MISE_DATA_DIR=/opt/m

# Prepended before activation so `mise activate` can find its own binary at all, then
# re-added below because activation rebuilds PATH and drops that directory.
case ":$PATH:" in
  *:/opt/m/bin:*) ;;
  *) export PATH="/opt/m/bin:$PATH" ;;
esac

eval "$(mise activate bash)"

# Activation rebuilds PATH from the tool dirs and drops the directory holding mise's own
# binary, so the entry has to be re-added after it (same lesson as fish/conf.d/00_mise.fish).
case ":$PATH:" in
  *:/opt/m/bin:*) ;;
  *) export PATH="/opt/m/bin:$PATH" ;;
esac