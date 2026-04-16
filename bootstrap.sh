#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu 24.04 box to match the reference dev machine.
# Idempotent: safe to re-run.

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$BUNDLE_DIR/dotfiles"
NVIM_VERSION="v0.11.6"
NVIM_TARBALL="nvim-linux-x86_64.tar.gz"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TARBALL}"
NVIM_CONFIG_REPO="https://github.com/klosowsk/rklosowski-nvim.git"

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

# --- 1. apt packages ----------------------------------------------------------
log "Installing apt packages"
sudo -v
sudo apt-get update -y
sudo apt-get install -y \
  zsh \
  tmux \
  git \
  curl \
  wget \
  build-essential \
  unzip \
  xclip \
  ca-certificates \
  autojump \
  direnv

# --- 2. neovim 0.11.6 (prebuilt tarball) --------------------------------------
if [[ -x /usr/local/bin/nvim ]] && /usr/local/bin/nvim --version | head -1 | grep -q "${NVIM_VERSION#v}"; then
  log "neovim ${NVIM_VERSION} already installed"
else
  log "Installing neovim ${NVIM_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/$NVIM_TARBALL" "$NVIM_URL"
  sudo rm -rf /opt/nvim-linux-x86_64
  sudo tar -C /opt -xzf "$tmp/$NVIM_TARBALL"
  sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
  rm -rf "$tmp"
fi

# --- 3. oh-my-zsh -------------------------------------------------------------
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  log "oh-my-zsh already present"
else
  log "Installing oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Custom plugins
ZCUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_plugin() {
  local name="$1" url="$2"
  local dest="$ZCUSTOM/plugins/$name"
  if [[ -d "$dest/.git" ]]; then
    log "plugin $name already cloned"
  else
    log "Cloning plugin $name"
    git clone --depth=1 "$url" "$dest"
  fi
}
clone_plugin zsh-autosuggestions       https://github.com/zsh-users/zsh-autosuggestions
clone_plugin zsh-syntax-highlighting   https://github.com/zsh-users/zsh-syntax-highlighting
clone_plugin fast-syntax-highlighting  https://github.com/zdharma-continuum/fast-syntax-highlighting
clone_plugin zsh-autocomplete          https://github.com/marlonrichert/zsh-autocomplete

# --- 4. mise ------------------------------------------------------------------
if command -v mise >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/mise" ]]; then
  log "mise already installed"
else
  log "Installing mise"
  curl -fsSL https://mise.run | sh
fi

# --- 5. Dotfiles --------------------------------------------------------------
log "Writing dotfiles"
mkdir -p "$HOME/.config/mise"

install_file() {
  local src="$1" dst="$2"
  if [[ -f "$dst" && ! -f "${dst}.bak-setup" ]]; then
    cp "$dst" "${dst}.bak-setup"
  fi
  cp "$src" "$dst"
}

install_file "$DOTFILES/zshrc"             "$HOME/.zshrc"
install_file "$DOTFILES/tmux.conf"         "$HOME/.tmux.conf"
install_file "$DOTFILES/gitconfig"         "$HOME/.gitconfig"
install_file "$DOTFILES/mise-config.toml"  "$HOME/.config/mise/config.toml"

# Optional host-specific prompt color. Set BOOTSTRAP_HOST_COLOR (e.g. red,
# blue, green, yellow, magenta, cyan) to tint agnoster's user@host segment so
# you can spot this box instantly when multi-SSH'd. Appended after the dotfile
# copy so it loads after `source $ZSH/oh-my-zsh.sh` and agnoster's theme.
if [[ -n "${BOOTSTRAP_HOST_COLOR:-}" ]] && ! grep -q "# PROMPT_HOST_COLOR_MARKER" "$HOME/.zshrc"; then
  log "Appending ${BOOTSTRAP_HOST_COLOR} prompt_context override to ~/.zshrc"
  cat >> "$HOME/.zshrc" <<EOF

# PROMPT_HOST_COLOR_MARKER — host-specific agnoster prompt_context override
prompt_context() {
  prompt_segment ${BOOTSTRAP_HOST_COLOR} black "%(!.%{%F{yellow}%}.)\$USER@%m"
}
EOF
fi

# --- 6. neovim config ---------------------------------------------------------
if [[ -d "$HOME/.config/nvim/.git" ]]; then
  log "nvim config repo already cloned"
else
  log "Cloning nvim config"
  if [[ -d "$HOME/.config/nvim" ]]; then
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak-setup.$(date +%s)"
  fi
  git clone "$NVIM_CONFIG_REPO" "$HOME/.config/nvim"
fi

# --- 7. mise install ----------------------------------------------------------
log "Running mise install"
export PATH="$HOME/.local/bin:$PATH"
mise install

# --- 8. QoL CLIs (apt) --------------------------------------------------------
log "Installing QoL CLIs"
sudo apt-get install -y \
  jq \
  ripgrep \
  fd-find \
  fzf \
  bat \
  tree \
  htop \
  ncdu

# --- 9. Docker (official apt repo) --------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker CE"
  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
  fi
  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  ARCH="$(dpkg --print-architecture)"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  log "docker already installed"
fi
if ! id -nG "$USER" | grep -qw docker; then
  log "Adding $USER to docker group (re-login required)"
  sudo usermod -aG docker "$USER"
fi

# --- 10. k9s ------------------------------------------------------------------
if ! command -v k9s >/dev/null 2>&1; then
  log "Installing k9s"
  tmp="$(mktemp -d)"
  K9S_URL="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
    | grep browser_download_url \
    | grep -E 'k9s_Linux_amd64\.tar\.gz"' \
    | head -1 | cut -d'"' -f4)"
  curl -fsSL -o "$tmp/k9s.tar.gz" "$K9S_URL"
  tar -C "$tmp" -xzf "$tmp/k9s.tar.gz" k9s
  sudo install -m 0755 "$tmp/k9s" /usr/local/bin/k9s
  rm -rf "$tmp"
else
  log "k9s already installed"
fi

# --- 11. lazygit --------------------------------------------------------------
if ! command -v lazygit >/dev/null 2>&1; then
  log "Installing lazygit"
  tmp="$(mktemp -d)"
  LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
    | grep -Po '"tag_name": "v\K[^"]+')"
  curl -fsSL -o "$tmp/lazygit.tar.gz" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LG_VER}/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
  tar -C "$tmp" -xzf "$tmp/lazygit.tar.gz" lazygit
  sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmp"
else
  log "lazygit already installed"
fi

# --- 12. lazydocker -----------------------------------------------------------
if ! command -v lazydocker >/dev/null 2>&1; then
  log "Installing lazydocker"
  tmp="$(mktemp -d)"
  LD_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest \
    | grep -Po '"tag_name": "v\K[^"]+')"
  curl -fsSL -o "$tmp/lazydocker.tar.gz" \
    "https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VER}/lazydocker_${LD_VER}_Linux_x86_64.tar.gz"
  tar -C "$tmp" -xzf "$tmp/lazydocker.tar.gz" lazydocker
  sudo install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
  rm -rf "$tmp"
else
  log "lazydocker already installed"
fi

# --- 13. default shell --------------------------------------------------------
ZSH_BIN="$(command -v zsh)"
if [[ "${SHELL:-}" != "$ZSH_BIN" ]]; then
  log "Changing default shell to $ZSH_BIN (will prompt for password)"
  sudo chsh -s "$ZSH_BIN" "$USER"
else
  log "Default shell already zsh"
fi

log "Done."
echo "Log out and back in (or start a new SSH session) to land in zsh."
