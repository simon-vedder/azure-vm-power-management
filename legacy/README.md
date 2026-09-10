# legacy/ — the tag-driven version

This is the tool as it ran in production before the controller rebuild, moved here rather than
deleted. It works. Nothing in the rest of this repository replaces it until the rebuild has proved
itself inside Azure Automation, and this folder is the fallback until then.

Also reachable as the git tag `legacy/tag-driven`, which is a permanent pointer to the last commit
where these files were the product.

| Path | What it is |
|---|---|
| `runbook/VM-PowerManagement.ps1` | The hourly runbook. Reads `AutoShutdown` and four modifier tags off each machine and starts or stops it. |
| `arm/deploy.json` | Self-contained ARM template: Automation Account, identity, custom role. |
| `terraform/` | The same thing in Terraform, plus an example VM and the GUI identity. |
| `gui/PowerMate.ps1` | Optional WPF interface for the person using the machine. Windows only. |

## How to run it

Unchanged from before. The ARM template is self-contained:

```
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimon-vedder%2Fazure-vm-power-management%2Fmain%2Flegacy%2Farm%2Fdeploy.json
```

or `terraform apply` in `legacy/terraform/`.

## Why it was replaced

Not because it was broken. Azure grew its own scheduler — `Microsoft.ComputeSchedule` performs
batched start and deallocate with throttling and retries handled — so an hourly loop calling
`Start-AzVM` became the least valuable part of the tool. The rebuild keeps intent, safety and
evidence and hands execution to Azure. The reasoning is in
[docs/decisions/0003](../docs/decisions/0003-a-controller-not-a-scheduler.md).

Two differences matter if you are choosing between them:

- **Tags.** Here the schedule lives *in* five tags per machine. In the rebuild a tag names a
  schedule that lives in a catalogue, so one edit fixes every machine that follows it and a policy
  can enforce the value. See [ADR 0002](../docs/decisions/0002-the-tag-names-a-schedule-it-does-not-contain-one.md).
- **The stranded machine.** This version does not look for machines in `PowerState/stopped` —
  powered off but still allocated, and still billed for compute. The rebuild does, and that is the
  feature with no downtime risk at all.

## When this folder goes

When the rebuild has run a full loop inside a real Automation Account and a month of its workbook has
been boring. The tag stays either way.
