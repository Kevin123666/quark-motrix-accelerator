# Measurements

All values below are from one real run on **2026-10-26**. They are not guarantees.

## Environment

| Item | Value |
|---|---|
| OS | Windows 10/11 |
| Browser | Microsoft Edge + Tampermonkey |
| LinkSwift | 1.1.3 |
| Motrix | 2.0.0-beta.47 |
| aria2 | 1.37.0-motrix.17 |
| 7-Zip | 24.08 |
| Network | 1 Gbps Ethernet; direct connection, no proxy |
| Save directory | `E:\download` |

## Archive

- Name: `3DMGAME_Call_of_Duty_HQ.CHS.Green`
- 33 RAR5 volumes
- Compressed size: `33,569,168,309` bytes ≈ **31.26 GiB**
- Uncompressed size: `34,754,452,770` bytes ≈ **32.37 GiB**
- Files: 2937, folders: 5
- Last volume: 14.05 MB (normal for a split archive)
- `7z t` result: `Everything is Ok`

## Baseline

| Active tasks | Connections/task | Speed/task | Aggregate |
|---:|---:|---:|---:|
| 10 | 16 | 0.76–0.81 MB/s | **7.84 MB/s** |

Per-connection estimate: `0.8 MB/s ÷ 16 ≈ 50 KB/s`.

## Single-task split test

The test task was paused, `split` changed, then resumed.

| Connections | Speed | Notes |
|---:|---:|---|
| 16 | 0.76 MB/s | baseline |
| 32 | 1.5–1.7 MB/s | roughly linear |
| 64 | 3.0–3.4 MB/s | roughly 4× baseline, stable |

## Concurrency test (all tasks at 64 connections)

| Active tasks | Connections (approx.) | Aggregate | Notes |
|---:|---:|---:|---|
| 10 | 640 | 31.1 MB/s | 10 × 3.2 MB/s |
| 12 | 768 | 37.9 MB/s | linear |
| 14 | 839 | 41.3 MB/s | diminishing returns |
| 16 | 990–1024 | **44.0 MB/s** | peak 49.3 MB/s |
| >16 | >1024 | no clear gain | stopped here |

Theoretical estimate:

```text
active_tasks × split × per_connection_speed
16 × 64 × 50 KB/s ≈ 51 MB/s
```

Observed 44 MB/s is close; overhead, retries, server behavior, and mixed task progress explain the gap.

## Final state

- 33/33 volumes downloaded
- No `.aria2` control files
- `7z t` exit code 0
- E: free space after download: 164.7 GB

## Reproducibility notes

- Quark direct links can be time-limited and IP-bound. A proxy/VPN switch may cause 403.
- Different accounts (free/VIP/over-quota), regions, ISPs, CDN nodes, and times of day can produce very different results.
- If aggregate speed stops increasing when adding tasks, the bottleneck is no longer per-connection; stop increasing.
- If 403/429 or retries appear, lower `split` and `max-concurrent-downloads`.
