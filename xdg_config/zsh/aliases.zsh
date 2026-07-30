# fd: Debian/Ubuntu ship the binary as fdfind
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd=fdfind
fi

# eza renames several GNU ls short flags. Use functions so flags like
# "ll -t" / "ls -lt" map to eza's --sort=modified instead of erroring.
if command -v eza >/dev/null 2>&1; then
  _eza_map_flags() {
  local -a mapped=()
  local arg long=0 reverse=0

  for arg in "$@"; do
    case "$arg" in
      --)
        mapped+=("$arg")
        shift
        mapped+=("$@")
        break
        ;;
      -l) long=1 ;;
      -lt | -tl)
        long=1
        mapped+=(-s modified)
        ;;
      -ltr | -rtl | -trl | -rt)
        long=1
        mapped+=(-s modified)
        reverse=1
        ;;
      -t) mapped+=(-s modified) ;;
      -tr | -rt)
        mapped+=(-s modified)
        reverse=1
        ;;
      -S) mapped+=(-s size) ;;
      -Sr | -rS)
        mapped+=(-s size)
        reverse=1
        ;;
      -r) reverse=1 ;;
      -h) ;; # eza long format is human-readable by default
      -a | -A) ;; # covered by base args
      -l*)
        local rest="${arg#-l}"
        if [[ -z "$rest" ]]; then
          long=1
          continue
        fi
        long=1
        local i c
        for ((i = 1; i <= ${#rest}; i++)); do
          c="${rest[i]}"
          case "$c" in
            t) mapped+=(-s modified) ;;
            r) reverse=1 ;;
            S) mapped+=(-s size) ;;
            h | a | A) ;;
            *) mapped+=("-$c") ;;
          esac
        done
        ;;
      -[tSr]*)
        local rest="${arg#-}"
        local i c
        for ((i = 1; i <= ${#rest}; i++)); do
          c="${rest[i]}"
          case "$c" in
            t) mapped+=(-s modified) ;;
            r) reverse=1 ;;
            S) mapped+=(-s size) ;;
            *) mapped+=("-$c") ;;
          esac
        done
        ;;
      *) mapped+=("$arg") ;;
    esac
  done

  ((reverse)) && mapped+=(-r)

  _eza_mapped=("${mapped[@]}")
  _eza_long=$long
  }

  ls() {
    _eza_map_flags "$@"
    if (( _eza_long )); then
      eza -l -g -a --icons "${_eza_mapped[@]}"
    else
      eza -g -a --icons "${_eza_mapped[@]}"
    fi
  }

  ll() {
    _eza_map_flags "$@"
    eza -l -g -a --icons "${_eza_mapped[@]}"
  }

  la() { ls -la "$@" }
  lt() { ls -lt "$@" }
  ltr() { ls -ltr "$@" }
else
  alias ls='ls -a --color=auto'
  alias ll='ls -l'
  alias la='ls -la'
  alias lt='ls -lt'
  alias ltr='ls -ltr'
fi

alias vi=nvim
alias vim=nvim

extract() {
  if [[ ! -f "$1" ]]; then
    echo "'$1' is not a valid file"
    return 1
  fi

  case "$1" in
    *.tar.bz2 | *.tbz2) tar xjf "$1" ;;
    *.tar.gz | *.tgz) tar xzf "$1" ;;
    *.tar.xz | *.txz) tar xJf "$1" ;;
    *.tar) tar xf "$1" ;;
    *.bz2) bunzip2 "$1" ;;
    *.rar) unrar x "$1" ;;
    *.gz) gunzip "$1" ;;
    *.zip) unzip "$1" ;;
    *.Z) uncompress "$1" ;;
    *.7z) 7z x "$1" ;;
    *) echo "'$1' cannot be extracted via extract()" ;;
  esac
}
