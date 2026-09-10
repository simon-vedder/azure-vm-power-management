# AzureVMPowerManagement command reference

Decides which Azure VMs should be off, proves what that saved, and delegates the power operation to Azure.

## Requirements

| | |
|---|---|
| Module version | 0.1.0-preview |
| PowerShell | 7.2+ (Core) |
| Required modules | none |
| Getting it | `Install-Module AzureVMPowerManagement`, or let the deployment pull it at the pinned version |

Per-command permissions are on each page under **Requirements and notes**.

## The runbook

What Azure Automation runs on the schedule.

| Script | What it does |
|---|---|
| [Invoke-AzureVMPowerManagementRunbook.ps1](Invoke-AzureVMPowerManagementRunbook.md) | Run AzureVMPowerManagement from an Azure Automation runbook |

## Module commands

The commands the runbook calls, and the same ones you can run locally after Install-Module.

| Command | What it does |
|---|---|
| [Get-VmPowerPlan](Get-VmPowerPlan.md) | Read-only discovery of VmPowerPlan findings. |
| [Remove-VmPowerPlan](Remove-VmPowerPlan.md) | Remove what a VmPowerPlan finding points at, after backing it up. |

---

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not these files.*
