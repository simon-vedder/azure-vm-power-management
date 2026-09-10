# 0001 — A PowerShell Gallery module, because a runbook imports one

**Status:** accepted · 2026

## Context

AzureVMPowerManagement runs unattended inside a customer's tenant on a schedule. The deployment is Bicep:
an Automation Account, a managed identity, a custom role and a thin runbook.

A runbook does not download a file and run it. It imports modules, and an Automation Account
resolves them from the PowerShell Gallery at a pinned version. That is the mechanism, and it decides
the packaging before anyone's taste does.

## Decision

The logic is a module, `AzureVMPowerManagement`, one function per file, published to the PowerShell Gallery.
Rules are pure functions in `Private/` and are proven on fixtures. The runbook in `src/runbooks/` is
a thin wrapper: sign in with the managed identity, resolve scope, call the module, summarise.

`deploy/main.bicep` points `moduleVersion` at a published version, so a deployment is reproducible
and an upgrade is a parameter change rather than a copy of new code into someone's tenant.

## Why not a single downloadable script

That is the right answer for the other construct in this family, an audit a person runs once or
twice on their own machine: no install, nothing to trust, readable before it runs. See the audit
skeleton's `0001-the-report-is-the-product.md`.

It is the wrong answer here. Nobody is standing at a prompt to run this, there is no first thirty
seconds to protect, and the thing that consumes it is a runbook that speaks Gallery modules. A
flattened script would need its own copy-into-the-tenant story and a second artefact to keep in
sync, for no gain.

## Consequences

- PowerShell 7.2+ only.
- Semantic versioning from the first release; the tag must match the manifest.
- The Gallery API key is scoped to this package and expires yearly. A missed rotation fails the
  next release, so the expiry date belongs in `docs/release.md` and in a reminder.
- Local use still works (`Install-Module AzureVMPowerManagement`, sign in, `Get-VmPowerPlan`), which is how
  anyone tries it before deploying it. It is a side effect of the packaging, not the reason for it.
