function Remove-VmPowerPlan {
    <#
    .SYNOPSIS
    Remove what a VmPowerPlan finding points at, after backing it up.

    .DESCRIPTION
    Skeleton example of the write path every tool in this family shares:

      - accepts the objects Get-VmPowerPlan produced, never free-form names
      - writes a JSON backup of every object before touching it (-BackupPath)
      - SupportsShouldProcess with ConfirmImpact High: a prompt per object, -WhatIf everywhere
      - refuses objects marked Protected (break-glass, PIM-managed) and reports them instead

    The tool proposes, the administrator decides. Replace the body of the "act" block with the
    real Az or Graph call and keep everything around it.

    .PARAMETER InputObject
    Findings from Get-VmPowerPlan.

    .PARAMETER BackupPath
    JSON file that receives every object before it is removed.
    Default: ./AzureVMPowerManagement-backup-<timestamp>.json in the current directory.

    .EXAMPLE
    Get-VmPowerPlan -MinimumSeverity High | Remove-VmPowerPlan -WhatIf

    .EXAMPLE
    Get-VmPowerPlan | Out-ConsoleGridView -PassThru | Remove-VmPowerPlan

    .OUTPUTS
    AzureVMPowerManagement.VmPowerPlanRemoval

    .NOTES
    Required permissions: write. Name the exact scope or action here; the read path must not need it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('AzureVMPowerManagement.VmPowerPlanRemoval')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('AzureVMPowerManagement.VmPowerPlan')]
        [object[]]$InputObject,

        [Parameter()]
        [string]$BackupPath = (Join-Path (Get-Location) ('AzureVMPowerManagement-backup-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date)))
    )

    begin {
        $backup = [System.Collections.Generic.List[object]]::new()

        $removal = {
            param([string]$Name, [string]$Result, [string]$Reason)
            [pscustomobject]@{
                PSTypeName = $script:TypeName.Removal
                Name       = $Name
                Result     = $Result
                Reason     = $Reason
            }
        }
    }

    process {
        foreach ($item in $InputObject) {
            if ($item.Protected) {
                Write-Warning "$($item.Name): protected, not removed. Handle it by hand."
                & $removal -Name $item.Name -Result 'Skipped' -Reason 'Protected'
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($item.Name, 'Remove VmPowerPlan')) {
                & $removal -Name $item.Name -Result 'Skipped' -Reason 'Declined or -WhatIf'
                continue
            }

            # Backup first, always. The whole list is rewritten as a JSON array so the file is
            # complete even if the next call throws.
            $backup.Add($item.Source)
            ConvertTo-Json -InputObject @($backup) -Depth 10 | Set-Content -Path $BackupPath -Encoding utf8

            # act: replace with the real call, e.g. Remove-AzRoleAssignment or Remove-MgApplicationPassword.
            & $removal -Name $item.Name -Result 'Removed' -Reason 'Skeleton: no call was made'
        }
    }

    end {
        if ($backup.Count) { Write-Verbose "Backup of $($backup.Count) object(s): $BackupPath" }
    }
}
