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

## 2026-09-10 — the runbook end to end, against a simulated estate

`tests/orchestrator/Invoke-OrchestratorScenarios.ps1`, driven by `tests/Orchestrator.Tests.ps1` in
CI. Real module, real rules, real executor; Resource Graph, the Az power cmdlets, the Az context and
the Automation asset store are stubs. Nothing reaches a network.

The estate is deliberately awkward: **two subscriptions, each with a machine called `vm-app` in a
resource group called `rg-shared`**, plus one always-on machine. Only the subscription tells the
first two apart, and `Stop-AzVM` has no parameter for it.

| Scenario | Result |
|---|---|
| Disarmed | 0 power calls, a decision recorded for all three machines, reasons not the word WhatIf |
| Disarmed, `-MaximumActions 1` | run refused, nothing done — the blast radius is checked in a dry run too |
| Armed | both `vm-app` machines deallocated, **one in each subscription** |
| Armed again, minutes later | 0 power calls: held by the schedule's own 45 minute dwell, not the run-wide 30 |
| Armed, memory aged past the window | 1 power call, the guard released |
| `PM_LastActionAt` set to junk | run stopped with the variable named, 0 power calls |

Three defects came out of this, none of which the 168 unit tests could see, because each half was
correct on its own:

- **Execution could not follow discovery across subscriptions.** The context was never switched, so
  the second machine either failed as not found or - with the names reused - resolved to the first
  subscription and deallocated the wrong machine.
- **The dwell guard could not fire at all.** `Invoke-VmPowerPlan` needs `-LastActionAt` and the
  runbook never passed it, so three documents described a guard with nothing to compare against.
  The per-schedule `minimumDwellMinutes` was authored, validated, stored and read by nothing.
- **The dwell store lost its time zone on the round trip.** `ConvertFrom-Json` returns a `DateTime`,
  `[string]` on it drops the `Z`, and the store then aged by the local offset and pruned itself
  empty one run after it was written.

## 2026-09-10 — 0.1.3-preview, armed, in a real Automation Account

A personal Azure test subscription, `westeurope`. One deployment of `main.bicep` at
`moduleVersion=0.1.3-preview`, two `Standard_B1s` machines, both put into `PowerState/stopped` with
`az vm stop`. One tagged `PowerSchedule=office-hours-ch`, one left untagged. Torn down afterwards,
subscription verified empty; cost a few cents.

The first deployment failed, on the version string itself:

> `The contentUri.version property is of an invalid form or value. It must be null or of a form
> compliant with the System.Version class.`

`contentVersion` defaulted to `moduleVersion`, and `0.1.3-preview` is a SemVer, not a
`System.Version`. The Gallery needs the suffix and the content link cannot have it. Fixed by
stripping it where the stamp is derived — and worth noting that this is the version string the
README itself calls published, so the first person to copy it would have hit the same wall.

| Job | Armed | Result |
|---|---|---|
| 1 | no | Both machines discovered. Tagged → `Deallocate`/StoppedNotDeallocated, untagged → `None`/StrandedButNotOnboarded. Nothing touched. |
| 2 | **yes** | `vm-lab-tagged` moved `VM stopped` → `VM deallocated`. `vm-lab-untagged` left alone: opt-in holding under real conditions. `PM_LastActionAt` written. |
| 3 | yes | `Dwell: 30 min, 1 machine(s) remembered from earlier runs` — the store round-trips. |
| 4 | yes | Machine put back into `stopped` by hand. `Deallocate - Skipped: Acted on 5 minute(s) ago, inside the 30 minute dwell`. Left in `stopped`. |

What that settles:

- **The controller has now run armed on a real schedule inside the sandbox.** Every armed run before
  this was from a laptop.
- **`Set-AutomationVariable` works in the PowerShell 7.2 runtime.** This was the one load-bearing
  unknown in the dwell memory, and the reason the write was built to degrade rather than fail.
- **The dwell guard fires against a real machine**, with the timestamp and its zone intact across
  the Automation variable. The same round trip had silently pruned itself empty two hours earlier.
- **The workbook's headline panel returns rows from real data.** Job streams reached Log Analytics
  and `Powered off and still billed` listed both machines, one `yes`, one `no - reported only`.
