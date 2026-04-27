# Dotfiles Roadmap

## Current Status

✅ Basic shell configuration (zsh, Oh My Zsh)
✅ Git configuration with work/personal separation
✅ Homebrew package management
✅ Node.js version management (nvm)
✅ Modern CLI tools (fzf, bat, ripgrep, eza)
✅ macOS system preferences automation
✅ Windows support (WIP)

---

## Phase 1: Editor Configurations

### VS Code

- [x] Add `vscode/settings.json` with:
  - Font configuration (Fira Code with ligatures)
  - Theme preferences
  - Extension recommendations
  - Keybindings
  - Language-specific settings
- [x] Add `vscode/extensions.txt` with essential extensions
- [x] Add symlink script for VS Code configs

### Neovim

- [ ] Add `init.vim` or `init.lua` configuration
- [ ] Plugin manager setup (vim-plug or lazy.nvim)
- [ ] Essential plugins (Telescope, Treesitter, LSP)
- [ ] Color scheme configuration

---

## Phase 2: Development Workflow

### Standards & Quality

- [x] Global `.editorconfig` (ensure it covers all file types)
- [x] Global `.prettierrc` for consistent formatting

### Git Enhancements

- [x] Git hooks (pre-commit, commit-msg)
- [ ] Git commit message templates
- [x] `delta` for syntax-highlighted git diffs
- [ ] `lazygit` TUI configuration

### Infrastructure & Cloud

- [ ] Docker global configuration (`config.json`)
- [ ] AWS CLI aliases and config helpers
- [ ] Python `pyenv` and `poetry` global settings

---

## Phase 3: Security & Privacy

- [x] SSH config with multiple keys/hosts management
- [x] GPG key configuration for commit signing
- [x] `gitleaks` pre-commit hook to prevent secret leaks

---

## Phase 4: Automation

### Automation & CI/CD

- [ ] GitHub Actions for linting shell scripts (`shellcheck`)
- [ ] Automated testing of installation scripts
- [ ] Brewfile validation workflow
- [ ] Automated backup script with rotation
