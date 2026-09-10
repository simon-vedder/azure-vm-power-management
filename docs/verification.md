# Verification log

What has actually been run, where, and what it showed. A row lands here with the run behind it;
anything not proved is in [KNOWN-ISSUES.md](../KNOWN-ISSUES.md) instead.

## 2026-09-10 — the rules, against four real machines

Subscription: a personal Azure test subscription, `westeurope`. Four `Standard_B1s` Ubuntu machines,
no public addresses, one of each case. Torn down afterwards; cost a few cents.

`az vm stop` produces the stranded state without touching the guest — a graceful shutdown that
leaves the machine allocated, which is what a person shutting down from inside the OS produces.

| Machine | State | Tags | Decision | Correct |
|---|---|---|---|---|
| `vm-stranded` | `PowerState/stopped` | `PowerSchedule` | `Deallocate` — StoppedNotDeallocated | yes |
| `vm-untagged` | `PowerState/stopped` | none | `None` — StrandedButNotOnboarded | yes |
| `vm-scheduled` | running | `PowerSchedule` | `None` — MatchesSchedule | yes |
| `vm-excluded` | running | `PowerSchedule` + exclusion | `None` — Excluded, protected | yes |

- **Armed run.** `vm-stranded` moved from `VM stopped` to `VM deallocated` — billed to not billed.
  `vm-untagged` was left alone, which is the opt-in rule holding under real conditions rather than in
  a fixture.
- **Blast radius.** A plan of two actions against `-MaximumActions 1` performed none of them and
  said so.
- **`-WhatIf`.** Changed nothing, and returned a row per machine including the skipped ones.
- **Planning for another moment.** At 23:00 local, `vm-scheduled` became `Deallocate` —
  ShouldBeStopped, and the excluded machine stayed protected.

## 2026-09-10 — the catalogue, against a real Automation Account

- The catalogue round-trips through two Automation variables.
- A custom entry beats the shipped example of the same name; `Source` says which is which.
- **A redeployment leaves `PM_ScheduleCatalogCustom` alone.** Deployed, added two custom schedules
  including an override, redeployed, and the override still won.

## 2026-09-10 — the runbook, inside the sandbox

Four scheduled jobs. The first three failed, each on something no local test could have found.

| Job | Result | What it showed |
|---|---|---|
| 1 | Failed | `Get-AutomationVariable` **works** in the 7.2 runtime — `Armed: False \| MaximumActions: 25 \| Dwell: 30 min`. Died on the catalogue: the cmdlet deserialises a variable, ARM returns raw JSON text, and the runbook assumed the latter. |
| 2 | Failed | Past the catalogue. Died on `Europe/Zurich`, which the sandbox cannot resolve. |
| 3 | Failed | Same, with the intended error message: the translation could not work either. |
| 4 | **Completed** | `Catalogue: 2 schedule(s) — always-on, office-hours-ch` · `Planned: 0 machine(s), 0 actionable` · `Summary: nothing to do`, disarmed. |

Two probe runbooks settled the platform questions:

```
OS                    : Microsoft Windows NT 10.0.17763.0
GetSystemTimeZones    : 141 zones, all Windows ids
UseNls (no ICU)       : True
Etc/UTC                          missing
Europe/Zurich                    missing
W. Europe Standard Time          OK
IANA->Windows Europe/Zurich            ok=False
Windows->IANA W. Europe Standard Time  ok=False
```

The sandbox is **Windows Server 2019, build 17763** — not Linux — and .NET there runs in NLS mode
with no CLDR data at all. An IANA id can only be rejected, never translated, which is why schedules
store the Windows form ([ADR 0008](decisions/0008-store-the-windows-time-zone-id.md)).

A module published to the Gallery imports cleanly next to the runtime's global Az bundle. An import
attempted immediately after publishing failed once with `No content was read from the supplied
ContentUri` and succeeded on a retry minutes later, unchanged.

## 2026-09-10 — daylight saving, measured not assumed

Europe/Zurich, 2026:

- **29 March, 02:30 does not exist.** `TimeZoneInfo.ConvertTimeToUtc` throws. An action there is
  moved to the first valid instant and marked; unhandled it would take the runbook down once a year.
- **25 October, 02:30 happens twice.** .NET resolves it to standard time — 01:30 UTC, the later of
  the two instants. Taken as-is and marked.
- 07:30 local is 05:30 UTC in July and 06:30 UTC in December.

## What is still unproved

- The controller has never run **armed** on a schedule inside a sandbox. Every armed run so far was
  from a laptop.
- No estate large enough to page Resource Graph has been seen.
- Nothing has run for long enough for the minimum dwell to matter in production.