- **`Switch-VmPowerSubscriptionContext` moves a real context between two real subscriptions**, and
  restores it. Read-only, from a laptop: nothing was deployed to the second subscription.

## 2026-09-11 — the schedule paths, armed, against real machines

The earlier labs only ever exercised the stranded rule. Nothing had yet stopped a running machine
because a schedule said so, and nothing had started one. Three `Standard_B1s` machines in a personal
test subscription, a second deployment, torn down afterwards.

| Machine | Before | Tag | Result |
|---|---|---|---|
| `vm-sched-start` | deallocated | `lab-up-now` | **`Start` — ShouldBeRunning.** Came back running. |
| `vm-sched-stop` | running | `lab-down-now` | **`Deallocate` — ShouldBeStopped.** `Schedule 'lab-down-now' has it down at this time and it is running.` |
| `vm-excluded` | running | `lab-down-now` + exclusion | **`None` — Excluded**, while armed and while its schedule wanted it down |

Also proved in the same lab:

- **`Set-VmPowerSchedule`, `Get-VmPowerSchedule` and `Remove-VmPowerSchedule` against a real
  account**, including `-WhatIf`, the merge of the two variables and the `Source` each entry came
  from.
- **The generated policy fires.** A machine tagged `PowerSchedule=typo-not-in-catalogue` was reported
  `NonCompliant` against `vm-power-unknown-schedule` by Azure Policy itself.
- **A catalogue written by an older version still works.** The custom variable held the PascalCase
  shape throughout, and the next write converted it.

The first armed run of this lab **did not** stop `vm-sched-stop`, and that is the point of the entry
below it: two defects were sitting in the merge, and neither was reachable from anything but a real
Automation sandbox with more than one custom schedule.

## 2026-09-11 — two defects in the catalogue merge

Both found by the run above, both invisible to 181 local tests, and both in the seam between the
runbook and the Automation asset store rather than in any rule.

1. **Only one custom schedule survived.** `Get-AutomationVariable` returns a Newtonsoft `JObject`,
   which indexes case-sensitively; Bicep writes `name` and the module wrote `Name`. Every custom
   entry keyed on an empty string and replaced the one before it. The machine tagged with the lost
   schedule reported `ScheduleNotInCatalogue` and was never touched.
2. **A catalogue of exactly one schedule broke the run.** PowerShell unrolls a collection leaving a
   function, and these nest: `JArray` → `JObject` → `JProperty`. One schedule arrived as its own
   fields. Two or more hid it entirely.

The orchestrator scenarios now stub `Get-AutomationVariable` with real `JArray`/`JObject` values
rather than strings, which is what makes either failure reproducible off Azure. Reverting each fix
makes exactly the new tests fail, and nothing else.

## 2026-09-11 — one armed run, across two subscriptions

The controller was deployed into a **second subscription that holds no virtual machines at all**,
and the machine it had to act on lived in the first one. That is the sharper direction: with the
context left where `Connect-AzAccount -Identity` puts it, every action would look for the machine in
the controller's own subscription and fail.

Sharper still, the resource group is called `rg-vmpower-xsub` on **both** sides, and the machine is
called `soak-office` - a name that also exists in the other subscription. Left unswitched, the call
resolves against a resource group that really exists and simply has no such machine.

```
Planned: 1 machine(s), 1 actionable
PMREC {... "vm":"soak-office","rg":"rg-vmpower-xsub","sub":"<the other subscription>",
       "state":"running","sched":"office-hours-ch","action":"Deallocate","reason":"ShouldBeStopped","status":"Done"}
[soak-office] Deallocate - Done: Schedule 'office-hours-ch' has it down at this time and it is running.
```

The machine ended `VM deallocated`. The identity held the operator role on one resource group in the
other subscription and nothing else, so discovery returned exactly that one machine - the blast
radius bounded by RBAC rather than by the tool, which is the design.

Found on the way: **a second controller in the same tenant fails on the custom role name**, because
role display names are unique per directory. `roleName` exists for it; the default collides.

## What is still unproved

- No estate large enough to page Resource Graph has been seen.
- Nothing has run for a week, so no report covers a daylight saving change or a weekend.
