# One Brewfile for both Macs (D-022). An entry ending in `if n0` installs only on n0, the Mac
# Mini home hub: local LLMs, 3D printing, home hardware, app building, media. Everything else
# is mirrored to book too. Add or drop the suffix by hand; `brew install` never adds it.
n0 = `/usr/sbin/scutil --get HostName 2>/dev/null`.strip == "n0"

# Taps
tap "knative-extensions/kn-plugins"
tap "knative/client"
tap "broots144/tap"

# CLI tools
brew "whisper.cpp"
brew "rtk"
brew "pdftk-java"
brew "imessage-exporter"
brew "htop"
brew "geoip"
brew "herdr"
brew "caddy" if n0
brew "cargo-llvm-cov"
brew "lightpanda-io/browser/lightpanda"
brew "mosh"
brew "scrcpy"
brew "knative-extensions/kn-plugins/func"
brew "knative/client/kn"
brew "xz"
brew "e2fsprogs"
brew "zbar"
brew "gnu-tar"
brew "actionlint"
brew "cfn-lint"
brew "aws-sam-cli"
brew "exiftool"
brew "gitleaks"
brew "pnpm"
brew "yq"
brew "pre-commit"
brew "just"
brew "ansible-lint"
brew "netbird"
brew "rust"
brew "yt-dlp"
brew "cloudflare-wrangler"
brew "b2-tools"
brew "restic"
brew "sops"
brew "age"
brew "hcloud"
brew "opentofu"
brew "xcodegen" if n0
brew "terminal-notifier"
brew "poppler"
brew "fswatch"
brew "wget"
brew "python@3.12"
brew "pipx"
brew "ollama" if n0
brew "ocrmypdf"
brew "grok"
brew "hf"
brew "gemini-cli"
brew "openjdk"
brew "node"
brew "git-filter-repo"
brew "ffmpeg"
brew "docker-compose"
brew "docker-buildx"
brew "docker"
brew "colima"
brew "cocoapods" if n0
brew "keith/formulae/reminders-cli"
brew "openssl"
brew "git"
brew "gh"
brew "awscli"
brew "bash"
brew "coreutils"
brew "findutils"
brew "grep"
brew "go"
brew "lastpass-cli"
brew "mas"
brew "tmux"
brew "zsh"
brew "zsh-completions"

# Modern CLI
brew "fzf"
brew "ripgrep"
brew "fd"
brew "bat"
brew "eza"
brew "zoxide"
brew "jq"
brew "starship"
brew "btop"
brew "dust"
brew "bandwhich"

# Language version managers / runtimes
brew "rbenv"
brew "ruby-build"
brew "pyenv"
brew "python@3.14"
brew "uv"
brew "fnm"

# Infra / ops
brew "kubectl"
brew "helm"
brew "k9s"
brew "ansible"

# Casks
cask "zoom"
cask "plex"
cask "multipass"
cask "iterm2"
cask "firefox"
cask "cakebrew"
cask "orcaslicer" if n0
cask "creality-print" if n0
cask "sparrow"
cask "discord"
cask "deskreen"
cask "localsend"
cask "kde-connect"
cask "android-platform-tools"
cask "tor-browser"
cask "rsyncui"
cask "qfinder-pro" if n0
cask "rectangle"
cask "hammerspoon"
cask "ubersicht"
cask "stats"
cask "swiftbar"
cask "grandperspective"
cask "sloth"
cask "cmux"
cask "raspberry-pi-imager"
cask "maccy"
cask "broots144/tap/claudeglance"
cask "google-drive"
cask "ollama-app" if n0
cask "lm-studio" if n0
cask "anythingllm" if n0
cask "grok-build"
cask "codex"
cask "chatgpt"
cask "flutter" if n0
cask "android-commandlinetools" if n0
cask "alfred"
cask "caffeine"
cask "ghostty"
cask "visual-studio-code"
cask "google-chrome"
cask "handbrake-app" if n0
cask "slack"
cask "sourcetree"
cask "sublime-text"
cask "the-unarchiver"
cask "transmission" if n0
cask "vlc"

# Mac App Store
mas "HDHomeRun", id: 949582631 if n0
mas "Xcode", id: 497799835 if n0
mas "GarageBand", id: 682658836 if n0
mas "iMovie", id: 408981434 if n0
mas "Keynote", id: 361285480
mas "Numbers", id: 361304891
mas "Pages", id: 361309726
