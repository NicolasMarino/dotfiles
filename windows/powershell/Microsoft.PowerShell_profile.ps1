# PowerShell Profile Configuration
# Location: $PROFILE (usually ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1)

# Environment Variables
$env:EDITOR = "code"

# Aliases
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name g -Value git
Set-Alias -Name vim -Value code

# Git Aliases
function gs { git status }
function ga { git add $args }
function gc { git commit -m $args }
function gp { git push }
function gl { git pull }
function gco { git checkout $args }

# Navigation
function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }

# Create directory and cd
function mkcd($path) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Location $path
}

# List with colors
function ll { Get-ChildItem -Force | Format-Table -AutoSize }
function la { Get-ChildItem -Force }

# Find files
function fnd($pattern) {
    Get-ChildItem -Recurse -Filter "*$pattern*" -ErrorAction SilentlyContinue
}

# Network
function localip { 
    Get-NetIPAddress | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object IPAddress
}

# Process
function whoisport($port) {
    Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object OwningProcess, State | ForEach-Object {
        $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Port = $port
            Process = $process.Name
            PID = $_.OwningProcess
            State = $_.State
        }
    }
}

# Kill process on port
function killport($port) {
    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        Stop-Process -Id $conn.OwningProcess -Force
        Write-Host "Killed process on port $port" -ForegroundColor Green
    }
}

# Show system info
function sysinfo {
    Write-Host "System Information:" -ForegroundColor Cyan
    Get-ComputerInfo | Select-Object CsName, WindowsVersion, OsArchitecture, CsProcessors
}

# Reload profile
function reload {
    . $PROFILE
    Write-Host "Profile reloaded" -ForegroundColor Green
}

# Welcome message
Write-Host "PowerShell Profile Loaded" -ForegroundColor Green
Write-Host "Node version: $(node --version 2>$null)" -ForegroundColor Gray
