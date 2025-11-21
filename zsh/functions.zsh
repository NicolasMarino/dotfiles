# Navigation & Files
mkcd() {
    [ -z "$1" ] && echo "Usage: mkcd <dir>" && return 1
    mkdir -p "$1" && cd "$1"
}

up() {
    local d=""
    local limit="${1:-1}"
    for ((i=1; i<=limit; i++)); do
        d="../$d"
    done
    cd "$d" || return 1
}

fnd() {
    [ -z "$1" ] && echo "Usage: fnd <name>" && return 1
    find . -iname "*$1*" 2>/dev/null
}

findin() {
    [ -z "$1" ] && echo "Usage: findin <text> [dir]" && return 1
    local dir="${2:-.}"
    grep -r "$1" "$dir" 2>/dev/null
}

# Archives
extract() {
    [ -z "$1" ] && echo "Usage: extract <file>" && return 1
    [ ! -f "$1" ] && echo "Error: '$1' not found" && return 1

    case "$1" in
        *.tar.bz2)   tar xjf "$1"     ;;
        *.tar.gz)    tar xzf "$1"     ;;
        *.bz2)       bunzip2 "$1"     ;;
        *.rar)       unrar x "$1"     ;;
        *.gz)        gunzip "$1"      ;;
        *.tar)       tar xf "$1"      ;;
        *.tbz2)      tar xjf "$1"     ;;
        *.tgz)       tar xzf "$1"     ;;
        *.zip)       unzip "$1"       ;;
        *.Z)         uncompress "$1"  ;;
        *.7z)        7z x "$1"        ;;
        *)           echo "Unknown format: '$1'" ;;
    esac
}

compress() {
    [ -z "$1" ] || [ -z "$2" ] && echo "Usage: compress <output> <dir>" && return 1
    tar czf "${1}.tar.gz" "$2"
    echo "Created: ${1}.tar.gz"
}

# Git
gquick() {
    [ -z "$1" ] && echo "Usage: gquick <message>" && return 1
    git add -A && git commit -m "$1" && git push
}

gnew() {
    [ -z "$1" ] && echo "Usage: gnew <branch>" && return 1
    git checkout -b "$1" && git push -u origin "$1"
}

gsearch() {
    [ -z "$1" ] && echo "Usage: gsearch <text>" && return 1
    git log --all --grep="$1"
}

glast() {
    git diff-tree --no-commit-id --name-only -r HEAD
}

# Node.js
create-node-project() {
    [ -z "$1" ] && echo "Usage: create-node-project <name>" && return 1
    
    mkcd "$1"
    npm init -y
    echo "node_modules/\n.env\n*.log\n.DS_Store" > .gitignore
    git init
    echo "# $1\n\n## Installation\n\n\`\`\`bash\nnpm install\n\`\`\`" > README.md
    
    echo "✅ Project '$1' created"
}

npm-clean() {
    npm cache clean --force
    echo "✅ npm cache cleared"
}

# Web Development
serve() {
    local port="${1:-8000}"
    echo "🌐 Serving at http://localhost:$port"
    python3 -m http.server "$port"
}

whoisport() {
    [ -z "$1" ] && echo "Usage: whoisport <port>" && return 1
    lsof -i :"$1"
}

killport() {
    [ -z "$1" ] && echo "Usage: killport <port>" && return 1
    local pid=$(lsof -ti:"$1")
    [ -n "$pid" ] && kill -9 "$pid" && echo "✅ Killed process on port $1" || echo "❌ No process on port $1"
}

# Utilities
dirsize() {
    du -sh * | sort -hr
}

backup() {
    [ -z "$1" ] && echo "Usage: backup <file>" && return 1
    cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
    echo "✅ Backup created"
}

note() {
    [ -z "$1" ] && echo "Usage: note <text>" && return 1
    local notes_file="$HOME/Documents/quick-notes.txt"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$notes_file"
    echo "✅ Note saved to $notes_file"
}

notes() {
    local notes_file="$HOME/Documents/quick-notes.txt"
    [ -f "$notes_file" ] && tail -20 "$notes_file" || echo "No notes found"
}

# System Info
sysinfo() {
    echo "🖥️  System:"
    system_profiler SPSoftwareDataType | grep "System Version"
    echo ""
    echo "💻 Hardware:"
    system_profiler SPHardwareDataType | grep -E "Model Name|Model Identifier|Chip|Memory"
    echo ""
    echo "💾 Disk:"
    df -h / | tail -1
}
