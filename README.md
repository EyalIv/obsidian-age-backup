# obsidian-age-backup

Weekly, encrypted backups of an Obsidian vault folder on Windows — encrypted with a
**public key**, so the computer that makes the backups can never open them.

## Why this exists

Sync is not backup. A two-way sync faithfully copies mistakes: delete files on one
device and they disappear everywhere. This project came out of exactly that — a phone
"free up space" cleanup plus a two-way sync tool removed hundreds of vault images.

Most backup tools that run on a schedule keep a password on the machine so they can
encrypt unattended. On a work-managed computer that is a weak spot: the password can
end up in process logs, and stored credentials can be recoverable by domain admins.

Here the machine only holds an [age](https://github.com/FiloSottile/age) **public key**.
It can lock backups but not unlock them. The private key lives only in your password
manager (and ideally on paper).

## How it works

```
Obsidian folder ──7-Zip (fast)──► archive ──age (public key)──► Obsidian-YYYY-MM-DD_HHmm.7z.age
                                                                     │
                                          copied to every destination in config.json
                                          old copies removed by age (default 8 weeks, keep ≥3)
```

- Runs from Windows Task Scheduler at low priority; catches up if the PC was off.
- Verifies the archive before encrypting, checks the encrypted file's format, and checks every copy's size.
- Partial backups (skipped/locked files) are reported as **partial**, never as success.
- A small window shows status, lets you change days and time, run a backup now, and restore.
- No network calls of its own. Your cloud apps (Google Drive, OneDrive, …) upload the files.

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 (built in)
- [7-Zip](https://www.7-zip.org) (64-bit, default install path)
- [age](https://github.com/FiloSottile/age) — e.g. `winget install FiloSottile.age`

## Install

1. Download this repository and keep all files in one folder.
2. Copy `config.example.json` to `config.json` and edit the paths.
   Use forward slashes (`G:/My Drive/...`) or doubled backslashes (`G:\\My Drive\\...`).
3. Open PowerShell in that folder (not as administrator) and run:
   ```
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```
4. Your **private key** is shown once. Save it in your password manager, then paste it
   back to confirm. It is never written to disk. Clear clipboard history afterwards (Win+V).
   Setup then prints your **public key**. It isn't secret: save it next to the private key
   (e.g. in the notes field) so you can compare it with the one the window shows.
   Close the PowerShell window when setup ends — its scroll-back may still hold the private key.
5. The backup window opens. Pick days and time, press **Back up now**, wait for green.
6. **Test a restore** (see below). A backup you haven't restored is not a backup yet.

Want to see the window first without installing anything?

```
powershell -ExecutionPolicy Bypass -File .\backup-ui.ps1 -Preview
```

## Restore

Open **Obsidian Backup** from the Start menu → **Restore from a backup** → choose a
`.age` file → paste your private key. The decrypted `.7z` lands in Downloads and opens
in 7-Zip. Extract what you need, then delete the decrypted file (Shift+Delete).

## What it protects against — and what it doesn't

| Scenario | Protected? |
|---|---|
| Sync tool, plugin, or AI agent deletes or damages vault files | Yes — restore from an earlier backup |
| Someone with access to the PC or the cloud reads your notes from the backup | Yes — needs the private key |
| A process running as you deletes the backup files | Partly — rely on your cloud's trash/version history |
| Changes made since the last backup | No — backups are periodic |
| Losing the private key | No — the backups become unreadable. Keep a second copy |

Other honest notes:

- An **unencrypted** archive exists briefly in `%TEMP%` during each run (the vault itself is on the same disk anyway).
- During restore, the private key is written to `%TEMP%` for a few seconds and then deleted.
- Scripts and the public key live in `%LOCALAPPDATA%\ObsidianBackup`, which any process running as you
  can modify. Malware could swap the public key for its own: backups would still look green, but only
  the attacker could open them. The window shows the start and end of the key in use — compare it with
  the one you saved. A periodic test restore catches this too.
- A destination inside the source folder is refused (each backup would contain the previous ones).
- The scheduled task runs while you're signed in. If you're signed out at the scheduled time, it runs at your next sign-in.
- age provides confidentiality and tamper detection, not signatures.
- Personal project. It has not been audited or widely tested. Use at your own risk.

## Files

| File | Purpose |
|---|---|
| `setup.ps1` | One-time install: key pair, scheduled task, Start-menu shortcut |
| `obsidian-backup.ps1` | The backup itself (run by Task Scheduler) |
| `backup-ui.ps1` | Status / schedule / restore window |
| `restore.ps1` | Decrypt a backup with your private key |
| `config.example.json` | Template for your `config.json` (which is git-ignored) |

## License

MIT — see [LICENSE](LICENSE).
