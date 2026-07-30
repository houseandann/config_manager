# Bootstrap: keep ~/.zshenv minimal and delegate to XDG zsh config.
# https://zsh.sourceforge.io/Doc/Release/Files.html
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export ZDOTDIR="${ZDOTDIR:-${XDG_CONFIG_HOME}/zsh}"
[[ -r "${ZDOTDIR}/.zshenv" ]] && source "${ZDOTDIR}/.zshenv"
