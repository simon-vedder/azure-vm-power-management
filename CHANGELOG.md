# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

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
