# azure-vm-power-management

**Tag-driven start/stop for Azure VMs — schedule power by putting an `AutoShutdown` tag on the VM.**

An Azure Automation runbook decides, per VM and per hour, whether to start or stop it — based
entirely on tags. No per-VM schedules to maintain, no GUI, no lists to keep in sync. Tag a VM and
it's managed; remove the tag and it's not. Runs least-privilege via a System-Assigned identity and
a custom role scoped to exactly read + start + deallocate.

## How it works

The runbook runs **hourly**. Each run it looks at every VM carrying an `AutoShutdown` tag, works out
the target action for the current hour, and starts or stops accordingly. VMs without the tag are
ignored.

## Tag schema

| Tag | Example | Meaning |
|---|---|---|
| `AutoShutdown` | `8-18` | Start at 08:00, stop at 18:00 (24h). **Required** to manage the VM. |
| `AutoShutdown-TimeZone` | `W. Europe Standard Time` | Time zone the hours refer to. Falls back to the runbook's `TimeZone` param. |
| `AutoShutdown-SkipUntil` | `2026-08-01` | Skip this VM until the given date. |
| `AutoShutdown-ExcludeOn` | `2026-07-20` | Skip on this specific date only. |
| `AutoShutdown-ExcludeDays` | `Saturday,Sunday` | Skip on these weekdays. |

## Layout

```
runbook/VM-PowerManagement.ps1   # the tag-driven runbook (PowerShell 7.2, Managed Identity)
gui/PowerMate.ps1                # OPTIONAL end-user WPF GUI (source only) — see below
terraform/
  main.tf         # automation account, hourly schedule, runbook, least-privilege role + assignment
  gui.tf          # OPTIONAL identity + role for the on-VM GUI — delete for runbook-only
  variables.tf
  outputs.tf
  example-vm.tf   # OPTIONAL demo VM tagged with the schema — delete for a runbook-only deploy
```

## Deploy

```bash
cd terraform
terraform init
terraform apply -var="subscription_id=<your-sub-id>"
```

Then tag a VM (`AutoShutdown = "8-18"`) and it's picked up on the next hourly run. The included
`example-vm.tf` shows a correctly-tagged VM; if you keep it, supply `example_vm_admin_password` via a
tfvars file or Key Vault (never commit it), or delete the file for a runbook-only deployment.

## Permissions

The runbook authenticates as the Automation Account's System-Assigned identity. The Terraform grants
it a custom **VM Power Manager** role with only:

- `Microsoft.Compute/virtualMachines/read`
- `Microsoft.Compute/virtualMachines/start/action`
- `Microsoft.Compute/virtualMachines/deallocate/action`

**Multi-subscription:** the runbook loops every subscription the identity can see. To manage VMs
across subscriptions, assign the role to the identity at each target subscription — or at a
management group scope — not just the one it's deployed in.

## Optional: PowerMate GUI (`gui/PowerMate.ps1`)

A small WPF tool that runs **on a VM** and gives end-users self-service over that VM's schedule:
"Skip for Today" (sets `AutoShutdown-ExcludeOn`), "Clear Today Skip", and "Deallocate Now". It
authenticates via the VM's managed identity (`gui.tf` provisions a least-privilege one) and reads/writes
the VM's own tags. Shipped as **source only** — no compiled `.exe`; run it directly or compile with
PS2EXE yourself.

> **Adapted for V2.** PowerMate now reads the stop hour from the VM's `AutoShutdown` tag (e.g. `8-18`
> → 18:00) instead of a hard-coded time, shows the schedule, and treats a missing `AutoShutdown` tag as
> "not managed" (the old permanent-`AutoShutdown-Exclude` tag the runbook never read is gone). The
> "skip today" / "clear" / "deallocate" flows are unchanged. It's a WPF app that only runs on Windows —
> **test it on a Windows VM before publishing.**

## Requirements

- Azure Automation account with PowerShell 7.2 runtime and the Az modules available.
- Terraform + the `azurerm` provider.
- The optional GUI needs a Windows VM with a managed identity and access to IMDS (169.254.169.254).
