<p align="center"><img src="docs/images/hero.png" alt="AzureVMPowerManagement: Tag a VM with the schedule it belongs to. The controller does the rest, and shows you what it did." width="100%"></p>

<p align="center">
  <a href="https://github.com/simon-vedder/azure-vm-power-management/actions/workflows/ci.yml"><img src="https://github.com/simon-vedder/azure-vm-power-management/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://www.powershellgallery.com/packages/AzureVMPowerManagement"><img src="https://img.shields.io/powershellgallery/v/AzureVMPowerManagement?include_prereleases&label=PowerShell%20Gallery" alt="PowerShell Gallery"></a>
  <img src="https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white" alt="PowerShell 7.2+">
  <img src="https://img.shields.io/badge/access-read--only%20by%20default-16a34a" alt="Read-only by default">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
</p>

**Tag a VM with the schedule it belongs to. The controller does the rest, and shows you what it did.**

Decides which Azure VMs should be off, proves what that saved, and delegates the power operation to Azure.

## Why

- What Microsoft ships for this, and where it stops.
- What the community has, and what it does not cover.
- The population this is for.

## Features

- **Read-only by default.** `Get-VmPowerPlan` needs read scopes only and returns objects, not a log.
- **Rules you can read.** Every decision is a pure function with a test on a fixture.
- **Remove with a safety net.** `Remove-VmPowerPlan` prompts per object, writes a JSON backup before
  it acts, and refuses anything marked protected.
- **Honest about limits.** [When not to use this](docs/when-not-to-use-this.md) and
  [KNOWN-ISSUES.md](KNOWN-ISSUES.md) list every sharp edge found.

## Quick start

```powershell
Install-Module AzureVMPowerManagement -AllowPrerelease

# 1. Look. Nothing changes.
Get-VmPowerPlan | Format-Table Name, Severity, Reason

# 2. Pick and remove, with a prompt per object and a backup file. -WhatIf shows the plan.
Get-VmPowerPlan -MinimumSeverity High | Remove-VmPowerPlan -WhatIf
Get-VmPowerPlan | Out-ConsoleGridView -PassThru | Remove-VmPowerPlan
```

## Safety

The tool proposes, you decide.
`Remove-VmPowerPlan` accepts only objects that `Get-VmPowerPlan` produced, asks before every object
(`ConfirmImpact = 'High'`), writes every object to a JSON file before the call, and reports
protected objects instead of touching them. `-WhatIf` works everywhere.

## Deploy the automation

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsimon-vedder%2Fazure-vm-power-management%2Fmain%2Fdeploy%2Fazuredeploy.json)

```bash
az deployment sub create -l westeurope -f deploy/main.bicep -p moduleVersion=0.1.0
```

One subscription-scope deployment creates an Automation Account with a system-assigned identity,
a least-privilege custom role, the module import from the PowerShell Gallery, the runbook and its
schedule, plus a Log Analytics workspace for job logs. Details in [deploy/README.md](deploy/README.md).

## Permissions

```
<exact Graph scopes or RBAC actions for the read path>
```

The write path adds `<...>` and is only requested with the switch that enables it.

## Status

Pre-release `0.1.0-preview`. What is verified is in [docs/verification.md](docs/verification.md);
what is not is in [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

## Documentation

- Tool page: [simonvedder.com/tools/vm-power-management](https://simonvedder.com/tools/vm-power-management)
- [Command reference](docs/commands) generated from the comment-based help
- [Verification log](docs/verification.md), [known issues](KNOWN-ISSUES.md), [when not to use this](docs/when-not-to-use-this.md)
- [Architecture decisions](docs/decisions), [releasing](docs/release.md), [contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md)

## License

MIT.
