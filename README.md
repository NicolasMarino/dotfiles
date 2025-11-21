# Dotfiles

My personal dev environment setup for macOS (M4) and Windows (WIP).

## Installation

```bash
cd ~/Documents/git/dotfiles
./install.sh
```

This will install Homebrew, packages from the Brewfile, Oh My Zsh with plugins, and create symlinks to your home directory. It can also apply some macOS defaults if you want.

## What's in here

**Shell (zsh)**
- Oh My Zsh with autosuggestions and syntax highlighting
- Custom aliases and functions
- fzf integration for fuzzy search (CTRL-T, CTRL-R, ALT-C)

**Git**
- Aliases and configuration
- Conditional configs for work/personal projects
- Global gitignore

**Homebrew**
- Brewfile with common dev tools (git, node, docker, etc.)
- Modern CLI tools (bat, ripgrep, fd, exa)

#### Installing a new tool
```bash
vim brew/Brewfile  # Add the package
brew bundle --file=brew/Brewfile
git commit -am "add new package"
```

**Node.js**
- nvm for version management
- Auto-switches versions based on `.nvmrc`

**Windows (WIP)**
- PowerShell profile with similar aliases
- Chocolatey package manager
- Shares git configs with macOS

## How it works


Everything uses symlinks, so you edit files in this repo and changes apply immediately. No need to copy files around.

```bash
~/.zshrc -> ~/Documents/git/dotfiles/zsh/.zshrc
~/.gitconfig -> ~/Documents/git/dotfiles/git/.gitconfig
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
```

**Functions:**
```bash
mkcd mydir          # make directory and cd into it
extract file.zip    # extract any archive
whoisport 3000      # see what's running on port 3000
killport 3000       # kill process on that port
```

**fzf shortcuts:**
- `CTRL-T` - fuzzy find files
- `CTRL-R` - search command history
- `ALT-C` - fuzzy find directories and cd

## Git work/personal setup

The `.gitconfig` uses conditional includes to automatically use different emails/SSH keys based on where you clone repos:

```bash
~/Documents/git/work/     # uses .gitconfig.work
~/Documents/git/personal/ # uses .gitconfig.personal
```

Copy the sample files and edit them:
```bash
cp git/.gitconfig.work.sample git/.gitconfig.work
cp git/.gitconfig.personal.sample git/.gitconfig.personal
vim git/.gitconfig.work
vim git/.gitconfig.personal
```

See [GIT_CONFIG_GUIDE.md](GIT_CONFIG_GUIDE.md) for more details.

## Customization

Just edit files in this repo:
```bash
vim zsh/aliases.zsh    # add your own aliases
vim brew/Brewfile      # add packages
git commit -am "update"
```

Don't forget to update your name/email in `git/.gitconfig`.

## Backups

Your original configs get backed up to `~/.dotfiles_backup/` before anything is changed.

## Windows

There's a PowerShell version in the `windows/` folder. Still a work in progress but has the basics. See [windows/README.md](windows/README.md).

## License

MIT
