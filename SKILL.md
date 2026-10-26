---
name: Quark Motrix Accelerator
description: Diagnose and improve large multi-part downloads from Quark Pan (夸克网盘) through LinkSwift + Motrix/aria2. Use when every task sits near 0.8 MB/s with ~16 connections, when aggregate throughput is far below the link speed, or when the user asks to tune aria2 split/concurrency, monitor RPC progress, verify multi-volume RAR files, or extract them safely.
license: MIT
---

# Quark Motrix Accelerator

A skill for turning a slow Quark → LinkSwift → Motrix/aria2 download into a fast, measurable one **without bypassing account or paywall limits**.

## When to use

Use this skill when:

- The user downloads many files from Quark Pan via LinkSwift and Motrix/aria2.
- Each active task has ~16 connections and ~0.8 MB/s, suggesting a per-connection throttle.
- Aggregate speed is much lower than the LAN/WAN link speed.
- The user wants a repeatable PowerShell/RPC workflow for tuning, monitoring, verifying, and extracting.

Do **not** use it to:

- Bypass paid membership, DRM, access controls, or quotas.
- Steal cookies, share accounts, or redistribute copyrighted content.
- Attack a service with unbounded connection counts.

## Preconditions

1. Motrix is running with aria2 JSON-RPC enabled.
2. You know the RPC URL (default `http://127.0.0.1:16800/jsonrpc`) and secret.
3. LinkSwift has already pushed the tasks into Motrix.
4. All parts of a multi-volume archive are in the same folder.
5. 7-Zip is installed; this repo assumes `E:\7-Zip\7z.exe` unless overridden.

**Never echo or commit the RPC secret.** Prefer:

```powershell
$env:MOTRIX_RPC_SECRET = '<secret>'
```

## Workflow

### 1. Measure before changing anything

```powershell
.\scripts\monitor-aria2.ps1 -Once -TotalTasks <N> -ShowOptions
```

Look at:

- `active`, `waiting`;
- per-task `connections`;
- per-task `downloadSpeed`;
- aggregate `downloadSpeed`;
- `errors`.

Decision rule:

```text
per-task speed / connections ≈ 50 KB/s  -> per-connection throttle -> raise split
aggregate stops rising when adding tasks -> account/IP/ISP cap      -> stop
403/429/retries increase                 -> too aggressive          -> lower split/concurrency
```

### 2. Apply the tuning

```powershell
.\scripts\tune-aria2.ps1 -Split 64 -MaxConcurrentDownloads 16
```

This pauses active tasks, changes per-task options, sets global defaults, then unpauses. Tasks that were paused before are restored to paused.

Preview first if the user is cautious:

```powershell
.\scripts\tune-aria2.ps1 -Split 64 -MaxConcurrentDownloads 16 -WhatIf
```

### 3. Monitor until done

```powershell
.\scripts\monitor-aria2.ps1 -TotalTasks <N> -IntervalSec 5
```

Stop when `active=0` and `waiting=0`. Do **not** use `aria2.tellStopped` as the completion source in Motrix 2.0: Motrix may remove completed tasks from aria2's stopped list.

### 4. Verify the archive

```powershell
.\scripts\verify-and-extract.ps1 `
  -ArchiveDir 'E:\download\Your.Package' `
  -VerifyOnly
```

Require `7z t` to return exit code 0 and print `Everything is Ok`.

### 5. Extract only after verification

```powershell
.\scripts\verify-and-extract.ps1 `
  -ArchiveDir 'E:\download\Your.Package' `
  -Destination 'E:\Games\Your.Package' `
  -Extract
```

### 6. Persist across Motrix restarts

Motrix 2.0 may reset `split` to 16 on startup. Re-apply global options after each start:

```powershell
.\scripts\tune-aria2.ps1 -GlobalOnly -WaitForRpc
```

Or install `scripts/apply-on-startup.ps1` as a login/startup task.

## Recommended starting values

| Parameter | Start | Notes |
|---|---:|---|
| `split` | 64 | Raise from 16 in steps: 32 → 64 |
| `max-connection-per-server` | 64 | Must be ≥ `split` |
| `min-split-size` | 4 MiB | Ensure `fileSize / split > min-split-size` |
| `max-concurrent-downloads` | 16 | Tested sweet spot |
| `file-allocation` | none | Avoid preallocation stalls |
| `disk-cache` | 32 MiB | Default is fine |

Do not exceed 64 without measuring. Stop increasing when aggregate speed no longer rises.

## Rollback

To return to the tested Motrix-like defaults:

```powershell
.\scripts\tune-aria2.ps1 -Split 16 -MaxConcurrentDownloads 10
```

Run without `-GlobalOnly` to rewrite the current tasks as well.

## Pitfalls

- **File size is not progress.** aria2 may extend a sparse file near its full logical size before all pieces arrive. Use `completedLength / totalLength`.
- **Pausing changes queue order.** A waiting task may take the freed slot; an unpaused task may go to the back. Use `aria2.changePosition(token, gid, 0, 'POS_SET')` if order matters.
- **Motrix resets split.** Re-apply via RPC or the startup script.
- **Last volume may be small.** A 33-volume archive can have a 14 MB final part. Verify with 7-Zip; do not assume truncation.
- **Do not switch proxies mid-download.** Quark links are often time-limited and IP-bound; a proxy change can cause 403.
- **Public repos must be sanitized.** Remove secrets, cookies, signed URLs, account names, and screenshots.

## Files in this skill

| File | Purpose |
|---|---|
| `scripts/tune-aria2.ps1` | Pause/apply/unpause split and concurrency |
| `scripts/monitor-aria2.ps1` | RPC progress, ETA, errors, options |
| `scripts/verify-and-extract.ps1` | 7-Zip test + optional extraction |
| `scripts/apply-on-startup.ps1` | Re-apply global tuning after Motrix starts |
| `references/measurements.md` | Real-world measurements from the 2026-10-26 run |

## Safety

Use only with your own account and lawful content. This skill tunes connection counts; it does not bypass quotas, membership limits, DRM, or access controls. Excessive connections can trigger risk controls or NAT exhaustion. If errors appear, lower `split` and `max-concurrent-downloads`.
