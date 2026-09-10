# 0002 — The tag names a schedule, it does not contain one

**Status:** accepted · 2026-09-10

## Context

The first version of this tool put the schedule itself into tags on the machine:

```
AutoShutdown              8-18
AutoShutdown-TimeZone     W. Europe Standard Time
AutoShutdown-SkipUntil    2026-08-01
AutoShutdown-ExcludeOn    2026-07-20
AutoShutdown-ExcludeDays  Saturday,Sunday
```

Five tags encoding a small language, repeated on every machine, with nothing checking any of it.
`8-118` is a valid tag value. It is not a valid schedule, and nobody finds out until 18:00.

Two things forced a rethink. Fixing a wrong schedule meant retagging every affected machine, and
`Microsoft.Resources/tags/write` is a permission handed out very widely — which made "can edit tags"
mean "can decide when production shuts down".

Meanwhile Azure grew its own scheduler. `Microsoft.ComputeSchedule` performs batched
Start/Deallocate/Hibernate with throttling and retries handled, and a recurring `scheduledActions`
resource exists in the template schema. Whatever shape this tool stores a schedule in, it should be
able to hand that schedule to Azure without a rewrite.

## Decision

A tag names a schedule. The schedule lives in a catalogue.

```
PowerSchedule    office-hours-ch
```

The catalogue is a list of named schedules, seeded by the deployment into an Automation variable and
edited with `Get-VmPowerSchedule`, `Set-VmPowerSchedule` and `Test-VmPowerSchedule`. Anyone can define
their own; the ones that ship are examples, not a fixed set.

A schedule is a list of **actions**, because that is how Azure models one — a scheduled action carries
exactly one `actionType`. "Office hours" is two actions, not one window:

```jsonc
{
  "name": "office-hours-ch",
  "displayName": "Office hours, Switzerland",
  "timeZone": "W. Europe Standard Time",
  "actions": [
    { "action": "Start",      "at": "07:30", "weekDays": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] },
    { "action": "Deallocate", "at": "18:30", "weekDays": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] }
  ],
  "exceptDates": ["2026-12-24", "2026-12-25"],
  "minimumDwellMinutes": 30
}
```

Every field maps onto `Microsoft.ComputeSchedule/scheduledActions`: `action` → `actionType`,
`at` → `scheduledTime`, `weekDays` → `requestedWeekDays`, `timeZone` → `timeZone`, and the optional
`months` and `daysOfMonth` → `requestedMonths` and `requestedDaysOfTheMonth`. Delegating execution
later is a translation, not a redesign.

Because that form is verbose for the common case, a shorthand compiles into it:

```jsonc
{ "name": "office-hours-ch", "timeZone": "W. Europe Standard Time", "weekdays": "07:30-18:30" }
```

`Test-VmPowerSchedule` expands the shorthand and validates the result, so what the engine reads is
always the long form.

Two shapes are special and both are deliberate:

- **No `Deallocate` action** means managed but never stopped. The controller will start the machine
  if it finds it deallocated, and never stops it. This is better than leaving a machine untagged,
  because untagged is indistinguishable from forgotten.
- **`exceptDates`** are supplied by whoever writes the schedule. No holiday calendar ships with this
  tool. Cantonal holidays alone would make a bundled calendar wrong for most readers, and a wrong
  calendar that looks authoritative is worse than none.

The inline form survives as a shorthand for a single machine that needs no catalogue entry:
`PowerSchedule: 07:30-18:30`. It is parsed as an anonymous schedule in the runbook's own time zone.

## Why

- **One place to fix a mistake.** A wrong schedule is one edit, not a retagging campaign.
- **The tag value becomes an enum**, so Azure Policy can carry the catalogue names in `allowedValues`
  and reject a typo at deployment time rather than at 18:00. The policy is generated from the
  catalogue, so the two cannot drift.
- **Least privilege actually means something.** Tag write now moves a machine between schedules that
  were already reviewed. Inventing a schedule is an infrastructure change with a diff and a reviewer.
- **Exceptions live with the schedule**, where one edit covers every machine that follows it, instead
  of being smeared across per-machine tags nobody will remember to clear.
- **It still needs no inventory.** The machine keeps carrying its own intent, which is the reason
  tags won in the first place. Nothing has to be kept in sync when a VM is created or destroyed.
- **It survives Azure catching up.** The stored form is already the shape Azure wants.

## Rejected

**Keep the schedule in the tags.** No validation, no central fix, and it makes a widely granted
permission into a power switch over production. The convenience is real and it is not worth that.

**Drop tags, keep a central list of machines.** This is what Azure's own Scheduled Actions does, and
it is exactly the part that rots: a list of resource IDs nobody updates when machines come and go.
Tags are the answer to that problem, not the problem.

**Ship a holiday calendar per country.** Tempting, and wrong often enough to be dangerous —
Switzerland alone has cantonal holidays. The tool would be confidently incorrect about days people
actually care about.

**Store the catalogue in a storage blob or App Configuration.** Editable without a redeployment,
which sounds like an advantage until the catalogue no longer matches the repository anyone reviews.
An Automation variable seeded by the deployment keeps the reviewed copy authoritative while
`Set-VmPowerSchedule` still allows an urgent change. App Configuration becomes the right answer for
several estates sharing one catalogue, and that is not this version.

## Consequences

- The deployment gains a catalogue parameter and a generated policy definition; both need to be
  written and both need a test that they agree.
- `Test-VmPowerSchedule` becomes load-bearing. Every path into the catalogue goes through it, and its
  fixtures are part of the test suite rather than an afterthought.
- Time zones accept both the Windows form (`W. Europe Standard Time`) and the IANA form
  (`Europe/Zurich`). Both resolve on the Linux workers that run PowerShell 7.2 in Azure Automation,
  and daylight saving is handled by the runtime — verified on 2026-09-10, 12:00 UTC converts to 14:00
  in July and 13:00 in December.
- Migration from the old tags is a one-time job. `Get-VmPowerSchedule -FromLegacyTags` reads the five
  old tags across an estate, proposes catalogue entries that reproduce them, and reports the machines
  whose tags do not parse — which, on any estate that has been running a while, is the interesting
  part of the output.
