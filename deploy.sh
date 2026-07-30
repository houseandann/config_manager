#!/usr/bin/env bash
#
# config_manager deploy script
#
# Installs dependencies and links dotfiles from this repo into the home directory.
# Compatible with most Linux distros (apt, dnf, yum, pacman, zypper, apk).
#
# Usage:
#   ./deploy.sh                 # interactive (recommended)
#   ./deploy.sh --yes           # accept all overwrites
#   ./deploy.sh --only-configs  # link configs only, skip package installs
#   ./deploy.sh --skip-packages # link configs + external tools, skip system packages
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}"
XDG_DATA="${XDG_DATA_HOME:-${HOME}/.local/share}"
ZSH_DIR="${XDG_DATA}/oh-my-zsh"
TMUX_PLUGINS="${XDG_CONFIG}/tmux/plugins"
BACKUP_DIR="${HOME}/.config_manager_backup/$(date +%Y%m%d_%H%M%S)"

AUTO_YES=false
ONLY_CONFIGS=false
SKIP_PACKAGES=false
OVERWRITE_ALL=false
PKG_MANAGER=""
DISTRO_ID="unknown"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --yes) AUTO_YES=true; OVERWRITE_ALL=true ;;
      --only-configs) ONLY_CONFIGS=true ;;
      --skip-packages) SKIP_PACKAGES=true ;;
      -h | --help) usage ;;
      *) error "Unknown option: $1"; usage ;;
    esac
    shift
  done
}

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER=apt
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER=dnf
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER=yum
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER=pacman
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER=zypper
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER=apk
  else
    PKG_MANAGER=unknown
  fi

  info "Detected distro: ${DISTRO_ID} (package manager: ${PKG_MANAGER})"
}

prompt_yes_no() {
  local question="$1"
  local default="${2:-n}"

  if $AUTO_YES; then
    return 0
  fi

  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"

  while true; do
    read -rp "${question} ${hint}: " answer
    answer="${answer:-$default}"
    case "${answer,,}" in
      y | yes) return 0 ;;
      n | no) return 1 ;;
    esac
  done
}

prompt_overwrite() {
  local target="$1"
  local description="$2"
  local expected_src="$3"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink -f "$target" 2>/dev/null || readlink "$target")"
    local expected
    expected="$(readlink -f "$expected_src" 2>/dev/null || readlink -f "$expected_src")"
    if [[ "$current" == "$expected" ]]; then
      info "Already linked: ${target}"
      return 2
    fi
  fi

  if $OVERWRITE_ALL; then
    return 0
  fi

  while true; do
    read -rp "Overwrite ${description} (${target})? [y/N/a=all/s=skip]: " answer
    case "${answer,,}" in
      y | yes) return 0 ;;
      a | all) OVERWRITE_ALL=true; return 0 ;;
      s | skip | n | no | "") return 1 ;;
    esac
  done
}

backup_path() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "${BACKUP_DIR}"
    local rel="${target#${HOME}/}"
    local dest="${BACKUP_DIR}/${rel}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$target" "$dest"
    info "Backed up: ${target} -> ${dest}"
  fi
}

link_path() {
  local src="$1"
  local dst="$2"
  local description="$3"

  if [[ ! -e "$src" ]]; then
    warn "Source missing, skip: ${src}"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  local result=0
  prompt_overwrite "$dst" "$description" "$src" || result=$?

  if [[ $result -eq 2 ]]; then
    return 0
  elif [[ $result -eq 1 ]]; then
    warn "Skipped: ${dst}"
    return 0
  fi

  backup_path "$dst"
  ln -sfn "$src" "$dst"
  info "Linked: ${dst} -> ${src}"
}

copy_if_missing() {
  local src="$1"
  local dst="$2"
  local description="$3"

  if [[ -f "$dst" ]]; then
    info "Already exists: ${dst}"
    return 0
  fi

  if prompt_yes_no "Create ${description} at ${dst}?"; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    info "Created: ${dst}"
  fi
}

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    error "Need root privileges but sudo is not available."
    return 1
  fi
}

