# XDG Base Directory Specification
# https://specifications.freedesktop.org/basedir-spec/latest/
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export PATH="${HOME}/.local/bin:${PATH}"

# History (state dir, not config dir)
export HISTFILE="${XDG_STATE_HOME}/zsh/history"
export HISTSIZE=50000
export SAVEHIST=50000

# Default editor
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${EDITOR}"

# Rust toolchain (optional)
[[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env"

export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd
