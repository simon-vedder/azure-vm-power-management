@{
    Severity            = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules        = @(
        # Add a rule here only with a comment that says why. Examples from earlier tools:
        # 'PSAvoidUsingWriteHost'  - guest scripts stored as here-strings, reviewed as text
        # 'PSUseSingularNouns'     - "Facts" is the noun for a bundle of values
    )
    Rules               = @{
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space'; PipelineIndentation = 'IncreaseIndentationForFirstPipeline' }
        PSUseConsistentWhitespace  = @{ Enable = $true; CheckInnerBrace = $true; CheckOpenBrace = $true; CheckOpenParen = $true; CheckOperator = $true; CheckPipe = $true; CheckSeparator = $true; IgnoreAssignmentOperatorInsideHashTable = $true }
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true }
        PSPlaceCloseBrace          = @{ Enable = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true; NoEmptyLineBefore = $false }
        PSAvoidUsingCmdletAliases  = @{ Enable = $true }
    }
}
