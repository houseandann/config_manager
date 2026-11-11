# Extra PATH entries (cargo is handled in .zshenv)
export PATH="${HOME}/.opencode/bin:${HOME}/bin:/usr/local/bin:/usr/local/go/bin:${PATH}"

# Oh My Zsh — installed to XDG_DATA_HOME by deploy.sh
export ZSH="${XDG_DATA_HOME}/oh-my-zsh"

# Starship handles the prompt; leave OMZ theme empty
export ZSH_THEME=""

CASE_SENSITIVE="true"

# zsh-syntax-highlighting must be the last plugin
plugins=(git zsh-autosuggestions command-not-found zsh-syntax-highlighting)

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=244"

if [[ -r "${ZSH}/oh-my-zsh.sh" ]]; then
  source "${ZSH}/oh-my-zsh.sh"
else
  echo "oh-my-zsh not found at ${ZSH}. Run deploy.sh to install it." >&2
fi

bindkey ',' autosuggest-accept

# Prompt
if command -v starship >/dev/null 2>&1; then
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME}/starship/starship.toml"
  eval "$(starship init zsh)"
fi

# History
setopt no_share_history
unsetopt share_history
setopt HIST_FIND_NO_DUPS
setopt INC_APPEND_HISTORY

export LESS=ixFR

source "${ZDOTDIR}/aliases.zsh"

# nvm — lazy-loaded to keep shell startup fast
export NVM_DIR="${HOME}/.nvm"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  nvm() {
    unset -f nvm
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
    nvm "$@"
  }
  node() {
    unset -f node nvm
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
    node "$@"
  }
  npm() {
    unset -f npm nvm
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
    npm "$@"
  }
fi

# fzf — prefer XDG install path, fall back to legacy ~/.fzf.zsh
if [[ -f "${XDG_DATA_HOME}/fzf/shell/completion.zsh" ]]; then
  source "${XDG_DATA_HOME}/fzf/shell/completion.zsh"
  source "${XDG_DATA_HOME}/fzf/shell/key-bindings.zsh"
elif [[ -f "${HOME}/.fzf.zsh" ]]; then
  source "${HOME}/.fzf.zsh"
fi

# Machine-specific overrides (not tracked in git)
[[ -f "${ZDOTDIR}/local.zsh" ]] && source "${ZDOTDIR}/local.zsh"
