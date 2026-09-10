# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Fixed

- **A prerelease `moduleVersion` no longer breaks the deployment.** Automation validates
  `contentUri.version` against `System.Version`, which cannot parse `0.1.3-preview`, so the module
  import failed with `The contentUri.version property is of an invalid form or value` - an ARM error
  naming a property nobody passed. The Gallery needs the suffix and the content link cannot have it,
  so it comes off where the stamp is derived. Template only; the module is unchanged.

### Verified

- **0.1.3-preview ran armed in a real Automation Account**, deallocated a stranded machine, left the
  untagged one alone, wrote its dwell memory and was held back by that memory on the next run. It is
  the first armed run on a schedule inside a sandbox, and it settles `Set-AutomationVariable`. Full
  log in [docs/verification.md](docs/verification.md).

## [0.1.3-preview] - 2026-09-10

The first end-to-end run of the runbook itself, and the four defects it found.

### Fixed

- **Execution now follows discovery across subscriptions.** One Resource Graph query answers for
  every subscription the identity can read, but `Stop-AzVM` and `Start-AzVM` take no subscription
  and act wherever the context points. A plan spanning several subscriptions failed on all but one
  of them - and where a resource group name and a machine name are reused, which dev estates do
  constantly, it resolved against the wrong subscription and deallocated the wrong machine. The
  context is pinned per machine from the plan; a subscription that cannot be reached fails that
  machine and no other.
- **The minimum dwell guard can fire.** `Invoke-VmPowerPlan` needs `-LastActionAt` and the runbook
  never passed it, so the guard described in the README, the runbook help and the command reference
  had nothing to compare against and stood down on every run. The controller now keeps what it
  touched in a new Automation variable, `PM_LastActionAt`.
- **A schedule's own `minimumDwellMinutes` is read.** It was authored by `New-VmPowerSchedule`,
  validated, stored, and shipped in the default catalogue - and no rule ever looked at it. It now
  travels with the decision, and the executor takes the longer of it and the run-wide setting. A
  schedule can ask for more caution, never less; zero on the run-wide setting still means off.
- **A timestamp survives the round trip through an Automation variable.** `ConvertFrom-Json` hands
  an ISO-8601 value back as a `DateTime` and `[string]` on that drops the `Z`, so the dwell store
  aged itself by the local offset and pruned entries that were seconds old.
- **The workbook no longer treats a machine name as an identity.** Two subscriptions with a
  resource group of the same name and a machine of the same name collapsed into one row, in the
  panel that exists to find exactly those machines.
- The command reference said `0.1.0-preview` and the README's status said the same; both are
  regenerated from the manifest.

### Changed

- **Disarmed is the same code path with `-WhatIf` on it**, not a second one. Every guard is now
  evaluated in a dry run, so a blast radius set too low fails a job in week one instead of on the
  day somebody arms it, and a machine held back by a guard appears in the report with the guard's
  own word for it.

### Added

- **An end-to-end exercise of the runbook**, in `tests/orchestrator`, run by CI. Real module, real
  rules, real executor; Azure and the Automation asset store are stubs. The estate has two
  subscriptions holding a machine of the same name in a resource group of the same name. Every
  defect above came out of it and none was visible to the 168 unit tests beside it.

- **A workbook that shows what the controller decided and why.** It reads the runbook's own job
  streams, so there is no data collection rule, no custom table and nothing that can disagree with
  the job log. The runbook writes one machine-readable record per machine alongside the readable
  line. No money figure: pricing per size, region and licence is not something to guess at.
- **Two Azure Policy definitions, generated from the catalogue.** One catches a `PowerSchedule` tag
  naming a schedule that does not exist, the other reports machines with no tag at all. The allowed
  values come from `scheduleCatalog`, so a schedule that exists is one the policy accepts. Both
  default to `Audit`.

### Verified

- **The loop closes.** Fourth scheduled job in a real Automation Account completed disarmed:
  settings from variables, both catalogue variables merged and validated, time zones resolved,
  Resource Graph queried, a plan printed, nothing touched. Full log in
  [docs/verification.md](docs/verification.md).

## [0.1.2-preview] - 2026-09-10

### Fixed

- **A schedule stores the Windows time zone id.** `0.1.1-preview` tried to translate an IANA id
  inside the sandbox, which cannot be done: .NET there runs in NLS mode with no CLDR data, so both
  conversion directions return false and `Europe/Zurich` can only be rejected. The conversion now
  happens where ICU is, on the way into the catalogue — [ADR 0008](docs/decisions/0008-store-the-windows-time-zone-id.md).
