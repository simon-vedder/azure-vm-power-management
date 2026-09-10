# 0007 — Start only while the start is recent

**Status:** accepted · 2026-09-10

## Context

[0003](0003-a-controller-not-a-scheduler.md) made the decision engine work from a desired state
rather than from events, and gave a good reason: a machine that should have started at 07:30 and did
not is still supposed to be running at 09:00, and an engine that only asked "what is due in the next
hour" would leave it down all day.

[0004](0004-eager-to-start-reluctant-to-stop.md) then said the stranded rule beats the schedule,
because somebody who shut a machine down from inside the guest should not be fought — and added
that "the next scheduled start brings it back if the schedule says so".

Those two sentences are incompatible, and the first real run showed it. Measured in the lab on
2026-09-10:

1. A machine tagged `office-hours-ch` was shut down from inside the guest at 16:00 local, inside its
   window. It sat in `PowerState/stopped`, billed for compute.
2. The controller deallocated it. Correct: nothing was running, and the bill stopped.
3. On the very next plan, the schedule still wanted machines up, the machine was deallocated, and
   the controller decided to **start it again**.

With a backwards-looking desired state, "the next scheduled start" is not tomorrow morning. It is
immediately. The net effect of somebody shutting a machine down would have been that the tool
rebooted it, which is precisely the surprise 0004 exists to prevent.

## Decision

A machine is started only while the schedule's start is recent. Each schedule carries
`startGraceMinutes`, defaulting to 120.

- Inside the grace, a machine that is down is a start that did not take. Start it.
- Outside it, a machine that is down was turned off by somebody. Leave it, and say so:
  `DownSinceTheStartWindow`.

Stopping keeps no such window. A machine still running outside its hours is the thing this tool
exists to find, whatever the reason it is up, and the exclusion tag is how somebody says otherwise.

`Get-VmPowerScheduleState` therefore returns the state *and* how long it has held, rather than the
state alone. The age was always the missing half of the question.

## Why

- **The asymmetry in 0004 survives, but on the right axis.** Eager to start was never meant to mean
  "override every manual shutdown"; it meant "when a signal is ambiguous, prefer the harmless
  direction". Six hours after a scheduled start, a machine that is down is not an ambiguous signal.
- **It keeps the reason 0003 gave for looking backwards.** A start that failed at 07:30 is retried
  until 09:30, which is the case that motivated the design.
- **It is one number, per schedule, with a defensible default.** Two hours is long enough for a
  transient failure and a retry, short enough that an afternoon shutdown stands.
- **The alternative needs state this tool does not have.** Telling "we tried and it did not work"
  from "a human turned it off" properly would mean remembering what we attempted. The ledger will
  make that possible later; the grace is the honest approximation until then.

## Rejected

**Start whenever the schedule wants the machine up.** What was implemented, and what the lab caught.
It makes the tool undo deliberate shutdowns, and pairs badly with the stranded rule: shut a machine
down and the controller deallocates it and then starts it, so the visible result of turning a
machine off is that it reboots.

**Never start a machine at all.** Tempting, and it loses the case that justified the desired-state
design. A schedule that only ever stops machines is a schedule somebody has to un-stop by hand every
morning.

**Only start machines this tool deallocated.** The right answer, and it needs the ledger. When
decisions are recorded and read back, this becomes a better rule than a time window and the grace
can go.

## Consequences

- `startGraceMinutes` joins the schedule model, and `Get-VmPowerScheduleState` returns an object
  rather than a string. Callers read `.State` and `.MinutesSince`.
- A machine deliberately shut down inside its window is deallocated once and then left alone, which
  is the behaviour to describe in the README: the tool stops paying for it, it does not restart it.
- `DownSinceTheStartWindow` will be a common line in the workbook on any estate where people turn
  machines off. That is information, not noise: it is the list of machines nobody has re-tagged.
- When the ledger lands, revisit this. A rule that knows what it attempted beats a rule that guesses
  from the clock.
