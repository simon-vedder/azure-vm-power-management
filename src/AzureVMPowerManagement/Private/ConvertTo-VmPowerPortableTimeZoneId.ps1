function ConvertTo-VmPowerPortableTimeZoneId {
    <#
    .SYNOPSIS
    The form of a time zone id that resolves everywhere this tool runs.

    .DESCRIPTION
    Windows ids are that form. macOS and Linux ship ICU and resolve both, so a Windows id works
    there; the Azure Automation sandbox has no CLDR data at all and resolves only Windows ids. See
    ADR 0008.

    The conversion has to happen where ICU is - a laptop, or the deployment - because inside the
    sandbox an IANA id can only be rejected, never translated. So an id is normalised on the way
    into the catalogue rather than on the way out of it.

    An id that is already the Windows form, or one this platform cannot convert, comes back
    unchanged. Validation is Resolve-VmPowerTimeZone's job, not this one's.

    .PARAMETER Id
    A time zone id in either form.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    # Only an IANA id needs converting, and only a slash tells them apart reliably: Windows ids
    # never contain one, IANA ids outside the handful of legacy aliases always do.
    if ($Id -notmatch '/') { return $Id }

    $windows = ''
    if (-not [System.TimeZoneInfo]::TryConvertIanaIdToWindowsId($Id, [ref]$windows) -or -not $windows) {
        Write-Verbose "This platform cannot convert '$Id' to a Windows id; storing it as written."
        return $Id
    }

    try {
        $null = [System.TimeZoneInfo]::FindSystemTimeZoneById($windows)
        Write-Verbose "'$Id' stored as '$windows', which resolves in an Automation sandbox as well as here."
        $windows
    }
    catch {
        Write-Verbose "'$Id' converts to '$windows', which this platform cannot resolve; storing it as written."
        $Id
    }
}
