set -gx MISE_INSTALLS_DIR /opt/m
set -gx MISE_DATA_DIR /opt/m

# mise is the curl install at /opt/m/bin/mise, not Homebrew: it must be on PATH
# before the `using mise` test below and in non-interactive shells.
if not contains /opt/m/bin $PATH
    set -gx PATH /opt/m/bin $PATH
end

status is-interactive; and begin

   if using mise
      mise activate fish | source
   end

end

# Activation rewrites PATH and drops the directory holding its own binary, erasing
# the entry above (measured: 0 entries after sourcing it), so re-add it here.
if not contains /opt/m/bin $PATH
    set -gx PATH /opt/m/bin $PATH
end

# Non-interactive shells get no activation above - Rex panes and scripts run the login
# shell's environment but not its interactive configuration - so they would have mise
# itself but none of its tools. The shims are the documented non-interactive path:
# rg, pi and friends have to be visible to child processes spawned there.
if not status is-interactive
    if not contains /opt/m/shims $PATH
        set -gx PATH /opt/m/shims $PATH
    end
end
