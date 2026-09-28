# Dotfiles

My personal dev environment setup for macOS (M4) and Windows (WIP).

## Prerequisites (Fresh Mac Setup)

If you are on a brand new Mac, you need the Apple Command Line Tools to get `git` before you can clone this repository. Open your terminal and run:

```bash
xcode-select --install
```

## Installation

Once you have git installed, clone the repository and run the setup script:

```bash
git clone https://github.com/nicolasmarino/dotfiles.git ~/Documents/git/personal/dotfiles
cd ~/Documents/git/personal/dotfiles
./install.sh
```

> **Note:** The `install.sh` script is completely **idempotent**. This means it is safe to run it multiple times. You can run it again in the future to sync changes or install newly added packages without breaking your current setup.

This will install Homebrew, packages from the Brewfile, Oh My Zsh with plugins, and create symlinks to your home directory. It can also apply some macOS defaults if you want.

## What's in here

**Shell (zsh)**
- Oh My Zsh with autosuggestions and syntax highlighting
- Custom aliases and functions
- fzf integration for fuzzy search (CTRL-T, CTRL-R, ALT-C)
- direnv for per-directory environment variables
- zoxide for smarter directory navigation
- Modern CLI tools (bat, ripgrep, fd, eza, delta)

**Git**
- Aliases and configuration
- Conditional configs for work/personal projects
- Global gitignore
- delta for syntax-highlighted diffs

**Editor (VS Code)**
- Font configuration (Fira Code with ligatures)
- Recommended extensions via `extensions.txt`
- Pre-configured `settings.json` symlinked automatically

**Homebrew**
- Brewfile with common dev tools (git, docker, etc.)

**Claude Code**
- Global `PreToolUse` guard hooks (secret scanning, destructive-command
  blocking) merged into `~/.claude/settings.json` — see [claude/README.md](claude/README.md)

#### Installing a new tool
```bash
vim brew/Brewfile  # Add the package
brew bundle --file=brew/Brewfile
git commit -am "add new package"
```

**Node.js**
- fnm for version management
- Auto-switches versions based on `.nvmrc` and `.node-version`

**Windows (WIP)**
- PowerShell profile with similar aliases
- Chocolatey package manager
- Shares git configs with macOS

## How it works

Everything uses symlinks, so you edit files in this repo and changes apply immediately. No need to copy files around.

```bash
~/.zshrc -> ~/Documents/git/personal/dotfiles/zsh/.zshrc
~/.zprofile -> ~/Documents/git/personal/dotfiles/zsh/.zprofile
~/.gitconfig -> ~/Documents/git/personal/dotfiles/git/.gitconfig
~/Library/Application Support/Code/User/settings.json -> ~/Documents/git/personal/dotfiles/vscode/settings.json
~/.config/nvim -> ~/Documents/git/personal/dotfiles/nvim
```

## Useful stuff

**Git aliases:**
```bash
gs    # git status
ga    # git add
gc    # git commit
gp    # git push
gl    # git pull
glog  # pretty git log
gcof  # checkout branch with fzf picker
```

**Functions:**
```bash
mkcd mydir          # make directory and cd into it
extract file.zip    # extract any archive
whoisport 3000      # see what's running on port 3000
killport 3000       # kill process on that port
```

**Reviewing a diff in Neovim** (LazyVim, `nvim/`):
```
<leader>gv    diffview: file panel + side-by-side diff of the working tree
<leader>gV    same, but the whole branch against origin
<leader>gr    repo commit history
<leader>gq    close it
<leader>gs    LazyVim picker: list of changed files
<leader>gd    LazyVim picker: every hunk in the repo
]h  [h        jump between hunks in the current file (gitsigns)
```

**fzf shortcuts:**
- `CTRL-T` - fuzzy find files
- `CTRL-R` - search command history
- `ALT-C` - fuzzy find directories and cd

## Git work/personal setup

The `.gitconfig` uses conditional includes to automatically use different emails/SSH keys based on where you clone repos:

```bash
~/Documents/git/          # uses .gitconfig.work
~/Documents/git/personal/ # uses .gitconfig.personal (overrides the line above)
```

Order matters: the broader `~/Documents/git/` include comes first, and the
narrower `personal/` one overrides it. A new scope must be appended after the
broader one to win.

Copy the sample files and edit them:
```bash
cp git/.gitconfig.work.sample git/.gitconfig.work
cp git/.gitconfig.personal.sample git/.gitconfig.personal
vim git/.gitconfig.work
vim git/.gitconfig.personal
```

See [docs/GIT_CONFIG_GUIDE.md](docs/GIT_CONFIG_GUIDE.md) for more details.

## Customization

Just edit files in this repo:
```bash
vim zsh/aliases.zsh    # add your own aliases
vim brew/Brewfile      # add packages
git commit -am "update"
```

Your name, email and signing key live in `git/.gitconfig.personal` and
`git/.gitconfig.work` — both gitignored. The tracked `git/.gitconfig` holds
only shared settings.

For anything that is specific to one machine rather than to an identity
(host credential helpers, a corporate proxy), use `git/.gitconfig.local`:

```bash
cp git/.gitconfig.local.sample git/.gitconfig.local
```

It is gitignored and loaded last, so it overrides everything above it.

## Backups & Rollback

Your original configs get backed up to `~/.dotfiles_backup/` before anything is changed during installation.

If you ever need to restore your old setup, you can copy everything back from the backup folder:
Each backup is timestamped, and nested paths are flattened with `_`
(`Library_Application_Support_Code_User_settings.json.20260820-193000`), so
restore the specific file you want rather than copying the folder wholesale:

```bash
eza -la ~/.dotfiles_backup/
cp ~/.dotfiles_backup/.zshrc.20260820-193000 ~/.zshrc
```

## Windows

There's a PowerShell version in the `windows/` folder. Still a work in progress but has the basics. See [windows/README.md](windows/README.md).

## License

MIT
