# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias docs='cd ~/Documents'
alias dl='cd ~/Downloads'
alias desk='cd ~/Desktop'
alias proj='cd ~/Documents/git'

# List
alias ll='ls -lah'
alias la='ls -A'
alias lsd='ls -l | grep "^d"'
alias lt='ls -lht'
alias lsize='ls -lhS'

# Use eza if available (modern ls replacement)
if command -v eza &> /dev/null; then
    alias ls='eza'
    alias ll='eza -lah --git'
    alias la='eza -a'
    alias lt='eza -lah --sort=modified'
    alias tree='eza --tree'
fi

# Git
alias gs='git status'
alias gss='git status -s'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gl='git pull'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'
alias gd='git diff'
alias gds='git diff --staged'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'

# Homebrew
alias brewup='brew update && brew upgrade && brew cleanup'
alias brewls='brew list'

# npm
alias ni='npm install'
alias nid='npm install --save-dev'
alias nig='npm install -g'
alias nrun='npm run'
alias nstart='npm start'
alias ntest='npm test'
alias nbuild='npm run build'
alias npmg='npm list -g --depth=0'
alias npmfresh='rm -rf node_modules package-lock.json && npm install'

# nvm
alias nvmls='nvm list'
alias nvmuse='nvm use'

# Docker
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dc='docker-compose'
alias dcup='docker-compose up -d'
alias dcdown='docker-compose down'
alias dclogs='docker-compose logs -f'

# Utilities
alias mkdir='mkdir -pv'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias df='df -h'
alias du='du -h'

# Network
alias localip='ipconfig getifaddr en0'
alias ping='ping -c 5'

# macOS
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'

# Config
alias zshconfig='vim ~/Documents/git/dotfiles/zsh/.zshrc'
alias aliases='vim ~/Documents/git/dotfiles/zsh/aliases.zsh'
alias functions='vim ~/Documents/git/dotfiles/zsh/functions.zsh'
alias gitconfig='vim ~/Documents/git/dotfiles/git/.gitconfig'
alias reload='source ~/.zshrc'

# fzf-powered search (INDUSTRY STANDARD)
alias preview='fzf --preview "bat --color=always {}"'
alias gco='git checkout $(git branch | fzf)'
