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
- *(observed)* **A disarmed run fails when the blast radius is set too low.** Disarmed is the same
  code path with `-WhatIf` on it, so every guard is evaluated - including the one that refuses a
  whole run. A job that fails with `more than the N allowed` while `PM_Armed` is false has changed
  nothing and is telling you the number is wrong at the only time that costs nothing. Raise
  `PM_MaximumActions`, or look at what made the plan jump.
- *(observed)* **A second controller in the same tenant fails on the role name.** Custom role display
  names are unique across the whole directory, not per subscription, so deploying into a second
  subscription with the defaults returns `RoleDefinitionWithSameNameExists` before anything is
  created. Pass a different `roleName`. It is rarely needed: one controller reaches every
  subscription its identity can read, which is the point of discovering through Resource Graph.
  Hit on 2026-09-11 while setting up the cross-subscription test.
- *(observed)* **A prerelease `moduleVersion` used to break the deployment.** Automation validates
  `contentUri.version` against `System.Version`, which cannot parse `0.1.3-preview`, and refuses the
  module import with `The contentUri.version property is of an invalid form or value` - an ARM error
  naming a property nobody passed. The Gallery wants the suffix and the content link cannot have it,
  so the suffix is stripped where the stamp is derived. Both Gallery URL forms answer 200 with the
  same package, so `0.1.3` and `0.1.3-preview` are equally valid for `moduleVersion` now. Hit on the
  very first lab deployment of 0.1.3, 2026-09-10.
- *(observed)* **A redeployment resets `PM_LastActionAt` to `{}`.** ARM has no create-if-absent, and
  the variable has to exist before the runbook can write it, so the deployment ships it empty. The
  first run after a redeployment therefore has no memory and the dwell guard stands down for that
  run. The catalogue is unaffected - `PM_ScheduleCatalogCustom` is deliberately not created by the
  deployment for exactly this reason.
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

- *(observed)* **`Set-AutomationVariable` works in the PowerShell 7.2 runtime**, and the value it
  writes survives being read back by `Get-AutomationVariable`. It stores the string it is given, so
  over ARM the value is JSON inside a JSON string; through the asset cmdlet it arrives already
  unwrapped. Both shapes are handled. Measured against a real Automation Account on 2026-09-10:
  `PM_LastActionAt` written by an armed job and read back by the next one, timestamp and zone intact.
- *(observed)* **`Get-AutomationVariable` works in the PowerShell 7.2 runtime**, and every scalar
  setting resolved through it on the first real job: `Armed: False | MaximumActions: 25 | Dwell: 30
  min`, read from `PM_Armed`, `PM_MaximumActions` and `PM_MinimumDwellMinutes`. 2026-09-10.
- *(observed)* **The Azure Automation PowerShell 7.2 sandbox runs on Windows Server 2019**, not on
  Linux. Measured with a probe runbook on 2026-09-10: `Microsoft Windows 10.0.17763`, 141 time zones,
  every one of them a Windows id. `Europe/Zurich` does not resolve there and neither does `Etc/UTC`;
  `W. Europe Standard Time` and `UTC` do. Schedules therefore keep the id they were written with and
  it is translated where it is used - .NET 6 carries the CLDR mapping in both directions. A
  laptop-only measurement said the opposite and it reached a decision record before the first real
  job caught it.
- *(observed)* **.NET in the sandbox runs in NLS mode, so there is no CLDR data and no time zone id
  conversion at all.** `GlobalizationMode.UseNls` is `True`, and both `TryConvertIanaIdToWindowsId`
  and `TryConvertWindowsIdToIanaId` return `False` for everything. Build 17763 is Windows Server
  2019 version 1809, older than the 1903 that first shipped ICU with Windows. An IANA id can only be
  rejected there, never translated, which is why schedules store the Windows form -
  [ADR 0008](docs/decisions/0008-store-the-windows-time-zone-id.md). Measured 2026-09-10.
