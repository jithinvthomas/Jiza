# Pocket Terminal: Claude Code and Codex

Jiza's Terminal tab connects to a **private HTTPS terminal gateway** that establishes SSH sessions on your Windows laptop or Oracle Cloud Linux server. The terminal does not run Claude Code or Codex inside iOS.

## Requirements
1. Install and authenticate Claude Code and/or Codex CLI on the remote host using their official installation instructions.
2. Enable SSH on the remote host; use key-based authentication and verify host keys.
3. Run a private, authenticated HTTPS/WSS terminal gateway that supports interactive PTY sessions. Protect it with an access layer such as Tailscale Serve; never publish an unauthenticated command execution endpoint.
4. In Jiza > Terminal > Settings, enter your private gateway HTTPS URL.
5. Select the remote host in the gateway interface, then type `claude` or `codex`.

## Persistent sessions (Linux)
Install tmux on Oracle Cloud:
```sh
sudo apt-get update && sudo apt-get install -y tmux
tmux new -As coding
```
Inside tmux run `claude` or `codex`. Detach with Ctrl-B then D; reconnect with `tmux attach -t coding`.

## Windows
Use PowerShell over SSH. If available, use WSL with tmux for persistent Linux coding sessions. Do not assume a closed SSH connection will preserve the process without tmux or another session manager.

## Security
Never commit passwords, API keys, SSH private keys or access tokens. The Jiza terminal view deliberately requires HTTPS. This repository's new iOS view is a client shell; the remote gateway and its authentication must be deployed and tested separately.
