# AzureVMPowerManagement command reference

Decides which Azure VMs should be off, proves what that saved, and delegates the power operation to Azure.

## Requirements

| | |
|---|---|
| Module version | 0.1.0-preview |
| PowerShell | 7.2+ (Core) |
| Required modules | `Az.Accounts` 2.15.0+, `Az.Compute` 7.1.1+ |
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
| [Get-VmPowerPlan](Get-VmPowerPlan.md) | Work out what should happen to the virtual machines in scope, and change nothing |
| [Invoke-VmPowerPlan](Invoke-VmPowerPlan.md) | Carry out a plan, after the guards agree to it |
| [New-VmPowerSchedule](New-VmPowerSchedule.md) | Build a schedule from parameters instead of writing the JSON by hand |
| [Show-VmPowerScheduleCalendar](Show-VmPowerScheduleCalendar.md) | Print the next few days of a schedule, so a mistake is something you read rather than survive |
| [Test-VmPowerSchedule](Test-VmPowerSchedule.md) | Check a schedule or a whole catalogue, and report what is wrong rather than throwing |

---

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not these files.*
