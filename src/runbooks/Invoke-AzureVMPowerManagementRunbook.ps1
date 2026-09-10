<#
.SYNOPSIS
Run AzureVMPowerManagement from an Azure Automation runbook

.DESCRIPTION
Thin wrapper around the AzureVMPowerManagement module: signs in with the Automation Account's managed
identity, selects the subscription, discovers work through the module and either reports it or
applies it. The runbook knows the operation; the module knows the logic. Keep this file free of
rules.

All optional flags are [bool] instead of [switch] because the Automation "Start runbook" dialog
cannot populate switch parameters. -DryRun maps to -WhatIf on the module. Requires the
AzureVMPowerManagement module and Az.Accounts in the Automation Account's PowerShell 7.2+ runtime.

.PARAMETER SubscriptionId
The subscription to operate on. One per job.

.PARAMETER Mode
Report lists findings and changes nothing. Apply removes what the findings point at.

.PARAMETER ResourceGroupName
Restrict discovery to one resource group.

.PARAMETER DryRun
Apply mode only: run the module with -WhatIf.

.PARAMETER ManagedIdentityClientId
Client ID of a user-assigned managed identity. Leave empty for the system-assigned identity.

.EXAMPLE
.\Invoke-AzureVMPowerManagementRunbook.ps1 -SubscriptionId '<subscription id>' -Mode Report

.INPUTS
None

.OUTPUTS
AzureVMPowerManagement.VmPowerPlan or AzureVMPowerManagement.VmPowerPlanRemoval, one per item, plus a summary string

.NOTES
Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
RequiredPermissions: Managed identity with the custom role from deploy/main.bicep on the target scope.
Prerequisites:       Azure Automation PowerShell 7.2+ runtime; modules AzureVMPowerManagement, Az.Accounts

.LINK
https://github.com/simon-vedder/azure-vm-power-management
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateSet('Report', 'Apply')]
    [string]$Mode = 'Report',

    [Parameter()]
    [string]$ResourceGroupName,

    [Parameter()]
    [bool]$DryRun = $false,

    [Parameter()]
    [string]$ManagedIdentityClientId
)

$ErrorActionPreference = 'Stop'

Import-Module Az.Accounts -ErrorAction Stop
Import-Module AzureVMPowerManagement -ErrorAction Stop

$connect = @{ Identity = $true; ErrorAction = 'Stop' }
if ($ManagedIdentityClientId) { $connect['AccountId'] = $ManagedIdentityClientId.Trim() }
$null = Connect-AzAccount @connect
$context = Set-AzContext -SubscriptionId $SubscriptionId.Trim() -ErrorAction Stop
Write-Output "Subscription: $($context.Subscription.Name) | Mode: $Mode | Scope: $(if ($ResourceGroupName) { $ResourceGroupName } else { 'subscription' }) | DryRun: $DryRun"

# Discovery: replace with the module's real read path and its scope parameters.
$findings = @(Get-VmPowerPlan)
Write-Output "Findings: $($findings.Count)"

$summary = @{}
function Add-Summary { param([string]$Key) if ($summary.ContainsKey($Key)) { $summary[$Key]++ } else { $summary[$Key] = 1 } }

if ($Mode -eq 'Report') {
    foreach ($finding in $findings) {
        Write-Output "[$($finding.Name)] $($finding.Severity): $($finding.Reason)"
        Add-Summary $finding.Severity
        $finding
    }
}
else {
    foreach ($result in ($findings | Remove-VmPowerPlan -Confirm:$false -WhatIf:$DryRun)) {
        Write-Output "[$($result.Name)] $($result.Result): $($result.Reason)"
        Add-Summary $result.Result
        $result
    }
}

Write-Output ("Summary: " + $(if ($summary.Count) { ($summary.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ' } else { 'nothing to do' }))
