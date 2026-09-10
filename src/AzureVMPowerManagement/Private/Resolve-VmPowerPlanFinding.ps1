function Resolve-VmPowerPlanFinding {
    <#
    .SYNOPSIS
    Pure decision function: raw facts in, one typed finding out.
    .DESCRIPTION
    Skeleton rule set. Every rule the tool applies lives in functions like this one, with no
    Azure or Graph call inside, so Pester can prove each rule on fixtures. Replace the rules,
    keep the shape: input object, output object with PSTypeName, Severity and Reason.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerPlan')]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $name = [string](Get-PropertyOrDefault -InputObject $InputObject -Name 'Name' -Default '(unnamed)')
    $isPrivileged = [bool](Get-PropertyOrDefault -InputObject $InputObject -Name 'IsPrivileged' -Default $false)
    $isActive = [bool](Get-PropertyOrDefault -InputObject $InputObject -Name 'IsActive' -Default $true)
    $protected = [bool](Get-PropertyOrDefault -InputObject $InputObject -Name 'Protected' -Default $false)

    $severity, $reason = switch ($true) {
        ($isPrivileged -and -not $isActive) { 'High', 'Privileged and unused'; break }
        ($isPrivileged) { 'Medium', 'Privileged and in use'; break }
        default { 'Info', 'Not privileged' }
    }

    # A stable id per finding, so the report can address a row and a second run can be diffed
    # against the first. Derive it from what identifies the thing, never from the row order.
    $id = [string](Get-PropertyOrDefault -InputObject $InputObject -Name 'Id' -Default $name)

    $finding = [pscustomobject]@{
        PSTypeName      = $script:TypeName.Finding
        Id              = $id
        Name            = $name
        Severity        = $severity
        Reason          = $reason
        Protected       = $protected
        ProtectedReason = if ($protected) { 'Protected by rule' } else { '' }
        CleanupPrimary  = ''
        Source          = $InputObject
    }
    # Protected findings still show their command, with the reason: a tool that refuses and
    # explains is more use than one that refuses and hides.
    $finding.CleanupPrimary = Get-VmPowerPlanCleanupCommand -InputObject $InputObject
    $finding
}
