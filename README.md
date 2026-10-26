# Quark Motrix Accelerator

A practical, scriptable tuning recipe for **large multi-part downloads from Quark Pan (夸克网盘)** through **LinkSwift + Motrix/aria2**.

It is not a magic speed hack. It is a repeatable way to:

1. Measure whether the bottleneck is **per-connection throttling**;
2. Raise aria2's `split` / connections per task;
3. Choose a sane number of concurrent tasks;
4. Monitor progress and errors over aria2 JSON-RPC;
5. Verify the multi-volume archive with 7-Zip before extracting.

> **Measured in one real run (2026-10-26):** 33 RAR volumes, 31.26 GB, throughput went from **~7.8 MB/s to ~44 MB/s** (peak 49 MB/s, about **5.6×**), with `7z t` reporting `Everything is Ok`.

---

## Why it works

In the measured run, Quark's direct links behaved like they had a **per-TCP-connection throttle of roughly 50 KB/s**.

aria2's `split` controls how many pieces (and therefore connections) one download uses:

| Connections per task | Approx. speed per task |
|---:|---:|
| 16 (default) | 0.8 MB/s |
| 32 | 1.6 MB/s |
| 64 | 3.2 MB/s |

With 16 active tasks at 64 connections each, that is roughly 1000 connections and about 44 MB/s aggregate.

This is an empirical observation, not a claim about Quark's internal implementation. Results vary by account, ISP, region, CDN node, time of day, and server-side policy.

---

## Requirements

