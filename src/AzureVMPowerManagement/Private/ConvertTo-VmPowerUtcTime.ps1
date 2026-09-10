function ConvertTo-VmPowerUtcTime {
    <#
    .SYNOPSIS
    Read a timestamp as UTC, whether it arrived as a DateTime or as text.

    .DESCRIPTION
    The dwell store round-trips through an Automation variable, so a time written as a DateTime
    comes back as a string. Casting that back with [datetime] is the trap this module already
    documents: PowerShell converts '2026-09-10T18:00:00Z' to the local zone and labels it Local,
    and any code that then relabels it moves the value by the local offset without saying so.

    Parsed with RoundtripKind instead, so a Z keeps Kind Utc and an offset is honoured. A time with
    no zone at all is read as UTC rather than local, because everything that writes this store
    writes UTC. Reading it as local would move the dwell window by the local offset - and a safety
    guard that is quietly an hour out is worse than one that is switched off.

    .PARAMETER Value
    A DateTime, or a string in a round-trip format.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime() }

    $text = "$Value".Trim()
    if (-not $text) { throw 'Empty value where a timestamp was expected.' }

    $parsed = [datetime]::Parse(
        $text,
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    )
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) {
        $parsed = [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Utc)
    }
    $parsed.ToUniversalTime()
}
