# R5 — Daytona Live Audit

- Date: 2026-10-20
- Method: read-only inspection of the already-open Daytona dashboard tab (`tab_fdcc0f16-218d-4fb3-84d4-e400444c2bb1`). No sandbox, key, or setting was created, modified, or deleted. No new tab was opened. No secret value was printed.

## 1. Organization tier, usage and limits

| Item | Live value |
|---|---|
| Tier | **Tier 1** |
| Region | **us** only (other regions: contact sales) |
| Compute (live) | 0 / 10 vCPU |
| Memory (live) | 0 / 10 GiB |
| Storage (live) | 0 / 30 GiB |
| GPU | Locked (“Top up to unlock GPUs”) |
| Per-sandbox compute | 4 vCPU |
| Per-sandbox memory | 8 GiB |
| Per-sandbox storage | 10 GiB |

## 2. Rate limits

Dashboard cards:

- General requests: **50,000 / 1 min**
- Sandbox creation: **600 / 1 min**
- Sandbox lifecycle: **50,000 / 1 min**

Tier table (same page):

| Tier | vCPU | Memory | Storage | API req/min | Creation/min | Lifecycle/min |
|---|---|---|---|---|---|---|
| 1 (current) | 10 | 10 | 30 | 10,000 | 300 | 10,000 |
| 2 | 100 | 200 | 300 | 20,000 | 400 | 20,000 |
| 3 | 250 | 500 | 2000 | 40,000 | 500 | 40,000 |
| 4 | 500 | 1000 | 5000 | 50,000 | 600 | 50,000 |

The dashboard cards and the tier table disagree on the exact rate values; both are recorded verbatim.

## 3. Network policy

The Limits page shows:

- **Preview Warning:** “Shown on Tier 1 & 2. Removed for Tier 3+.”
- **Internet Access:** “Restricted on Tier 1 & 2. Full access for Tier 3+.”

There is no sandbox-level toggle that overrides this. Full outbound browsing requires upgrading to Tier 3+. The sandbox creation dialog’s network switches (Public HTTP Preview, Block All Network Access) do not change the Tier 1/2 restriction.

## 4. Existing sandboxes

**None.** The sandboxes list is empty after the earlier `kelivo-inspect-2026-10-20` deletion.

## 5. API keys (names and last 4 only)

| Name | Permissions | Created | Last used | Expires | Key |
|---|---|---|---|---|---|
| `kelivo-work-2026-10-20` | Sandboxes, Access | 4h ago | 18m ago | — | `dtn********************826` |

No key values were read.

## 6. Snapshots

**0 snapshots.** The function uses the Daytona default image (`daytonaio/sandbox:0.8.0`) when `DAYTONA_SNAPSHOT` is unset.

## 7. Tier upgrade requirements

Shown on the Limits page:

- Credit card linked
- Top up **$25 (one time)**
- Then the Upgrade button becomes available
- Other regions: contact `sales@daytona.io`

Tier 3 is required for full internet access.

## 8. Audit trail

The earlier inspection sandbox is no longer listed. No separate audit-log entry was read for this report.
