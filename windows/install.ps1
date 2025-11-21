# Windows Installation Script
# Run in PowerShell as Administrator

Write-Host "Installing Dotfiles for Windows..." -ForegroundColor Cyan

# Get the dotfiles directory
$DOTFILES_DIR = Split-Path -Parent $PSScriptRoot

# Backup existing configs
$BACKUP_DIR = "$HOME\.dotfiles_backup"
if (!(Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
    Write-Host "Created backup directory: $BACKUP_DIR" -ForegroundColor Yellow
}

# PowerShell Profile
$PROFILE_PATH = $PROFILE
$PROFILE_DIR = Split-Path -Parent $PROFILE_PATH

if (!(Test-Path $PROFILE_DIR)) {
    New-Item -ItemType Directory -Path $PROFILE_DIR -Force | Out-Null
}

if (Test-Path $PROFILE_PATH) {
    Copy-Item $PROFILE_PATH "$BACKUP_DIR\Microsoft.PowerShell_profile.ps1.backup" -Force
    Write-Host "Backed up existing PowerShell profile" -ForegroundColor Yellow
}

# Create symlink for PowerShell profile
$source = "$DOTFILES_DIR\windows\powershell\Microsoft.PowerShell_profile.ps1"
New-Item -ItemType SymbolicLink -Path $PROFILE_PATH -Target $source -Force | Out-Null
Write-Host "Created symlink: $PROFILE_PATH -> $source" -ForegroundColor Green

# Git Config (Windows uses the same .gitconfig)
if (Test-Path "$HOME\.gitconfig") {
    Copy-Item "$HOME\.gitconfig" "$BACKUP_DIR\.gitconfig.backup" -Force
    Write-Host "Backed up existing .gitconfig" -ForegroundColor Yellow
}

New-Item -ItemType SymbolicLink -Path "$HOME\.gitconfig" -Target "$DOTFILES_DIR\git\.gitconfig" -Force | Out-Null
Write-Host "Created symlink: ~/.gitconfig -> dotfiles/git/.gitconfig" -ForegroundColor Green

New-Item -ItemType SymbolicLink -Path "$HOME\.gitignore_global" -Target "$DOTFILES_DIR\git\.gitignore_global" -Force | Out-Null
Write-Host "Created symlink: ~/.gitignore_global -> dotfiles/git/.gitignore_global" -ForegroundColor Green

# Install Chocolatey (Windows package manager)
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..." -ForegroundColor Cyan
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Write-Host "Chocolatey installed" -ForegroundColor Green
} else {
    Write-Host "Chocolatey already installed" -ForegroundColor Green
}

# Install essential packages
Write-Host "Installing essential packages..." -ForegroundColor Cyan
choco install -y git
choco install -y nodejs
choco install -y vscode
choco install -y fzf
choco install -y ripgrep
choco install -y fd
choco install -y bat

Write-Host ""
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "Restart PowerShell to apply changes" -ForegroundColor Yellow
Write-Host "Backups stored in: $BACKUP_DIR" -ForegroundColor Gray
