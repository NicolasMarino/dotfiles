# Windows Dotfiles Setup

Configuration files for Windows development environment using PowerShell and Chocolatey.

## Quick Start (Windows)

**Run PowerShell as Administrator**:

```powershell
# Clone the repo
git clone https://github.com/YOUR_USERNAME/dotfiles.git C:\Users\YourName\Documents\git\dotfiles
cd C:\Users\YourName\Documents\git\dotfiles\windows

# Allow script execution (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run installation
.\install.ps1
```

## What's Included

- **PowerShell**: Profile with aliases and functions (similar to zsh)
- **Git**: Same git config as macOS (shared)
- **Chocolatey**: Package manager (equivalent to Homebrew)
- **fzf, ripgrep, bat, fd**: Modern CLI tools

## Structure

```
windows/
├── install.ps1                              # Installation script
├── packages.txt                             # Chocolatey packages
└── powershell/
    └── Microsoft.PowerShell_profile.ps1     # PowerShell profile
```

## Common Commands

### PowerShell Aliases

```powershell
# Git
gs          # git status
ga          # git add
gc          # git commit -m
gp          # git push
gl          # git pull

# Navigation
..          # cd ..
ll          # Get-ChildItem (list with details)
```

### Custom Functions

```powershell
mkcd <dir>              # Create directory and cd into it
whoisport <port>        # See what's using a port
killport <port>         # Kill process on port
sysinfo                 # Show system information
reload                  # Reload PowerShell profile
```

## Customization

Edit files in the dotfiles directory:

```powershell
code C:\Users\YourName\Documents\git\dotfiles\windows\powershell\Microsoft.PowerShell_profile.ps1
reload  # Reload profile
```

## Package Management

### Install packages from list:
```powershell
choco install -y $(Get-Content windows\packages.txt)
```

### Update all packages:
```powershell
choco upgrade all -y
```

### List installed:
```powershell
choco list --local-only
```

## WSL Integration (Optional)

If using WSL (Windows Subsystem for Linux), you can share some configs:

```bash
# In WSL
ln -s /mnt/c/Users/YourName/Documents/git/dotfiles/git/.gitconfig ~/.gitconfig
ln -s /mnt/c/Users/YourName/Documents/git/dotfiles/zsh/.zshrc ~/.zshrc
```

## Troubleshooting

### Cannot create symbolic links
Run PowerShell as **Administrator**.

### Execution Policy Error
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Check symbolic links
```powershell
Get-Item $PROFILE | Select-Object Target
```

## Notes

- **Git config is shared** between macOS and Windows (same files in `git/`)
- **Shell configs are separate** (zsh for macOS, PowerShell for Windows)
- Use **Windows Terminal** for better experience with PowerShell
