# Reference: tags, state and the words in the output

Everything the controller reads to decide, everything it writes down, and what each value in a
plan means. If a value is not listed here, the controller does not read it.

## Where the state lives

Membership is **not stored**. It is recomputed from tags on every run, so a machine created at
11:00 is managed at 12:00 and one deleted at 13:00 stops mattering at 14:00. There is no list to
reconcile and none to go stale.

Three things are stored, all as Automation variables, all listed in
[deploy/README.md](../deploy/README.md):

- the settings the runbook reads, including whether it is armed
- the schedule catalogue, in two variables: one the deployment owns and overwrites, one only
  `Set-VmPowerSchedule` writes. A custom entry wins on a name collision, which is why a
  redeployment cannot eat your schedules
- `PM_LastActionAt`, what the runbook last acted on and when, which is what the dwell guard
  compares against

## Tags on the virtual machine

Read on every run, never written. Both names are defaults: the module takes `-ScheduleTag` and
`-ExclusionTag`, the deployment takes `scheduleTag` and `exclusionTag`, and the runbook reads
whichever names the deployment stored.

| Tag | Default name | What a value means |
|---|---|---|
| schedule | `PowerSchedule` | the **name** of a schedule in the catalogue, for example `office-hours-ch`. Not a schedule itself: see [ADR 0002](decisions/0002-the-tag-names-a-schedule-it-does-not-contain-one.md). A machine without this tag is never acted on by a schedule. A value naming a schedule that does not exist is reported as `ScheduleNotInCatalogue` rather than guessed at |
| exclusion | `PowerSchedule-Exclude` | present, whatever the value, and nothing touches the machine. Reported as `Excluded`. It wins over every schedule |

## Armed and disarmed

One switch, the Automation variable `PM_Armed`, false when the deployment lands.

- **disarmed** — the runbook discovers, decides, evaluates every guard and performs nothing. It
  is the same code path with `-WhatIf` on it, not a second one, so a blast radius set too low
  fails the job in week one rather than on the day you arm it.
- **armed** — the same path without the dry run.

A value that cannot be read as a boolean stops the run. A controller that cannot tell whether it
is armed has no business acting.

## Action

What would happen to the machine on an armed run. On a disarmed run the same value is computed
and nothing is performed.

| Value | Meaning |
|---|---|
| `None` | nothing. Either no rule applies, or a guard held the machine back |
| `Start` | the machine would be started |
| `Deallocate` | the machine would be deallocated, which is what stops the compute charge |

## Reason

One per branch of the decision, returned with `Explanation`, the same reason as a sentence.

| Value | Meaning |
|---|---|
| `StrandedButNotOnboarded` | switched off but still allocated on a host, so still billed, and carrying no schedule tag. Reported, not touched |
| `StoppedNotDeallocated` | the same state on a machine that does carry a tag. Deallocated |
| `InTransition` | Azure is already starting, stopping or deallocating it |
| `PowerStateUnknown` | Resource Graph returned no power state. Not knowing is not a reason to act |
| `Excluded` | the machine carries the exclusion tag |
| `MatchesSchedule` | already in the state its schedule wants at this time |
| `ShouldBeStopped` | its schedule has it down at this time and it is running |
| `ShouldBeRunning` | its schedule started machines minutes ago and this one is still deallocated, so the start did not take |
| `DownSinceTheStartWindow` | its schedule wants it up, but the start was long enough ago that somebody turned this machine off on purpose. See [ADR 0007](decisions/0007-start-only-while-the-start-is-recent.md) |
| `ScheduleStateUnknown` | the schedule has no action in the lookback window, so there is nothing to compare against |
| `ScheduleNotInCatalogue` | the tag names a schedule that does not exist |
| `NoRuleMatched` | no schedule, and nothing else applies |

These names are this module's own. Azure reports a power state and says nothing about intent.

## Power states this reads

From Resource Graph, `properties.extended.instanceView.powerState.code`. The code form is the
stable one.

| State | What it costs |
|---|---|
| `PowerState/running` | compute and storage |
| `PowerState/stopped` | compute and storage. Off, still allocated on a host, still billed |
| `PowerState/deallocated` | storage only |
| `PowerState/starting`, `/stopping`, `/deallocating` | treated as `InTransition`; nothing acts on a machine mid-move |