- *(observed)* **The same variable has two shapes depending on how it is read.** Over ARM,
  `properties.value` is the raw JSON text. `Get-AutomationVariable` deserialises it first, so a JSON
  array arrives as objects. Code that reads a variable both ways - as this tool does, from a laptop
  and from a runbook - has to accept both. Casting the deserialised form to a string and parsing it
  fails with `Additional text encountered after finished reading JSON content`, which is what the
  first real runbook job did on 2026-09-10.
- *(observed)* **A module import attempted immediately after publishing can fail with `No content
  was read from the supplied ContentUri`**, and succeed on a retry minutes later with the same URI.
  The package URL answered 200 with content throughout, so this is the Gallery not yet serving the
  download path Automation uses. A failed import leaves the previous version in place and does not
  fail the rest of the deployment, so the module resource has to be checked rather than the
  deployment status. 2026-09-10.
- *(observed)* **A module published to the Gallery imports cleanly into the PowerShell 7.2 runtime
  next to the global Az bundle**, when its manifest minimums match the runtime's own versions and it
  pulls in nothing else. `AzureVMPowerManagement 0.1.0` imported as `Succeeded` on 2026-09-10. The
  assembly-loading trouble seen on another tool came from importing a newer `Az.Accounts` alongside
  the bundle, not from importing a module at all.

## Sharp edges in the tooling itself

- **`Get-AutomationVariable` returns a Newtonsoft `JObject`, and a `JObject` indexes
  case-sensitively.** It is not an `IDictionary`, it exposes no PowerShell properties, and
  enumerating it yields `JProperty`. The two catalogue variables were not written in the same case -
  Bicep writes `name`, the module used to store the expanded object as `Name` - so reading
  `$entry.name` found the deployment's entries and returned empty for every custom one. All of them
  keyed on an empty string, each replaced the last, and **only one custom schedule survived**. A
  machine tagged with a lost schedule reported `ScheduleNotInCatalogue`, which is indistinguishable
  from a machine nobody onboarded. The module writes camelCase now and the runbook reads either;
  an entry whose name cannot be read stops the run rather than being keyed on nothing. Found on
  2026-09-11 by running a real armed job with two custom schedules.
- **PowerShell unrolls a collection on its way out of a function, and these collections nest.** A
  `JArray` yields `JObject` and a `JObject` yields `JProperty`, so a catalogue variable holding
  **exactly one** schedule arrived at the caller as that schedule, and one level further as that
  schedule's fields - a run that died on `Expand-VmPowerSchedule was given a collection`. Two or
  more schedules hid it completely, which is why it survived a lab, an armed run and 181 tests.
  Structured variables are read through their own function with `Write-Output -NoEnumerate`.
- **`-NoEnumerate` is not transparent.** Applied to a string it returns
  `System.Collections.Generic.List[object]` holding that string, so a single reader cannot serve
  both scalars and collections. That is why there are two.
- **An Az power cmdlet takes no subscription.** `Stop-AzVM` and `Start-AzVM` have `-ResourceGroupName`
  and `-Name` and act in whatever subscription the current context points at; `Connect-AzAccount
  -Identity` picks the first one it sees. Discovery has no such limit - one Resource Graph query
  answers for every subscription the identity can read. Left alone the two halves disagree in
  silence: a plan spanning three subscriptions fails on two of them, and where a resource group name
  and a machine name are reused - which dev and test estates do constantly - the call resolves
  against the wrong subscription and deallocates the wrong machine. The context is now pinned per
  machine from the subscription on the plan. Found on 2026-09-10 by running the runbook end to end
  against two simulated subscriptions; 168 unit tests had nothing to say about it.
- **`ConvertFrom-Json` does not give back the string that went in.** It recognises an ISO-8601 value
  and returns a `DateTime`, correctly zoned - and `[string]` on that `DateTime` renders the short
  invariant form, without the `Z` and without the fractional seconds. `Kind` becomes `Unspecified`
  and every reader downstream is free to call it local. That is how the dwell store aged itself by
  the local offset and pruned entries that were seconds old. Timestamps are formatted with `'o'`
  explicitly on the way through, and an unzoned value in that store is read as UTC.

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
