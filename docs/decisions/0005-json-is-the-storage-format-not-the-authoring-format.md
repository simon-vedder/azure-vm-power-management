# 0005 — JSON is the storage format, not the authoring format

**Status:** accepted · 2026-09-10

## Context

[0002](0002-the-tag-names-a-schedule-it-does-not-contain-one.md) moved the schedule out of tags and
into a catalogue, and showed the catalogue as JSON. That is what the engine reads and what maps onto
`Microsoft.ComputeSchedule`. It is not something to ask a person to type.

The person defining a schedule is an Azure administrator or a team lead. They know "our development
machines run 07:30 to 18:30, Swiss time, weekdays, off over Christmas". Handing them a JSON blob in a
`.bicepparam` means they get no validation until deployment, no way to see what they defined, and no
way to change it later without a redeployment. Most of them will edit the tag instead, which is the
thing this design moved away from.

There is also a drift trap waiting. If the deployment writes the catalogue on every run, any change
made outside the deployment is silently eaten by the next `az deployment group create`.

## Decision

Nobody hand-writes the catalogue. JSON is what it is stored as, the way ARM JSON is what Bicep is
stored as. Three authoring doors, in the order people will reach for them.

**The cmdlet, and it is the primary door.**

```powershell
New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' |
    Set-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower
```

Validated on the way in, persisted without a redeployment, one line. `New-VmPowerSchedule` also takes
`-Days`, `-Start`, `-Stop`, `-ExceptDate` and `-NeverStop` for the cases the shorthand does not cover,
and it emits an object, so composing several and piping them is natural.

Authoring in a console is only safe if you can see the result, so it comes with:

```powershell
Get-VmPowerSchedule office-hours-ch | Show-VmPowerScheduleCalendar -Days 14
```

which prints the next fourteen days of actions in the schedule's own time zone, daylight saving
included. That turns "did I get it right" into something you read rather than something you find out
at 18:30.

**A form at deployment time.** `deploy/createUiDefinition.json` gives the Deploy to Azure button a
real interface — a time picker, day toggles, a time zone dropdown — so the first schedules come out
of a form. It covers first-run only, which is exactly when a JSON blob does the most damage.

**The web app, later.** The self-service page in v2 is the door for people who do not live in
PowerShell. Same store, same validation, a live calendar preview.

**Two variables, so the doors do not fight.**

| Variable | Owner | Behaviour |
|---|---|---|
| `PM_ScheduleCatalog` | the deployment | Holds the shipped examples. Overwritten on every deployment, deliberately. |
| `PM_ScheduleCatalogCustom` | whoever runs `Set-VmPowerSchedule` | **Never touched by the deployment.** |

The runbook reads both and a custom entry wins on a name collision. So an example can be overridden
without being edited, a redeployment never eats somebody's work, and an estate that wants everything
in infrastructure as code simply leaves the custom variable empty.

An Automation variable holds 1,048,576 characters, which is thousands of schedules. Size is not a
reason to reach for another store.

## Why

- **The authoring format and the storage format have different jobs.** One has to be pleasant and
  checkable; the other has to be exact and machine-readable. Conflating them is why the tag version
  failed.
- **A preview is what makes console authoring safe.** Most schedule mistakes are not syntax errors,
  they are "I did not think about the Sunday" — and a printed calendar catches those, while a schema
  validator does not.
- **Splitting ownership of the two variables removes an entire class of support question.** "My
  schedule disappeared after I redeployed" is not a bug anybody should have to diagnose.
- **`createUiDefinition.json` is cheap** and it is the difference between a tool that feels like a
  script and one that feels like a product on the day somebody first tries it.

## Rejected

**Only a Bicep parameter.** Correct for one team that already runs everything through a pipeline,
useless for everybody else, and every edit is a deployment.

**Only the cmdlets.** Leaves the infrastructure-as-code path with nowhere to declare a catalogue, and
makes the first run a scavenger hunt.

**One variable, written by both.** The drift trap above. Whichever wrote last wins, silently.

**A dedicated store — storage blob, App Configuration, a table.** Another resource, another identity,
another thing to pay for and back up, to hold a few kilobytes that an Automation variable already
holds. App Configuration becomes right when several deployments share one catalogue; that is not this
version.

**A schedule as its own Azure resource.** That is what `Microsoft.ComputeSchedule/scheduledActions`
will be. Building a private imitation of it would be exactly the mistake
[0003](0003-a-controller-not-a-scheduler.md) exists to avoid.

## Consequences

- `New-VmPowerSchedule`, `Set-VmPowerSchedule`, `Get-VmPowerSchedule`, `Remove-VmPowerSchedule`,
  `Test-VmPowerSchedule` and `Show-VmPowerScheduleCalendar` are public surface and need help,
  examples and `RequiredPermissions` like everything else.
- The occurrence calculation behind `Show-VmPowerScheduleCalendar` is the same code the decision
  engine uses, or the preview is a lie. One function, two callers.
- `deploy/createUiDefinition.json` is a new artifact with no test harness beyond the portal, so it
  stays small: the examples plus one custom schedule, not a schedule designer.
- The runbook's catalogue read merges two variables, and the merge order is a documented rule rather
  than an implementation detail.
