# 0003 — A controller, not a scheduler

**Status:** accepted · 2026-09-10

## Context

This repository shipped an hourly runbook that read tags, worked out the target state for the current
hour, and called `Start-AzVM` or `Stop-AzVM`. That was a reasonable thing to build in 2025.

Azure has since built the same thing, better. `Microsoft.ComputeSchedule` takes a batch of machines
and a time and performs Start, Deallocate or Hibernate on them. It handles subscription throttling,
retries transient errors, and adapts as Azure raises its own limits — 100 machines per call, up to
5000 per action, up to 14 days ahead. There is also a recurring `scheduledActions` resource in the
ARM, Bicep and Terraform schemas carrying weekdays, days of the month, months, a time, a time zone,
a validity window and notification settings.

Measured in the Testing subscription on 2026-09-10:

- The provider is present in every region. After registering it, the one-off batch API answers —
  a status call for a fabricated operation id returns `OperationNotFound`, which is the endpoint
  working.
- `scheduledActions` does **not** resolve at any API version, registered provider or not. Two
  features exist and are unregistered: `ComputeSchedulePreview` and `DefaultFeature`.

So the recurring resource is not yet something a normal tenant can use, and the batch API is.

Rebuilding the hourly loop as it stands would ship a worse copy of a first-party feature.

## Decision

This tool stops being a scheduler and becomes a controller. It owns intent, membership, safety and
evidence. It does not own the power operation.

Every run does seven things, and only the sixth touches a machine:

1. **Discover** — one Azure Resource Graph query across every onboarded scope, all subscriptions at
   once.
2. **Resolve intent** — tag to named schedule, then overrides: snooze, freeze window, exception date.
3. **Observe** — current power state, including the difference between `Stopped` and `Deallocated`.
4. **Decide** — desired against actual, producing a plan. **Pure functions, no Azure calls.**
5. **Guard** — blast radius, protected markers, freeze windows, minimum dwell.
6. **Act** — hand the plan to the ComputeSchedule batch API where the provider is registered,
   otherwise fall back to `Start-AzVM` and `Stop-AzVM -Force` per machine.
7. **Record** — every decision, *including every skip and its reason*, to Log Analytics.

Step 4 is the line between a script and a tool: it is testable on fixtures, and it produces the dry
run for free rather than as a separate code path that drifts.

Step 6 is deliberately pluggable. Today the fallback carries most tenants. As `scheduledActions`
becomes generally available, the controller delegates more and owns less.

## Why

- **Microsoft owns execution; nobody owns intent.** Scheduled Actions takes a list of resource IDs.
  Nothing keeps that list right as machines are created, destroyed, moved or retagged. That gap is
  structural, not a missing feature.
- **The failure modes that matter are not scheduling failures.** They are: stopping a machine somebody
  was using, stopping more machines than intended, and not being able to explain either afterwards.
  None of those are solved by a better loop.
- **Delegating the hard part removes the code most likely to be wrong.** Throttling and retry logic
  against the compute API is exactly the sort of thing that looks fine in a lab and falls over on an
  estate of a thousand machines.
- **A pure decision step makes the dry run honest.** The armed and disarmed paths compute the same
  plan; only step 6 differs.

## Rejected

**Keep the loop, ignore ComputeSchedule.** Means owning throttling and retries forever, and
competing with a first-party feature that is free and improving.

**Go all-in on `scheduledActions` now.** It does not resolve in a normal subscription today. Building
on it would mean the tool does not work.

**Become a thin wrapper that only creates scheduled actions.** That is a Bicep module, not a tool,
and it solves none of the six problems that actually hurt.

## Consequences

- The module needs an execution abstraction with two implementations behind it, and a capability
  probe that decides which one a tenant gets.
- The decision engine has no Azure dependency and is proven on fixtures, so the test suite is worth
  reading.
- The value proposition moves from "it turns machines off on a schedule" to "it knows which machines
  should be off, and can prove what that saved". That changes the README, the tool page and the
  workbook more than it changes the code.
- One feature needs no schedule at all and should ship first: finding machines in `Stopped`
  (allocated) rather than `Deallocated`. Those are billed for compute and are already powered off, so
  deallocating them is money at zero downtime risk. See [0004](0004-eager-to-start-reluctant-to-stop.md).
