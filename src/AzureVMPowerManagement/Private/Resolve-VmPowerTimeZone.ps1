function Resolve-VmPowerTimeZone {
    <#
    .SYNOPSIS
    A TimeZoneInfo for an id written in either form, whatever platform is asking.

    .DESCRIPTION
    Windows ids are the portable form, and that is not a preference - it is the only shape that
    works in both places a schedule lives.

    Measured with a probe runbook on 2026-09-10. The Azure Automation PowerShell 7.2 sandbox is
    Windows Server 2019, build 17763, which is version 1809 - older than the 1903 that first shipped
    ICU with Windows. .NET there runs in NLS mode (`GlobalizationMode.UseNls` is `True`), so the CLDR
    data is absent and **both** conversion directions return false:

        IANA->Windows Europe/Zurich    ok=False
        Windows->IANA W. Europe Standard Time  ok=False

    So `Europe/Zurich` cannot be translated inside a sandbox, only rejected. A Windows id resolves
    there, and also resolves on macOS and Linux, where .NET ships ICU and accepts both forms. That
    asymmetry decides the storage format: schedules keep Windows ids.

    This function still tries a translation, because on a machine with ICU it turns an IANA id into
    something the sandbox can use, which is what makes `New-VmPowerSchedule -TimeZone 'Europe/Zurich'`
    work at all.

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

    $hint = if ($Id -match '/') {
        "'$Id' is an IANA id. This runtime has no CLDR data to translate it - Azure Automation runs " +
        'on Windows Server 2019, where .NET falls back to NLS. Store the Windows form instead: ' +
        "New-VmPowerSchedule normalises it for you when it runs on a machine that can, so re-create " +
        'the schedule from a laptop rather than editing the variable by hand.'
    }
    else {
        "'$Id' is not a time zone this runtime knows, in either form."
    }
    throw "Time zone: $hint (platform: $([System.Environment]::OSVersion.VersionString))"
}
