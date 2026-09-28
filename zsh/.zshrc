# Keep PATH entries unique: .zprofile, brew shellenv and nested shells each
# prepend again, which left every Homebrew dir listed several times.
typeset -U path PATH

# Oh My Zsh Configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="" # Disabled to use Starship

plugins=(
  macos
  brew
  node
  npm
  docker
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# Never prompt for updates: the prompt eats the first keystroke of commands typed by Orca.
zstyle ':omz:update' mode reminder

source $ZSH/oh-my-zsh.sh

# Homebrew PATH (auto-detect architecture)
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# User-local binaries (claude, etc.)
export PATH="$HOME/.local/bin:$PATH"

# Antigravity CLI (agy)
[ -d "$HOME/.antigravity/antigravity/bin" ] && export PATH="$PATH:$HOME/.antigravity/antigravity/bin"

# fnm - Fast Node Manager
if command -v fnm &> /dev/null; then
    eval "$(fnm env --use-on-cd)"
fi

# fzf - Fuzzy Finder
if [[ -f ~/.fzf.zsh ]]; then
    source ~/.fzf.zsh
elif [[ -f "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh" ]]; then
    source "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
    source "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh"
fi
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# fzf options
export FZF_DEFAULT_OPTS='
  --height 40%
  --layout=reverse
  --border
  --inline-info
  --preview "bat --style=numbers --color=always --line-range :500 {}"
'

# Environment Variables
export EDITOR='code --wait'
export VISUAL='code --wait'
export LANG='en_US.UTF-8'
export LESS='-R'
export HOMEBREW_NO_ANALYTICS=1

# Load custom configurations
[ -f "$HOME/Documents/git/personal/dotfiles/zsh/aliases.zsh" ] && source "$HOME/Documents/git/personal/dotfiles/zsh/aliases.zsh"
[ -f "$HOME/Documents/git/personal/dotfiles/zsh/functions.zsh" ] && source "$HOME/Documents/git/personal/dotfiles/zsh/functions.zsh"

# History
HISTFILE=~/.zsh_history
HISTSIZE=500000
SAVEHIST=500000
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY

# Completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Navigation
setopt AUTO_CD
setopt PUSHD_SILENT
setopt CORRECT

# Performance
ZSH_DISABLE_COMPFIX=true
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv &>/dev/null && eval "$(pyenv init -)"

# direnv - per-directory environment variables
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# zoxide - smarter cd
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# OpenClaw Completion
[ -f "$HOME/.openclaw/completions/openclaw.zsh" ] && source "$HOME/.openclaw/completions/openclaw.zsh"

# LM Studio CLI
[ -d "$HOME/.lmstudio/bin" ] && export PATH="$PATH:$HOME/.lmstudio/bin"

[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# Initialize Starship prompt
if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
fi
