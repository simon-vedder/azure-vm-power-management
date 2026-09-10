function Resolve-VmPowerNameList {
    <#
    .SYNOPSIS
    Turn a weekday or month list into the canonical names, or say which entry is wrong.

    .DESCRIPTION
    Accepts the same shapes Microsoft.ComputeSchedule does: a list of names, or the single value
    'All'. Matching is case-insensitive and 'All' expands to the full list, so what the engine
    reads is always an explicit list and no rule downstream has to remember the special case.

    An empty or absent value means All. That matches the ComputeSchedule schema, where an empty
    requestedDaysOfTheMonth means every day.

    .PARAMETER Value
    What the author wrote: a string, an array, 'All', or nothing.

    .PARAMETER Allowed
    The canonical names, in order.

    .PARAMETER Label
    Where this list came from, for the error message.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory)]
        [string[]]$Allowed,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $entries = @($Value | Where-Object { $null -ne $_ -and "$_" -ne '' })
    if (-not $entries.Count) { return $Allowed }
    if ($entries.Count -eq 1 -and "$($entries[0])" -eq 'All') { return $Allowed }

    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $entries) {
        $match = $Allowed | Where-Object { $_ -eq "$entry" } | Select-Object -First 1
        if (-not $match) {
            throw "'$entry' is not valid for $Label. Allowed: $($Allowed -join ', '), or All."
        }
        if (-not $resolved.Contains($match)) { $resolved.Add($match) }
    }

    # Sorted into the canonical order rather than the order somebody typed, so two schedules that
    # mean the same thing compare equal.
    @($Allowed | Where-Object { $resolved.Contains($_) })
}
