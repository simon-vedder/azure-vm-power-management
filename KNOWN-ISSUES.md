# Known issues and sharp edges

Every entry says where it comes from: *(observed)* in this project's lab or a real run,
*(Microsoft)* from official documentation, *(to verify)* on the lab list. Nothing here is guessed.

## Behaviour

- *(observed)* **A machine in `PowerState/stopped` is deallocated even when its schedule wants it
  up, and is then left alone.** Somebody shut it down from inside the guest; the tool stops paying
  for it and does not restart it. It is picked up again at the next scheduled start, within that
  schedule's `startGraceMinutes`. Until [ADR 0007](docs/decisions/0007-start-only-while-the-start-is-recent.md)
  it was restarted on the very next run, so the visible effect of shutting a machine down was that
  it rebooted - found in the lab on 2026-09-10, not by any test.
- *(observed)* **Deallocating releases a dynamic private IP address.** The stranded-machine rule is
  free of downtime risk because nothing is running, but a machine that comes back may not come back
  on the same address. Static addresses are unaffected. Verified against the documented behaviour of
  deallocation rather than in a lab.
- *(Microsoft)* **Azure bills a five-minute minimum per virtual machine start**, effective
  1 June 2025. A schedule that flaps costs money as well as being wrong, which is what
  `minimumDwellMinutes` exists for.
- *(observed)* **Local times in the daylight saving gap are shifted forward.** On 29 March 2026 in
  Europe/Zurich, 02:30 does not exist and `TimeZoneInfo.ConvertTimeToUtc` throws. An action there is
  moved to the first valid instant and marked. Measured on 2026-09-10.
- *(observed)* **Local times in the doubled autumn hour resolve to standard time.** On
  25 October 2026, 02:30 local becomes 01:30 UTC, not 00:30 - the later of the two instants. Taken
  as-is and marked. Measured on 2026-09-10.

## Platform

- *(observed)* **`Microsoft.ComputeSchedule/scheduledActions` does not resolve in a normal
  subscription.** The recurring resource is in the ARM, Bicep and Terraform schemas, but on
  2026-09-10 it returned `InvalidResourceType` at every api-version in a subscription with the
  provider registered. Two features exist and are unregistered: `ComputeSchedulePreview` and
  `DefaultFeature`. The one-off batch API does answer. This is why the controller owns the
  recurrence - see [ADR 0003](docs/decisions/0003-a-controller-not-a-scheduler.md).
- *(Microsoft)* **An Azure Automation schedule cannot run more often than hourly.** Microsoft's own
  workaround is four schedules fifteen minutes apart, or a Logic App calling a webhook. This tool
  uses one hourly trigger and hands exact times to the batch API instead - see
  [ADR 0006](docs/decisions/0006-one-trigger-many-schedules.md).
- *(observed)* **`Az.ResourceGraph` is not in the Automation PowerShell 7.2 bundle**, and importing
  Az modules alongside that bundle has broken assembly loading in the sandbox before. Resource Graph
  and the Automation variables are both reached over REST through `Invoke-AzRestMethod`, which
  Az.Accounts already provides.
- *(observed)* **Resource Graph returns an empty power state for anything that is not a virtual
  machine**, and for a machine whose instance view it does not have. The rules treat an unreadable
  power state as a reason to do nothing rather than a reason to act. Verified against a live tenant
  on 2026-09-10.
- *(observed)* **An Automation variable value has to be valid JSON, and is stored verbatim.**
  Anything else is refused with `Invalid JSON - Kindly check the value of the variable`. Two traps
  come with that in Bicep: ARM's `string(false)` is `False` with a capital F, which JSON does not
  accept, and a bare word like `PowerSchedule` is not a JSON string until it is quoted. Numbers and
  arrays from `string()` are already valid. Measured against a real Automation Account on
  2026-09-10, where four of eight variables failed on the first deployment.
- *(observed)* **A redeployment leaves `PM_ScheduleCatalogCustom` alone.** Deployed, added two
  custom schedules including one overriding a shipped example, redeployed, and the override still
  won. 2026-09-10. That split is the whole point of having two variables.

- *(observed)* **`az vm stop` produces the stranded state without touching the guest.** It performs
  a graceful shutdown and leaves the machine allocated, which is exactly what a person shutting down
  from inside Windows or Linux produces. Useful for a lab: no public address and no sign-in needed.

- *(to verify)* **`Get-AutomationVariable` inside the PowerShell 7.2 runtime.** Every setting the
  deployment writes - whether it is armed, the blast radius, the catalogue - is read through that
  internal cmdlet. Microsoft documents `Orchestrator.AssetManagement.Cmdlets` as installed by default
  and available in the sandbox, but says nothing specific about the 7.2 runtime, and no runbook job
  has run yet. The failure mode is safe rather than silent: without it the fallbacks apply, the blast
  radius reads as zero and the run refuses with "No blast radius is set". On the lab list.

## Sharp edges in the tooling itself

- **`switch ($true)` does not coerce the way `-eq` does.** `$true -eq 'some-string'` is `True`, but
  a case label of `('some-string')` never matches, because switch compares the case value against
  the switch value as a string. A case expression that is not already a boolean is dead code. One
  branch shipped that way and was caught on 2026-09-10; every case in the module is a boolean now.
- **`-match` is case-insensitive.** A lowercase-only pattern silently accepts `Office-Hours`.
  Schedule names are checked with `-cnotmatch`.
- **`[datetime]'2026-10-25T00:00:00Z'` is not a UTC value.** PowerShell converts it to the local
  time zone and keeps `Kind` as `Local`. Relabelling it with `SpecifyKind` moves the window by the
  local offset without saying so; the incoming `Kind` is respected instead.
- **`[bool]'false'` is `$true`.** Every non-empty string is. A setting read back from an Automation
  variable may arrive as a boolean or as the text, depending on how it was stored, so a cast would
  arm a deployment whose `PM_Armed` says false. The runbook parses booleans explicitly and refuses
  to run on a value it cannot read as a yes or a no.
- **A local variable that matches a typed parameter name is coerced to that type.** PowerShell
  variable names are case-insensitive, so inside a function with `[object[]]$Schedule` a loop
  variable written `$schedule` *is* that parameter: every assignment to it silently becomes a
  one-element array. The stored catalogue came out as `[[{..}],[{..}]]` and the read side could only
  say "a schedule with no name". It cost several hours on 2026-09-10 because the function behaves
  correctly everywhere except inside the one that declares the parameter, so no isolated test could
  see it. A typed parameter makes its own name unusable as a local.
- **The member form of `ForEach-Object` supports `ShouldProcess`.** `$items | ForEach-Object Name`
  inside a `SupportsShouldProcess` function raises its own confirmation under `-WhatIf` and returns
  nothing, so a message built from it loses exactly the information it exists to carry. Use
  `Select-Object -ExpandProperty`.
- **`, $array` emits the array as one pipeline item.** `@()` at the call site then collects it as a
  single element rather than unrolling it, so no rows become one phantom row and many rows become
  one object that is really the whole list.
