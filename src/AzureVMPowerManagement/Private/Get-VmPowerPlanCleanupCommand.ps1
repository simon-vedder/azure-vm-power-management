function Get-VmPowerPlanCleanupCommand {
    <#
    .SYNOPSIS
    Pure rule: the native command that fixes one finding.
    .DESCRIPTION
    The command is Microsoft's own, not this tool's. Once you know what to change, the change is one
    cmdlet or one Graph call that ships in the box; what was missing was knowing which object and
    whether touching it is safe. So the report hands over the real command, filled in, for a person
    to read before running.

    Nothing executes these strings. Replace the body with the command your tool's findings need,
    and put one example of each shape in a fixture.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $name = ConvertTo-PowerShellLiteral -Value ([string](Get-PropertyOrDefault -InputObject $InputObject -Name 'Name' -Default ''))
    return "Remove-Something -Name '$name' -WhatIf"
}
