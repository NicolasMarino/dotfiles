# Enterprise Git Security (SSH & GPG)

This guide documents the mandatory cryptographic configurations across this dotfiles repository to guarantee verifiable commits and zero-friction remote authentication.

## 1. SSH Authentication & Agent Forwarding

Bypass HTTPS password deprecations by leveraging asymmetric SSH cryptography.

### A. ED25519 Key Generation
Generate a modern, highly resilient elliptic curve key targeting your GitHub email:
```bash
ssh-keygen -t ed25519 -C "your_github_email@example.com"
```
*Note parameter `-t ed25519`: Do not fallback to legacy RSA variants unless forced by legacy infrastructure.*

### B. Agent Configuration & Keychain Persistence
macOS users should bind the key to the Apple Keychain to prevent repetitive passphrase queries.
Ensure your `~/.ssh/config` enforces this explicitly:

```text
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
```

Add the generated key to the agent matrix:
```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

### C. Public Key Deployment
Export your public key component via `pbcopy < ~/.ssh/id_ed25519.pub` and register it within GitHub under **Settings > SSH and GPG keys**. Verify connectivity with `ssh -T git@github.com`.

---

## 2. Cryptographic Commit Verification (GPG)

Deploying GPG keys enforces strict identity validation for every commit, unlocking the "Verified" badge on platforms like GitHub and preventing commit spoofing.

### A. Key Generation
Execute the full key generation wizard:
```bash
gpg --full-generate-key
```
1. Select `9` (ECC and ECC) for Elliptic Curve.
2. Select `1` (Curve 25519).
3. Set expiration (e.g., `1y`).
4. **Critical**: The associated email must strictly match the address registered under GitHub settings and your local `.gitconfig`.

### B. Extracting the Signing Key ID
Retrieve your generated key ID (the alphanumeric string succeeding `ed25519/`):
```bash
gpg --list-secret-keys --keyid-format=long
```
*(Example: `sec ed25519/3AA5C34371567BD2` -> `3AA5C34371567BD2`)*

### C. Deploying the Public Block to GitHub
Export the public cryptographic block to your clipboard:
```bash
gpg --armor --export YOUR_LONG_KEY_ID | pbcopy
```
Paste this block directly into GitHub's **New GPG key** interface.

### D. Enforcing Global Signing
Bind the local repository configuration to default to this key and strictly enforce commit signing across all operations:

```bash
git config --global user.signingkey YOUR_LONG_KEY_ID
git config --global commit.gpgsign true
```

Once configured, any native git execution or UI client will seamlessly inherit `commit.gpgsign = true` and implicitly prompt your locally cached GPG passphrase during the commit hook lifecycle.
