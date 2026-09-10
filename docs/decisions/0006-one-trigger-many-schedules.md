# 0006 — One trigger, many schedules

**Status:** accepted · 2026-09-10

## Context

Two different things in this design are called a schedule, and confusing them produces a wrong
architecture.

- An **Automation Schedule** is a trigger. It says "run this runbook at these times". It knows nothing
  about virtual machines.
- A **power schedule** is a rule in the catalogue. It says "machines that follow me are up 07:30 to
  18:30 on weekdays". It knows nothing about runbooks.

The obvious-looking design maps one onto the other: a catalogue entry becomes an Automation Schedule,
adding a schedule adds a trigger. It does not survive contact with the platform.

Azure Automation's documented floor is one hour: *"The most frequent interval for which a schedule in
Azure Automation can be configured is one hour."* Microsoft's own workaround is either four schedules
started fifteen minutes apart, or a Logic App calling a webhook. So an hourly trigger cannot act at
07:30 and 18:30 — and half past is a completely ordinary thing for somebody to want.

## Decision

**One Automation Schedule.** Hourly. It is a heartbeat, not a calendar. It is created once by the
deployment and never changes when somebody adds a power schedule.

The runbook it fires is a planner. Each run it looks at the hour **ahead**, works out every action due
in it, and submits those actions to `Microsoft.ComputeSchedule` **with their exact timestamps**. The
07:00 run submits "deallocate these at 07:30". Submit-type operations accept a datetime up to fourteen
days ahead, so an hourly heartbeat is more than enough lead time.

That is what buys minute-level accuracy without a trigger per schedule, and it is the same delegation
[0003](0003-a-controller-not-a-scheduler.md) is built around.

The full path, once:

```
Automation Schedule (hourly)
   └─▶ runbook: the controller
         ├─ read the catalogue        PM_ScheduleCatalog + PM_ScheduleCatalogCustom
         ├─ discover                  Resource Graph: every VM with the PowerSchedule tag, in scope
         ├─ resolve                   tag value → catalogue entry (+ snooze, freeze, exceptDates)
         ├─ observe                   power state, Stopped vs Deallocated
         ├─ decide                    what is due in the next hour           (pure, no Azure calls)
         ├─ guard                     armed? blast radius? dwell? protected?
         ├─ act                       submit to ComputeSchedule with exact times, else act directly
         └─ record                    every decision and every skip, to Log Analytics
```

Nothing about a machine is stored anywhere. Membership is recomputed from tags on every run, so a
machine created at 11:00 is managed at 12:00 and one deleted at 13:00 stops mattering at 14:00.

**A submitted action can be taken back.** `virtualMachinesCancelOperations` cancels a pending
operation by its id, so a snooze at 18:15 cancels the 18:30 deallocate that was submitted at 18:00.
The controller keeps the operation ids it submitted for exactly this reason — the API hands them back
and expects the caller to persist them.

**Where ComputeSchedule is not available**, the fallback acts directly at the top of the hour and
times round to the trigger. `Show-VmPowerScheduleCalendar` renders the *effective* times for the
tenant it is pointed at, so a 07:30 that will really happen at 08:00 says so instead of being a
surprise.

## Why

- **A trigger per catalogue entry means infrastructure churn for a business rule.** Adding a schedule
  would need Automation Account write from whoever is authoring, and the trigger set would drift from
  the catalogue the moment anyone edited one without the other.
- **An hourly heartbeat self-heals.** A missed run is corrected by the next one. A missed trigger in a
  trigger-per-time design is simply a missed action.
- **Recomputing membership every run is the whole point of tags.** There is no list to go stale.
- **The exact time is Azure's problem, not the runbook's.** Delegating it also removes the temptation
  to write a fifteen-minute polling loop.

## Rejected

**Four Automation Schedules fifteen minutes apart.** Microsoft's own suggestion. It quadruples the job
count on every account for a granularity that is still not exact, and 07:30 works only by luck of the
offsets.

**One Automation Schedule per distinct time in the catalogue.** Exact, and it makes the catalogue an
infrastructure concern. Authoring a schedule would need write on the Automation Account, which is a
much larger permission than editing a variable.

**A Logic App as the timer.** A whole resource, a connection and a bill, to do what a schedule already
does — and it does not solve the exact-time problem any better than delegation does.

**A Hybrid Runbook Worker with a cron.** Somebody else's virtual machine, running to decide whether
virtual machines should be running.

## Consequences

- The decision engine works on a **window**, not an instant: "what is due between now and now plus one
  hour". The window length comes from the trigger's interval so the two cannot disagree.
- Submitted operation ids have to be kept between runs, in the same store as the snoozes. Losing them
  means losing the ability to cancel, which is what makes a snooze work.
- Both catalogue variables must be **unencrypted** Automation variables. An encrypted variable does
  not return its value over ARM, and the workbook reads them through the Workbooks Azure Resource
  Manager data source, which is a plain GET. The catalogue is configuration, not a secret.
- That data source supports no `PUT` or `PATCH`, so the portal view of the catalogue is read-only by
  construction. Editing stays with the cmdlets, the deployment form and the v2 page — see
  [0005](0005-json-is-the-storage-format-not-the-authoring-format.md).
