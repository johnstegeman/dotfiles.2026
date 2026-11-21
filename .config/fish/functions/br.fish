function br
  if not using brew
    echo "Error: brew is not installed" >&2
    return 1
  end

  switch $argv[1]
    case up
      brew update; brew upgrade; brew cleanup; brew doctor
    case in
      # Package declarations live in mise's [bootstrap.packages], one config.<env>.toml
      # per environment; this installs whatever is declared but missing.
      mise bootstrap packages apply
    case '*'
      brew $argv
  end
end
