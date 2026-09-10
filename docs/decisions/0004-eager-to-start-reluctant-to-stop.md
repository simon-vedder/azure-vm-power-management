# 0004 — Eager to start, reluctant to stop

**Status:** accepted · 2026-09-10

## Context

The two ways this tool can be wrong are not equally bad.

Failing to start a machine costs somebody an hour and an annoyed message. Wrongly stopping one costs
an outage that somebody else has to explain to somebody else again. The licence disclaims warranty,
and Swiss law will not let liability for intent or gross negligence be excluded in advance anyway, so
the protection has to be in the design rather than in the text.

There is also a category of action with no downside at all, and it was not in the first version.
A machine shut down from inside the guest sits in `Stopped` — allocated on a host, not running, and
**still billed for compute**. Only `Deallocated` stops the meter. Microsoft's own FinOps guidance
says to avoid stopping machines without deallocating them, and offers nothing in the platform that
fixes it.

## Decision

The controller treats starting and stopping as different kinds of act, and ships the risk-free action
first.

**Asymmetric confidence.** When a signal is missing or ambiguous, start. Never stop on an assumption.
A machine whose schedule cannot be resolved, whose tag does not parse, or whose state cannot be read
is reported and left alone — and if it is deallocated during a window that says it should be up, it
is started.

**Never `Stop`, always `Deallocate`,** and always with a graceful OS shutdown. Force is an explicit
opt-in per run, never a default. Stopping without deallocating is the bug this tool exists to fix; it
would be absurd to cause it.

**Disarmed by default.** The deployment ships with acting turned off. It discovers, decides, records
everything and does nothing. You read a week of the workbook, then arm it. Same shape as `CR_DryRun`
in the credential rotation tool, and for the same reason: the first run on a real estate always finds
something the author did not expect.

**Opt-in, never opt-out.** No tag, never touched. There is no switch that means "manage everything in
this subscription". A machine nobody has thought about is a machine this tool does not act on.

**Blast radius cap.** A run that would deallocate more than a configured number of machines, or more
than a configured share of the onboarded estate, performs none of them and says why. A bad catalogue
edit or a mistaken policy assignment cannot take an environment down; it produces a loud report.

**Protected markers beat everything.** An exclusion tag or an open freeze window wins over any
schedule, including a manual run.

**Minimum dwell.** Since 1 June 2025 Azure bills a five-minute minimum per machine start, so a
flapping schedule costs real money on top of being wrong. The controller refuses to act on a machine
it moved within the schedule's `minimumDwellMinutes`.

**Every skip is recorded with its reason.** "Why didn't it stop last night" must be answerable from
the workbook without reading code.

**The risk-free feature ships first.** Detecting machines in `Stopped` rather than `Deallocated`, and
deallocating them, needs no schedule, no catalogue and no trust: the machine is already powered off,
so nothing that was running stops running. It is the first thing built and the first thing that can
be armed.

## Why

- The costs of the two error directions differ by orders of magnitude, so the confidence thresholds
  should differ too.
- A disarmed first week converts "trust this tool" into "read what it would have done", which is the
  only honest way to ask somebody to point it at their estate.
- A blast radius cap turns the worst plausible mistake — a wrong catalogue entry applied broadly —
  from an incident into a report.
- Leading with the `Stopped` detector means the tool proves its value before it is ever allowed to
  interrupt anything.

## Rejected

**A confirmation prompt per machine.** Correct for an interactive audit tool, meaningless in a runbook
that nobody is watching.

**Trusting the schedule and reporting exceptions afterwards.** That is the design that produces the
outage this decision exists to prevent.

**Shipping armed with good defaults.** There are no good defaults for somebody else's estate.

## Consequences

- The deployment carries `armed`, a blast-radius number and a share, and the runbook refuses to act
  without them being explicit.
- Two code paths must produce the same plan, so the plan is computed once and consumed twice. This is
  the reason the decision step is pure — see [0003](0003-a-controller-not-a-scheduler.md).
- `docs/when-not-to-use-this.md` names the exclusions plainly: domain controllers, anything with a
  quorum, anything with a licence check on boot, anything under a customer SLA. This is a tool for
  development and test estates. Saying so is the strongest control in this document.
- The workbook needs a skips-with-reasons view as a first-class panel, not a footnote.
