# Cursor with this devcontainer (GitHub Codespaces)

Use a **GitHub Codespace** for this repo, then attach **Cursor** with **Remote - SSH** using the **GitHub CLI** (`gh codespace ssh`). Authentication is handled by GitHub and `gh`.

The devcontainer includes the [`sshd` feature](https://github.com/devcontainers/features/tree/main/src/sshd) so Codespaces SSH works as documented by GitHub.

**Further reading**

- [Connecting GitHub Codespaces to Cursor](https://medium.com/@NFAblog/connect-github-codespaces-to-cursor-ai-ai-friendly-vs-code-clone-243fa5f79414)
- [Cursor AppImage on Ubuntu 24.04](https://dev.to/melvincarvalho/how-to-fix-cursor-appimage-not-running-on-ubuntu-2404-2o3p)

---

## 1. `sshd` in `devcontainer.json`

```json
"ghcr.io/devcontainers/features/sshd:1": {
    "version": "latest"
}
```

Rebuild the devcontainer after changing features.

---

## 2. GitHub CLI

Install [GitHub CLI](https://cli.github.com/) (`gh`). If `gh codespace ssh` misbehaves, update to a recent `gh` release.

---

## 3. List codespaces and open a shell

```bash
gh codespace list

gh codespace ssh -c YOUR_CODESPACE_NAME --
```

Use your codespace name from the list. Shell user is **`runwhen`**.

---

## 4. SSH config for Cursor

```bash
gh codespace ssh -c YOUR_CODESPACE_NAME --config >> ~/.ssh/codespaces
```

Edit the new **`Host`** block:

- Remove **`IdentityFile …/codespaces.auto`**
- In **`ProxyCommand`**, remove **`-i …/codespaces.auto`**; keep **`gh cs ssh … --stdio --`** (end with `--` only)

Example:

```sshconfig
Host cs.YOUR_CODESPACE_NAME.remote-updates
  User runwhen
  ProxyCommand ... gh cs ssh -c YOUR_CODESPACE_NAME --stdio -- -i ~/.ssh/codespaces.auto
  IdentityFile ~/.ssh/codespaces.auto
  ...
```

After editing, **`ProxyCommand`** should end with **`--stdio --`** and there should be **no** `IdentityFile` for `codespaces.auto`.

Bulk cleanup example:

```bash
sed -i.bak \
  -e 's|IdentityFile .*/\.ssh/codespaces\.auto||g' \
  -e 's|-i .*/\.ssh/codespaces\.auto||g' \
  ~/.ssh/codespaces
```

In Cursor: **Remote-SSH: Connect to Host…** → select that host → **Open Folder** → **`/home/runwhen`**.

---

## 5. Troubleshooting

- Run **`gh codespace ssh -c YOUR_CODESPACE_NAME --`** again if the connection or auth state seems off.
- For **`authorized_keys`** permission errors inside the codespace:

  ```bash
  sudo chmod 755 /home/runwhen
  sudo chmod 700 /home/runwhen/.ssh
  sudo chmod 600 /home/runwhen/.ssh/authorized_keys
  ```

---

## 6. Codespace lifecycle

Stop or delete codespaces in GitHub when you no longer need them.

---

## 7. Local Docker and direct SSH (optional)

The [`sshd` feature](https://github.com/devcontainers/features/tree/main/src/sshd) listens on port **2222** inside the container by default. This repo’s `devcontainer.json` forwards **3000** (logs) only; local workflows typically use **Dev Containers: Reopen in Container**. For SSH from the host, publish port **2222** and follow the feature docs (for example key-based login).

---

## Related

- `.devcontainer/devcontainer.json`
- [Repository README — Getting started](../README.md#getting-started)
- [sshd feature README](https://github.com/devcontainers/features/tree/main/src/sshd)
