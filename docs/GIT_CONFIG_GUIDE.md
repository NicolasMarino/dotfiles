# Git Configuration Guide

## Work vs Personal Setup

This dotfiles repo supports separate Git configurations for work and personal projects using Git's conditional includes.

### Directory Structure

```
~/Documents/git/
├── work/              # Work projects use .gitconfig.work
│   └── company-repo/
├── personal/          # Personal projects use .gitconfig.personal
│   └── my-project/
└── dotfiles/          # This repo
```

### How It Works

Git automatically loads different configurations based on the directory:

- **Work projects** (`~/Documents/git/work/*`)
  - Uses: `git/.gitconfig.work`
  - Your work email, work SSH keys, etc.

- **Personal projects** (`~/Documents/git/personal/*`)
  - Uses: `git/.gitconfig.personal`
  - Your personal email, personal SSH keys, etc.

### Setup

1. **Create directories**:
   ```bash
   mkdir -p ~/Documents/git/work
   mkdir -p ~/Documents/git/personal
   ```

2. **Update configurations**:
   - Edit `git/.gitconfig.work` with your work info
   - Edit `git/.gitconfig.personal` with your personal info

3. **Clone repos in the right place**:
   ```bash
   # Work projects
   cd ~/Documents/git/work
   git clone git@github.com:company/repo.git
   
   # Personal projects
   cd ~/Documents/git/personal
   git clone git@github.com:yourusername/repo.git
   ```

### Verify Configuration

Check which config is being used:

```bash
cd ~/Documents/git/work/some-repo
git config user.email
# Should show: you@company.com

cd ~/Documents/git/personal/my-project
git config user.email
# Should show: your.personal@gmail.com
```

### Multiple SSH Keys (Optional)

If you use different SSH keys for work and personal:

1. **Generate keys**:
   ```bash
   # Work key
   ssh-keygen -t ed25519 -C "you@company.com" -f ~/.ssh/id_ed25519_work
   
   # Personal key
   ssh-keygen -t ed25519 -C "personal@gmail.com" -f ~/.ssh/id_ed25519_personal
   ```

2. **Add to SSH config** (`~/.ssh/config`):
   ```
   # Work GitHub
   Host github.com-work
       HostName github.com
       User git
       IdentityFile ~/.ssh/id_ed25519_work
   
   # Personal GitHub
   Host github.com
       HostName github.com
       User git
       IdentityFile ~/.ssh/id_ed25519_personal
   ```

3. **Clone work repos with special host**:
   ```bash
   # Instead of: git clone git@github.com:company/repo.git
   git clone git@github.com-work:company/repo.git
   ```

### Override for Specific Repo

If you need to override config for a specific repo:

```bash
cd ~/Documents/git/work/special-project
git config user.email "special@email.com"
# This overrides the work config for this repo only
```
