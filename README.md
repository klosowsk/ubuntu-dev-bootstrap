# ubuntu-dev-bootstrap

One-shot bootstrap for a fresh **Ubuntu 24.04** dev box — my personal reference setup, idempotent and safe to re-run.

## Usage

On a fresh box (needs `sudo` rights; will prompt once):

```sh
git clone https://github.com/klosowsk/ubuntu-dev-bootstrap.git
cd ubuntu-dev-bootstrap
bash bootstrap.sh
```

Or one-liner:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/klosowsk/ubuntu-dev-bootstrap/main/bootstrap.sh)"
```

> The one-liner only works if the `dotfiles/` directory is next to the script. For `curl | bash` use, clone first.

### Optional: colored prompt for this host

Tints agnoster's `user@host` segment so you can tell which box you're on at a glance:

```sh
BOOTSTRAP_HOST_COLOR=red bash bootstrap.sh
```

Valid values: `red`, `green`, `blue`, `yellow`, `magenta`, `cyan` (any color agnoster's `prompt_segment` accepts).

## What it installs

### Shell / editor
- **zsh + oh-my-zsh** with agnoster theme
- Plugins: `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fast-syntax-highlighting`, `zsh-autocomplete`
- **tmux** + catppuccin-mocha status config
- **neovim 0.11.6** (prebuilt tarball → `/usr/local/bin/nvim`)
- nvim config cloned from [klosowsk/rklosowski-nvim](https://github.com/klosowsk/rklosowski-nvim)

### Runtime / languages
- **mise** — installs `node`, `bun`, `kubectl`, `helm` per `dotfiles/mise-config.toml`
- `autojump`, `direnv`

### Kubernetes / containers
- **docker-ce** + buildx + compose plugin (official Docker apt repo)
- User added to `docker` group
- **k9s** — k8s cluster TUI
- `kubectl`, `helm` via mise (see above)

### Dev CLIs
- `lazygit`, `lazydocker`
- `jq`, `ripgrep`, `fd-find`, `fzf`, `bat`, `tree`, `htop`, `ncdu`
- `build-essential`, `unzip`, `xclip`, `git`, `curl`, `wget`, `ca-certificates`

### Dotfiles copied to `$HOME`
- `.zshrc`, `.tmux.conf`, `.gitconfig`, `.config/mise/config.toml`

Existing files are backed up to `<file>.bak-setup` on first run.

## Idempotency

Every step checks whether the target is already installed/configured. Re-running picks up new additions to the script without clobbering state. The one side-effect to know about: `install_file` only backs up the *first* time — subsequent runs overwrite dotfiles in place with whatever is in `dotfiles/`. If you hand-edit a dotfile on a target box, fold the change back into this repo.

## Layout

```
bootstrap.sh          # The installer
dotfiles/
  zshrc
  tmux.conf
  gitconfig
  mise-config.toml
```

## Post-install

- New shell / re-SSH to land in zsh.
- Log out + back in once for `docker` group to take effect.
- If you asked for a host color, the red/blue/etc. prompt is at the bottom of `~/.zshrc` — marker `# PROMPT_HOST_COLOR_MARKER` — edit or delete there.
