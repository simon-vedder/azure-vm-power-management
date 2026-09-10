function ConvertTo-PowerShellLiteral {
    <#
    .SYNOPSIS
    Escape a value for interpolation into a single-quoted PowerShell string.
    .DESCRIPTION
    Every generated command carries values that came from an API: display names with apostrophes,
    descriptions with newlines. Pasted into a single-quoted string unescaped, an apostrophe ends the
    string and the rest of the line becomes code. Doubling it is the whole fix, and collapsing
    whitespace keeps a generated command on one line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not $Value) { return '' }
    return ($Value -replace '[\r\n\t]+', ' ').Replace("'", "''")
}
