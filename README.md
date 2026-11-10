# herdr-resume-windows

Bring your **Claude Code** conversations back in their [herdr](https://herdr.dev) terminals after a reboot, on **Windows / PowerShell**.

herdr app restores your spaces, tabs and terminals after a reboot, but by design it does not restart the agents that were running in them: each pane comes back as a fresh shell in the same folder. This add-on closes that gap. After a reboot (or a herdr-core restart), every terminal that had a Claude Code conversation runs `claude --resume <id>` on its own, in the right folder.

> Other resume mods exist for Linux and macOS (bash/zsh, `/proc`). This one is Windows-native: PowerShell 5.1 and 7, no Git Bash, no change to herdr's shell setting.

## Install

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/aramillo/herdr-resume-windows/main/install.ps1 | iex
```

Then restart the Claude sessions you have open (or start new ones) so they register. That's it.

Requirements: herdr app + herdr-core (`hc`), Claude Code (`claude` on PATH).

## How it works

1. **Remember.** A Claude Code `SessionStart` hook writes labels on the herdr terminal it runs in (`$HC_TERMINAL_ID`):
   `claude.resume=<session id>` and `claude.cwd=<folder>`. herdr-core keeps labels on disk, so they survive a reboot.
   `/clear`, `/resume` and forks update the id.
2. **Forget on purpose.** A `SessionEnd` hook removes the labels when *you* quit (`/exit`, Ctrl+C, logout).
   When Claude is killed (reboot, shutdown, crash) the labels stay.
3. **Resume.** When herdr-core recreates a terminal, PowerShell loads your profile, which runs `resume.ps1`. If the terminal has a remembered conversation it goes to its folder, shows
   `herdr-resume: resuming Claude session <id>  (Esc to cancel)` and, after 3 seconds, runs `claude --resume <id>`.

Safety rails:

- Acts only in shells started **directly by herdr-core**. Nested shells, shells spawned by Claude Code (`CLAUDECODE`) and non-console hosts are ignored.
- A conversation that fails to resume twice is forgotten, with a message.
- Press **Esc** during the countdown to skip and forget it for that terminal.
- `HERDR_RESUME=0` in the environment disables resuming.
- The hook never blocks Claude Code: errors are swallowed and logged to `%LOCALAPPDATA%\herdr-resume\hook.log`.

## What it changes

| Where | What |
|---|---|
| `%LOCALAPPDATA%\herdr-resume\` | `hook.ps1`, `resume.ps1`, `hook.log` |
| `~\.claude\settings.json` | one `SessionStart` and one `SessionEnd` hook (backup: `settings.json.bak-herdr-resume`). Your other settings and hooks are kept. |
| PowerShell 5.1 and 7 profiles | one block between `# >>> herdr-resume >>>` and `# <<< herdr-resume <<<` |

If your execution policy blocks profiles, the installer sets `RemoteSigned` for the current user.

## Uninstall

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/aramillo/herdr-resume-windows/main/install.ps1))) -Uninstall
```

or, from a clone, `.\install.ps1 -Uninstall`. It removes the hooks, the profile blocks and the folder.

## Limitations

- Claude Code only (for now).
- Launch flags (`--model`, permission mode, ...) are not restored: the conversation comes back with your defaults.
- Every remembered terminal resumes at once after a reboot. With many agents and little RAM, give it a moment.
- Sessions started before installing are not known until they are restarted.
- Local terminals only (not `hc machine` remotes).
- If herdr ships native agent resume for the app, uninstall this.

---

## En español

Complemento para **herdr app en Windows** que vuelve a abrir tus conversaciones de **Claude Code** en sus pestañas después de reiniciar la PC.

- **Instalar:** `irm https://raw.githubusercontent.com/aramillo/herdr-resume-windows/main/install.ps1 | iex` y luego reinicia las sesiones de Claude que tengas abiertas.
- **Al reiniciar:** cada pestaña que tenía una conversación muestra `resuming Claude session ... (Esc to cancel)` y a los 3 segundos ejecuta `claude --resume <id>` en su carpeta. Pulsa **Esc** para saltarla.
- **Si sales con `/exit` o Ctrl+C**, esa conversación no se retoma.
- **Desinstalar:** `& ([scriptblock]::Create((irm .../install.ps1))) -Uninstall`.

## License

MIT