- Windows 10/11
- [Motrix](https://motrix.app/) 2.x (tested with `2.0.0-beta.47`)
- aria2 engine bundled with Motrix (tested with `1.37.0-motrix.17`)
- Edge/Chrome + Tampermonkey + [LinkSwift](https://github.com/hmjz100/LinkSwift) (tested with `1.1.3`)
- [7-Zip](https://www.7-zip.org/) (tested with `24.08`)
- PowerShell 5.1+

---

## LinkSwift integration

This project is meant to be used **together with LinkSwift**:

- **LinkSwift** gets the Quark direct links, handles the required Cookie/User-Agent/Referer headers, and pushes the tasks to Motrix/aria2.
- **This skill** tunes the aria2 tasks LinkSwift created: `split`, connections per task, concurrency, monitoring, verification, and extraction.

Setup:

1. Install Tampermonkey + LinkSwift in Edge/Chrome.
2. In LinkSwift's Aria2/RPC settings, set:
   - RPC URL: `http://127.0.0.1:16800/jsonrpc`
   - RPC secret: the secret shown in Motrix settings
3. Open `pan.quark.cn`, select the files/folder, click **下载助手**, and choose **Aria2 推送**.
4. Confirm the tasks appear in Motrix.
5. Run `.\scripts\tune-aria2.ps1 -Split 64 -MaxConcurrentDownloads 16`.

If LinkSwift's connection test fails, verify that Motrix is running, the RPC port/secret match, and localhost RPC is not blocked by Windows Firewall. If tasks appear but stall, refresh the Quark direct link and do not switch proxies mid-download.

This skill does **not** replace LinkSwift, and it does not create Quark direct links by itself. Browser downloads are not suitable for this tuning because they do not expose aria2's per-task `split` setting.

---

## Quick start

### 1. Clone / copy this folder

```powershell
git clone https://github.com/Kevin123666/quark-motrix-accelerator.git
cd quark-motrix-accelerator
```

### 2. Set your Motrix RPC secret

The secret is in Motrix: **Settings → Advanced / RPC**. Do **not** commit it.

```powershell
$env:MOTRIX_RPC_SECRET = '<your-rpc-secret>'
```

Or pass `-Secret '<your-rpc-secret>'` to each script.

### 3. Tune current tasks

```powershell
# Apply to existing active/waiting tasks + global defaults
.\scripts\tune-aria2.ps1 -Split 64 -MaxConcurrentDownloads 16
```

This script:

- pauses all tasks;
- changes `split=64`, `max-connection-per-server=64`, `min-split-size=4M` on every task;
- sets global defaults and `max-concurrent-downloads=16`;
- unpauses tasks, restoring any task that was paused before.

Use `-WhatIf` to preview without changing anything:

```powershell
.\scripts\tune-aria2.ps1 -Split 64 -MaxConcurrentDownloads 16 -WhatIf
```

### 4. Monitor

```powershell
# Continuous, until active + waiting reaches zero
.\scripts\monitor-aria2.ps1 -TotalTasks 33

# One snapshot
.\scripts\monitor-aria2.ps1 -Once -TotalTasks 33
```

### 5. Verify and extract

```powershell
# Verify only (recommended first)
.\scripts\verify-and-extract.ps1 `
  -ArchiveDir 'E:\download\Your.Game.CHS.Green' `
  -VerifyOnly

# Verify + extract
.\scripts\verify-and-extract.ps1 `
  -ArchiveDir 'E:\download\Your.Game.CHS.Green' `
  -Destination 'E:\Games\Your.Game.CHS.Green' `
  -Extract
```

The script finds `*.part01.rar` / `*.part001.rar` (or falls back to the first `.rar`), runs `7z t`, and only extracts if the test passes.

---

## Use as an OpenCode skill

This folder is a valid OpenCode V2 skill: the entry point is `SKILL.md`, and its ID is the directory name `quark-motrix-accelerator`.

Global install on Windows:

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode\skills" | Out-Null
git clone https://github.com/Kevin123666/quark-motrix-accelerator.git `
  "$HOME\.config\opencode\skills\quark-motrix-accelerator"
```

Project-local install:

```powershell
New-Item -ItemType Directory -Force ".opencode\skills" | Out-Null
git clone https://github.com/Kevin123666/quark-motrix-accelerator.git `
  ".opencode\skills\quark-motrix-accelerator"
```

OpenCode discovers global skills under `~/.config/opencode/skills` and project skills under `.opencode/skills`. Load it explicitly with `@quark-motrix-accelerator` or the `skill` tool.

---

## Motrix persistence caveat

Motrix 2.0 persists `maxConcurrentDownloads` and `maxConnectionPerServer`, but in the tested build it **resets `split` to 16 on restart**.

Options:

1. Re-run the tune script after each Motrix start:
   ```powershell
   .\scripts\tune-aria2.ps1 -GlobalOnly -WaitForRpc
   ```
2. Put `scripts/apply-on-startup.ps1` into your startup folder or Task Scheduler.

The global runtime values are visible through:

```powershell
.\scripts\monitor-aria2.ps1 -Once -ShowOptions
```

---

## Key parameters

| Parameter | Recommended | Notes |
|---|---:|---|
| `split` | 64 | Connections/pieces per task; main lever |
| `max-connection-per-server` | 64 | Must be ≥ `split` |
| `min-split-size` | 4 MiB | 1 GiB / 64 = 16 MiB, so 64 pieces are possible |
| `max-concurrent-downloads` | 16 | Tested sweet spot; more gave little gain |
| `file-allocation` | none | Avoids preallocation stalls |
| `disk-cache` | 32 MiB | Motrix default is fine |

**Do not jump straight to 128/256 connections.** Increase in steps, watch for 403/429, and stop when aggregate speed stops rising.

---

## Rollback

To return to Motrix-like defaults:

```powershell
.\scripts\tune-aria2.ps1 -Split 16 -MaxConcurrentDownloads 10
```

This only changes aria2 runtime values. To reset per-task options, run it without `-GlobalOnly`; it will pause, rewrite, and unpause the current tasks.

---

## Decision guide

| Observation | Likely cause | Action |
|---|---|---|
| Each task has 16 connections and ~0.8 MB/s | Per-connection throttle | Raise `split` to 32 → 64 |
| Per-task speed rises with connections | Per-connection limit | Add more connections or tasks |
| Aggregate speed stops rising when adding tasks | Account/IP/ISP cap | Stop; keep the last stable value |
| 403 / 429 / many retries | Too many connections or expired links | Lower split/concurrency; refresh direct links |
| Some tasks finish but `tellStopped` is empty | Motrix removes completed tasks | Check files + `7z t`, not `tellStopped` |

---

## Safety and legal

- Use this only for **your own account** and **content you are allowed to download**.
- Do not bypass paid/member limits, DRM, or access controls.
- Do not publish real RPC secrets, cookies, signed direct links, or account data.
- Respect Quark's terms of service and your ISP's policies.
- Excessive connections can trigger account risk controls or router/NAT exhaustion.
- The authors are not affiliated with Quark, Motrix, LinkSwift, or 7-Zip.

---

## Repository layout

```text
quark-motrix-accelerator/
├─ SKILL.md
├─ README.md
├─ LICENSE
├─ .gitignore
├─ scripts/
│  ├─ tune-aria2.ps1
│  ├─ monitor-aria2.ps1
│  ├─ verify-and-extract.ps1
│  └─ apply-on-startup.ps1
└─ references/
   └─ measurements.md
```

---

## Publish to GitHub

```powershell
cd C:\Users\R9000P\Desktop\quark-motrix-accelerator
git init
git add .
git commit -m "Initial commit: Quark Motrix accelerator skill"
git branch -M main
git remote add origin https://github.com/<your-name>/quark-motrix-accelerator.git
git push -u origin main
```

Before pushing, search the folder for secrets:

```powershell
Select-String -Path .\* -Pattern 'rpcSecret|token:|Cookie|Authorization' -Recurse
```

Do not commit real RPC secrets, cookies, signed URLs, or account screenshots.

---

## Acknowledgements

- [LinkSwift](https://github.com/hmjz100/LinkSwift) for Quark direct-link extraction.
- [Motrix](https://motrix.app/) for the cross-platform aria2 frontend.
- [aria2](https://aria2.github.io/) for the JSON-RPC engine.
- [7-Zip](https://www.7-zip.org/) for multi-volume RAR verification/extraction.

---

## License

MIT. See [LICENSE](LICENSE).
