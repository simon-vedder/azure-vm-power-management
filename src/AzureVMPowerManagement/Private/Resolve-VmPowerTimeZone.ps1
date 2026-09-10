function Resolve-VmPowerTimeZone {
    <#
    .SYNOPSIS
    A TimeZoneInfo for an id written in either form, whatever platform is asking.

    .DESCRIPTION
    A schedule is authored on somebody's laptop and resolved inside an Azure Automation sandbox, and
    those are not the same operating system. Measured on 2026-09-10 by running a probe runbook: the
    PowerShell 7.2 sandbox is **Windows Server 2019**, not Linux, and it carries 141 time zones - all
    of them Windows ids. `Europe/Zurich` does not resolve there. Neither does `Etc/UTC`. On macOS and
    Linux the reverse is true for ids like `W. Europe Standard Time` on older runtimes.

    So the id is not normalised when a schedule is stored - it stays as it was written - and is
    translated here, at the moment it is used. .NET 6 carries the CLDR mapping both ways, which is
    what makes a catalogue portable between the two.

    An earlier version of this project claimed both forms resolved in the sandbox. That was measured
    on a Mac and generalised, and the first real runbook job disproved it.

    .PARAMETER Id
    A time zone id in the Windows form ('W. Europe Standard Time') or the IANA form
    ('Europe/Zurich').
    #>
    [CmdletBinding()]
    [OutputType([System.TimeZoneInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($Id) }
    catch { Write-Verbose "Time zone '$Id' is not known to this platform as written; trying the other form." }

    # Not resolvable as written. Try the other form - IANA to Windows in a sandbox, Windows to IANA
    # on a laptop - and say which translation worked, because a silent one is hard to debug later.
    $translated = ''
    if ([System.TimeZoneInfo]::TryConvertIanaIdToWindowsId($Id, [ref]$translated) -and $translated) {
        try {
            $zone = [System.TimeZoneInfo]::FindSystemTimeZoneById($translated)
            Write-Verbose "Time zone '$Id' resolved as '$translated' on this platform."
            return $zone
        }
        catch { Write-Verbose "'$translated' is not known here either." }
    }

    $translated = ''
    if ([System.TimeZoneInfo]::TryConvertWindowsIdToIanaId($Id, [ref]$translated) -and $translated) {
        try {
            $zone = [System.TimeZoneInfo]::FindSystemTimeZoneById($translated)
            Write-Verbose "Time zone '$Id' resolved as '$translated' on this platform."
            return $zone
        }
        catch { Write-Verbose "'$translated' is not known here either." }
    }

    throw ("The time zone '$Id' cannot be resolved on this platform ($([System.Environment]::OSVersion.VersionString)), " +
        'in either the Windows or the IANA form. Azure Automation runs PowerShell 7.2 on Windows Server, ' +
        "which knows ids like 'W. Europe Standard Time'; a Mac or Linux machine knows 'Europe/Zurich'. " +
        'Both are accepted and translated, so this id is wrong rather than in the wrong form.')
}