pkg_name() {
  local logical="$1"
  case "${PKG_MANAGER}:${logical}" in
    apt:fd) echo "fd-find" ;;
    apt:rg) echo "ripgrep" ;;
    apt:eza) echo "eza" ;;
    dnf:fd | yum:fd | pacman:fd | zypper:fd | apk:fd) echo "fd" ;;
    dnf:rg | yum:rg | pacman:rg | zypper:rg | apk:rg) echo "ripgrep" ;;
    dnf:eza | yum:eza | pacman:eza | zypper:eza) echo "eza" ;;
    pacman:neovim | *) echo "$logical" ;;
  esac
}

install_system_packages() {
  if $SKIP_PACKAGES || $ONLY_CONFIGS; then
    info "Skipping system package installation."
    return 0
  fi

  if [[ "$PKG_MANAGER" == "unknown" ]]; then
    warn "Unknown package manager. Install dependencies manually."
    return 0
  fi

  local logical_packages=(zsh git curl unzip tar fontconfig neovim tmux fzf ripgrep fd eza)
  local to_install=()
  local pkg

  for logical in "${logical_packages[@]}"; do
    pkg="$(pkg_name "$logical")"
    case "$logical" in
      neovim)
        if command -v nvim >/dev/null 2>&1; then
          info "Already installed: nvim"
          continue
        fi
        ;;
      ripgrep)
        if command -v rg >/dev/null 2>&1; then
          info "Already installed: rg"
          continue
        fi
        ;;
      fd)
        if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
          info "Already installed: fd"
          continue
        fi
        ;;
      eza)
        if command -v eza >/dev/null 2>&1; then
          info "Already installed: eza"
          continue
        fi
        ;;
      *)
        if command -v "$logical" >/dev/null 2>&1; then
          info "Already installed: ${logical}"
          continue
        fi
        ;;
    esac
    to_install+=("$pkg")
  done

  # kitty is often missing from default repos on Debian/Ubuntu
  if ! command -v kitty >/dev/null 2>&1; then
    case "$PKG_MANAGER" in
      apt)
        warn "kitty is not installed. On Debian/Ubuntu, install from: https://sw.kovidgoyal.net/kitty/binary/"
        ;;
      *)
        to_install+=("kitty")
        ;;
    esac
  else
    info "Already installed: kitty"
  fi

  if [[ ${#to_install[@]} -eq 0 ]]; then
    info "All system packages are already installed."
    return 0
  fi

  info "Packages to install: ${to_install[*]}"
  if ! prompt_yes_no "Install missing system packages?"; then
    warn "Skipped system package installation."
    return 0
  fi

  case "$PKG_MANAGER" in
    apt)
      run_privileged apt-get update -qq
      run_privileged apt-get install -y "${to_install[@]}" || warn "Some packages failed to install."
      ;;
    dnf) run_privileged dnf install -y "${to_install[@]}" || warn "Some packages failed to install." ;;
    yum) run_privileged yum install -y "${to_install[@]}" || warn "Some packages failed to install." ;;
    pacman) run_privileged pacman -S --noconfirm "${to_install[@]}" || warn "Some packages failed to install." ;;
    zypper) run_privileged zypper --non-interactive install "${to_install[@]}" || warn "Some packages failed to install." ;;
    apk) run_privileged apk add "${to_install[@]}" || warn "Some packages failed to install." ;;
  esac
}

install_starship() {
  if $ONLY_CONFIGS; then
    return 0
  fi

  if command -v starship >/dev/null 2>&1; then
    local version
    version="$(starship --version 2>/dev/null | head -1 || true)"
    info "Already installed: starship ${version}"
    if ! $AUTO_YES && ! prompt_yes_no "Reinstall starship?"; then
      return 0
    fi
  elif ! prompt_yes_no "Install starship prompt?"; then
    return 0
  fi

  info "Installing starship..."
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
}

install_oh_my_zsh() {
  if $ONLY_CONFIGS; then
    return 0
  fi

  if [[ -f "${ZSH_DIR}/oh-my-zsh.sh" ]]; then
    info "Already installed: oh-my-zsh at ${ZSH_DIR}"
    if ! $AUTO_YES && ! prompt_yes_no "Reinstall oh-my-zsh?"; then
      install_omz_plugins
      return 0
    fi
    if prompt_yes_no "Remove existing oh-my-zsh before reinstall?" "y"; then
      rm -rf "${ZSH_DIR}"
    else
      install_omz_plugins
      return 0
    fi
  elif ! prompt_yes_no "Install oh-my-zsh to ${ZSH_DIR}?"; then
    return 0
  fi

  info "Installing oh-my-zsh..."
  export ZSH="${ZSH_DIR}"
  export RUNZSH=no
  export CHSH=no
  export KEEP_ZSHRC=yes
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  install_omz_plugins
}