- The catalogue that ships with the deployment uses Windows ids for the same reason; it is written
  straight into an Automation variable without passing through the module.

## [0.1.1-preview] - 2026-09-10

The first two runbook jobs in a real Automation Account, and what they broke.

### Fixed

- **Time zone ids resolve on both platforms.** The Azure Automation PowerShell 7.2 sandbox is
  Windows Server 2019, not Linux, and knows only Windows time zone ids: `Europe/Zurich` does not
  resolve there and neither does `Etc/UTC`. A schedule keeps the id it was written with and it is
  translated where it is used, using the CLDR mapping .NET 6 carries. `0.1.0-preview` could not
  resolve any schedule inside a sandbox.
- **The catalogue is read in whichever shape it arrives.** Over ARM an Automation variable's value
  is raw JSON text; `Get-AutomationVariable` deserialises it first. The runbook assumed the former
  and died on `Additional text encountered after finished reading JSON content`.

### Verified

- **`Get-AutomationVariable` works in the PowerShell 7.2 runtime.** Every scalar setting resolved on
  the first real job: `Armed: False | MaximumActions: 25 | Dwell: 30 min`.
- **The module imports cleanly from the Gallery next to the global Az bundle**, when its manifest
  minimums match the runtime's own versions.

## [0.1.0-preview] - 2026-09-10

First release of the rebuild. The tag-driven runbook that came before it is kept in
[`legacy/`](legacy/) and at the git tag `legacy/tag-driven`; it still works and is the fallback
until this has run a full loop inside a real Automation Account.

### Added

- **`Get-VmPowerPlan`** — reads every machine the caller can see through one Resource Graph query
  and returns a decision each, including the ones it leaves alone and why. Read-only.
- **`Invoke-VmPowerPlan`** — performs a plan behind four guards: `ShouldProcess`, a mandatory blast
  radius, a minimum dwell, and protected markers.
- **Schedules.** `New-VmPowerSchedule`, `Test-VmPowerSchedule`, `Show-VmPowerScheduleCalendar`,
  and `Get-`/`Set-`/`Remove-VmPowerSchedule` against the Automation Account. A tag names a schedule;
  the schedule lives in a catalogue.
- **Bicep deployment** — Automation Account with a system-assigned identity, a custom role with four
  actions, the module import, the runbook, an hourly trigger, and every setting as a variable.
- Seven [architecture decisions](docs/decisions), [when not to use
  this](docs/when-not-to-use-this.md), and [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

### Changed

- The hourly loop that read five `AutoShutdown-*` tags per machine is gone. Azure ships
  `Microsoft.ComputeSchedule` now, so this keeps intent, safety and evidence and hands execution to
  Azure — [ADR 0003](docs/decisions/0003-a-controller-not-a-scheduler.md).
- A tag names a schedule instead of containing one —
  [ADR 0002](docs/decisions/0002-the-tag-names-a-schedule-it-does-not-contain-one.md).
- The deployment arrives disarmed. Arming it is one edit of `PM_Armed`, not a redeployment.

### Verified

- **2026-09-10, live subscription.** Four machines, one of each case. The plan was right on all
  four; the armed run moved a stranded machine from `Stopped` to `Deallocated` and left the untagged
  one alone. Blast radius refused two actions against a cap of one. `-WhatIf` changed nothing.
- **2026-09-10.** The catalogue round-trips through two Automation variables, a custom entry beats
  the shipped example of the same name, and a redeployment leaves `PM_ScheduleCatalogCustom` alone.
- **2026-09-10.** Daylight saving measured against Europe/Zurich for 2026: an action in the spring
  gap is shifted out of it, one in the doubled autumn hour resolves to standard time.

### Not verified yet

- The runbook has never run **inside** the Automation sandbox. `Get-AutomationVariable` is documented
  as available there but was not exercised, and every setting the deployment writes is read through
  it. See [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

[Unreleased]: https://github.com/simon-vedder/azure-vm-power-management/compare/v0.1.2...HEAD
[0.1.2-preview]: https://github.com/simon-vedder/azure-vm-power-management/releases/tag/v0.1.2
[0.1.1-preview]: https://github.com/simon-vedder/azure-vm-power-management/releases/tag/v0.1.1
[0.1.0-preview]: https://github.com/simon-vedder/azure-vm-power-management/releases/tag/v0.1.0
