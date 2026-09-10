# 0008 — Store the Windows time zone id

**Status:** accepted · 2026-09-10 · amends [0002](0002-the-tag-names-a-schedule-it-does-not-contain-one.md)

## Context

[0002](0002-the-tag-names-a-schedule-it-does-not-contain-one.md) said a schedule keeps the time zone
id it was written with, and that both the Windows form and the IANA form resolve wherever this runs.
The second half was measured on a Mac and asserted about a platform nobody had looked at.

Two probe runbooks settled what is actually true. The Azure Automation PowerShell 7.2 sandbox is
**Windows Server 2019, build 17763** — version 1809, older than the 1903 that first shipped ICU with
Windows. .NET there runs in NLS mode:

```
OS                    : Microsoft Windows NT 10.0.17763.0
UseNls (kein ICU)     : True
IANA->Windows Europe/Zurich            ok=False
Windows->IANA W. Europe Standard Time  ok=False
```

So inside a sandbox an IANA id cannot be translated. It can only be rejected. `Europe/Zurich` does
not resolve, and neither does `Etc/UTC`.

The reverse is not symmetric. macOS and Linux ship ICU, resolve Windows ids directly, and can
convert in both directions. Three real runbook jobs failed on this before it was understood.

## Decision

A schedule stores the **Windows** id. `Europe/Zurich` becomes `W. Europe Standard Time` on the way
into the catalogue, `Etc/UTC` becomes `UTC`, and an id already in that form is left alone.

The conversion happens at authoring time, in `New-VmPowerSchedule`, because that is where ICU is.
Both forms are still accepted from a person: the point is that what reaches the catalogue is what
the runbook can read.

The catalogue that ships with the deployment uses Windows ids for the same reason — it is written
straight into an Automation variable without passing through the module.

## Why

- **It is the only form that works in both places.** A Windows id resolves in the sandbox and on a
  laptop. An IANA id resolves on a laptop only. There is no third option.
- **Translation has to happen where the data is.** Converting on read would be tidier, and the
  sandbox has nothing to convert with.
- **It costs the reader nothing.** `New-VmPowerSchedule -TimeZone 'Europe/Zurich'` still works, and
  says what it stored under `-Verbose`.

## Rejected

**Keep the id as written, translate on use.** What 0002 said, and what the sandbox cannot do.

**Ship a mapping table.** A curated IANA-to-Windows map would work inside a sandbox, and it is data
that has to be maintained against a moving target for no benefit over converting earlier.

**Require Windows ids from the author.** Correct and unfriendly. `Europe/Zurich` is the form most
people know, and rejecting it to save a conversion is the tool being awkward on purpose.

**Store both forms.** Two fields that can disagree, and a rule about which wins.

## Consequences

- `$schedule.TimeZone` is not always the string that was typed. `New-VmPowerSchedule` says so under
  `-Verbose`, and `Show-VmPowerScheduleCalendar` renders the same instants either way.
- A catalogue edited by hand in the portal with an IANA id will fail in the runbook, with a message
  that says to re-create the schedule from a machine that can convert it.
- Authoring from a platform without ICU stores the id unchanged, which then fails in the sandbox.
  That is a narrow case and it fails loudly rather than silently.