install_omz_plugins() {
  local plugins_dir="${ZSH_DIR}/custom/plugins"
  mkdir -p "${plugins_dir}"

  declare -A plugins=(
    [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
    [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
  )

  local name url target
  for name in "${!plugins[@]}"; do
    url="${plugins[$name]}"
    target="${plugins_dir}/${name}"

    if [[ -d "${target}/.git" ]]; then
      info "Already installed: OMZ plugin ${name}"
      if $AUTO_YES || prompt_yes_no "Update OMZ plugin ${name}?"; then
        git -C "$target" pull --ff-only || warn "Failed to update ${name}"
      fi
      continue
    fi

    if [[ -e "$target" ]]; then
      if ! prompt_overwrite "$target" "OMZ plugin ${name}" "$target"; then
        continue
      fi
      backup_path "$target"
      rm -rf "$target"
    fi

    if prompt_yes_no "Install OMZ plugin ${name}?"; then
      git clone --depth=1 "$url" "$target"
      info "Installed: ${name}"
    fi
  done
}

install_tpm() {
  if $ONLY_CONFIGS; then
    return 0
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    warn "tmux not found, skipping TPM install."
    return 0
  fi

  local tpm_dir="${TMUX_PLUGINS}/tpm"
  if [[ -d "${tpm_dir}/.git" ]]; then
    info "Already installed: TPM at ${tpm_dir}"
    if $AUTO_YES || prompt_yes_no "Update TPM?"; then
      git -C "$tpm_dir" pull --ff-only || warn "Failed to update TPM"
    fi
  else
    if ! prompt_yes_no "Install tmux plugin manager (TPM)?"; then
      return 0
    fi
    mkdir -p "${TMUX_PLUGINS}"
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir"
    info "Installed TPM."
  fi

  install_tpm_plugins
}

install_tpm_plugins() {
  local tpm_dir="${TMUX_PLUGINS}/tpm"
  local installer="${tpm_dir}/bin/install_plugins"

  if [[ ! -x "$installer" ]]; then
    warn "TPM installer not found at ${installer}"
    return 0
  fi

  if ! prompt_yes_no "Install/update tmux plugins via TPM?"; then
    return 0
  fi

  info "Installing tmux plugins (no need to press prefix + I)..."
  TMUX_PLUGIN_MANAGER_PATH="${TMUX_PLUGINS}" bash "$installer"
  info "Tmux plugins installed."
}

jetbrains_mono_installed() {
  fc-list : family 2>/dev/null | grep -qi 'jetbrains.*mono.*nerd'
}

install_jetbrains_mono_font() {
  if $ONLY_CONFIGS; then
    return 0
  fi

  if jetbrains_mono_installed; then
    info "JetBrains Mono Nerd Font is already installed."
    if ! $AUTO_YES && ! prompt_yes_no "Reinstall JetBrains Mono Nerd Font?"; then
      return 0
    fi
  elif ! prompt_yes_no "Install JetBrains Mono Nerd Font (for kitty/nvim icons)?"; then
    return 0
  fi

  # Arch ships the nerd-patched font directly.
  if [[ "$PKG_MANAGER" == "pacman" ]] && ! $SKIP_PACKAGES; then
    if prompt_yes_no "Install ttf-jetbrains-mono-nerd via pacman?"; then
      run_privileged pacman -S --noconfirm ttf-jetbrains-mono-nerd && fc-cache -fv
      if jetbrains_mono_installed; then
        info "JetBrains Mono Nerd Font installed via pacman."
        return 0
      fi
    fi
  fi

  local nerd_version="v3.3.0"
  local font_dir="${HOME}/.local/share/fonts/JetBrainsMonoNerd"
  local tmp_dir

  if ! command -v unzip >/dev/null 2>&1; then
    warn "unzip is required to install JetBrains Mono Nerd Font."
    return 1
  fi

  info "Downloading JetBrainsMono Nerd Font (${nerd_version})..."
  tmp_dir="$(mktemp -d)"
  curl -fsSL \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/${nerd_version}/JetBrainsMono.zip" \
    -o "${tmp_dir}/JetBrainsMono.zip"
  mkdir -p "$font_dir"
  unzip -qo "${tmp_dir}/JetBrainsMono.zip" -d "$font_dir"
  rm -rf "$tmp_dir"

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv "$font_dir" "${HOME}/.local/share/fonts" >/dev/null 2>&1 || fc-cache -fv
  fi

  if jetbrains_mono_installed; then
    info "JetBrains Mono Nerd Font installed to ${font_dir}"
  else
    warn "Font files were installed, but fontconfig did not report them yet. Restart kitty or run: fc-cache -fv"
  fi
}

install_nvm() {
  if $ONLY_CONFIGS; then
    return 0
  fi

  local nvm_dir="${HOME}/.nvm"
  if [[ -s "${nvm_dir}/nvm.sh" ]]; then
    info "Already installed: nvm at ${nvm_dir}"
    if ! $AUTO_YES && ! prompt_yes_no "Reinstall nvm?"; then
      return 0
    fi
  elif ! prompt_yes_no "Install nvm (Node Version Manager)?"; then
    return 0
  fi

  info "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
}

install_fzf() {
  if $ONLY_CONFIGS; then
    return 0
  fi

  if command -v fzf >/dev/null 2>&1; then
    info "Already installed: fzf"
    return 0
  fi

  if ! prompt_yes_no "Install fzf via git (when not available from package manager)?"; then
    return 0
  fi

  local fzf_dir="${XDG_DATA}/fzf"
  if [[ -d "${fzf_dir}/.git" ]]; then
    git -C "$fzf_dir" pull --ff-only
  else
    git clone --depth=1 https://github.com/junegunn/fzf.git "$fzf_dir"
  fi
  "$fzf_dir/install" --all --no-bash --no-fish
  info "Installed fzf to ${fzf_dir}"
}

deploy_configs() {
  info "Linking configuration files..."

  link_path "${REPO_ROOT}/.zshenv" "${HOME}/.zshenv" "zsh bootstrap (~/.zshenv)"
  link_path "${REPO_ROOT}/xdg_config/zsh" "${XDG_CONFIG}/zsh" "zsh config"
  link_path "${REPO_ROOT}/xdg_config/starship" "${XDG_CONFIG}/starship" "starship config"
  link_path "${REPO_ROOT}/xdg_config/tmux" "${XDG_CONFIG}/tmux" "tmux config"
  link_path "${REPO_ROOT}/xdg_config/kitty" "${XDG_CONFIG}/kitty" "kitty config"
  link_path "${REPO_ROOT}/xdg_config/nvim" "${XDG_CONFIG}/nvim" "neovim config"

  copy_if_missing \
    "${REPO_ROOT}/xdg_config/zsh/local.zsh.example" \
    "${XDG_CONFIG}/zsh/local.zsh" \
    "local zsh overrides"

  mkdir -p "${HOME}/.local/state/zsh"
}

maybe_change_shell() {
  if ! command -v zsh >/dev/null 2>&1; then
    warn "zsh is not installed, skipping shell change."
    return 0
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    info "Default shell is already zsh."
    return 0
  fi

  if prompt_yes_no "Change default shell to zsh (${zsh_path})?"; then
    if command -v chsh >/dev/null 2>&1; then
      chsh -s "$zsh_path"
      info "Default shell changed. Log out and back in for it to take effect."
    else
      warn "chsh not found. Run manually: chsh -s ${zsh_path}"
    fi
  fi
}

print_summary() {
  echo
  info "Deployment complete!"
  echo
  echo "Next steps:"
  echo "  1. Open a new terminal (or run: exec zsh -l)"
  echo "  2. Restart kitty to pick up JetBrains Mono Nerd Font"
  echo "  3. Run nvim — lazy.nvim will bootstrap plugins on first launch"
  if [[ -d "${BACKUP_DIR}" ]]; then
    echo "  4. Previous configs backed up to: ${BACKUP_DIR}"
  fi
  echo
}

main() {
  parse_args "$@"
  detect_distro

  info "Repo: ${REPO_ROOT}"
  info "Backup dir: ${BACKUP_DIR}"

  install_system_packages
  deploy_configs
  install_oh_my_zsh
  install_starship
  install_nvm
  install_fzf
  install_jetbrains_mono_font
  install_tpm
  maybe_change_shell
  print_summary
}

main "$@"
