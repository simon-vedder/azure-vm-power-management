function ConvertTo-VmPowerHashtable {
    <#
    .SYNOPSIS
    One case-insensitive table out of whatever shape a schedule arrived in.

    .DESCRIPTION
    A schedule reaches the module as a hashtable from a fixture, a PSCustomObject from
    ConvertFrom-Json when it comes out of an Automation variable, or an ordered dictionary from
    someone building one by hand. Reading a key that is present but cased differently would mean
    quietly ignoring what somebody wrote, so every shape is flattened once, here.

    .PARAMETER InputObject
    The hashtable, dictionary or object to flatten. A missing key returns $null rather than throwing.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    $table = @{}
    # A plain @{} is already case-insensitive in PowerShell; this is the same behaviour made
    # explicit, because the whole point of this function is that casing must not matter.
    $result = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($null -eq $InputObject) { return $result }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in @($InputObject.Keys)) { $table[[string]$key] = $InputObject[$key] }
    }
    else {
        foreach ($property in @($InputObject.PSObject.Properties)) { $table[$property.Name] = $property.Value }
    }

    foreach ($key in $table.Keys) { $result[$key] = $table[$key] }
    $result
}
