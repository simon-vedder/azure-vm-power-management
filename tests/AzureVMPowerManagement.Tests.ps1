#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $manifestPath = Join-Path $PSScriptRoot '..' 'src' 'AzureVMPowerManagement' 'AzureVMPowerManagement.psd1'
    Import-Module $manifestPath -Force -ErrorAction Stop
    $module = Get-Module AzureVMPowerManagement

    # Private functions are fetched from the module scope once. Invoking the FunctionInfo runs the
    # body inside the module, so $script: variables resolve as they do in production.
    $Private = & $module {
        @{
            Resolve  = Get-Command Resolve-VmPowerPlanFinding
            Property = Get-Command Get-PropertyOrDefault
            Literal  = Get-Command ConvertTo-PowerShellLiteral
            Cleanup  = Get-Command Get-VmPowerPlanCleanupCommand
        }
    }

    function New-Raw {
        param([hashtable]$Override = @{})
        $raw = @{ Name = 'item-01'; IsPrivileged = $false; IsActive = $true; Protected = $false }
        foreach ($key in $Override.Keys) { $raw[$key] = $Override[$key] }
        [pscustomobject]$raw
    }
}

Describe 'Module' {
    BeforeDiscovery {
        $publicFolder = Join-Path $PSScriptRoot '..' 'src' 'AzureVMPowerManagement' 'Public'
        $publicFunctions = @(Get-ChildItem -Path $publicFolder -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        $stateChanging = @($publicFunctions | Where-Object { ($_ -split '-')[0] -in 'Remove', 'Set', 'New', 'Start', 'Stop', 'Restore', 'Update', 'Clear', 'Disable', 'Enable' })
    }

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions in Public/ and the manifest agrees' {
        $public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src' 'AzureVMPowerManagement' 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be $public
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be $public
    }

    It 'documents <_> with synopsis, description and an example' -ForEach $publicFunctions {
        $help = Get-Help -Name $_ -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It '<_> changes state, so it supports ShouldProcess' -ForEach $stateChanging {
        $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $_))
        $metadata.SupportsShouldProcess | Should -BeTrue
        if ($_ -like 'Remove-*') { $metadata.ConfirmImpact | Should -Be 'High' }
    }

    It 'keeps every source file free of control characters' {
        $files = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src') -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
        foreach ($file in $files) {
            (Get-Content -Path $file.FullName -Raw) | Should -Not -Match '[\x00-\x08\x0b\x0c\x0e-\x1f]' -Because "$($file.Name) must not carry stray control characters"
        }
    }
}

Describe 'Get-PropertyOrDefault' {
    It 'reads from a hashtable' { (& $Private.Property @{ A = 1 } 'A') | Should -Be 1 }
    It 'reads from an object' { (& $Private.Property ([pscustomobject]@{ A = 2 }) 'A') | Should -Be 2 }
    It 'falls back when the key is missing' { (& $Private.Property @{} 'A' -Default 'x') | Should -Be 'x' }
    It 'falls back on null input' { (& $Private.Property $null 'A' -Default 'x') | Should -Be 'x' }
}

Describe 'Resolve-VmPowerPlanFinding' {
    It 'rates privileged and unused as High' {
        $finding = & $Private.Resolve (New-Raw @{ IsPrivileged = $true; IsActive = $false })
        $finding.Severity | Should -Be 'High'
        $finding.PSObject.TypeNames[0] | Should -Be 'AzureVMPowerManagement.VmPowerPlan'
    }
    It 'rates privileged and active as Medium' { (& $Private.Resolve (New-Raw @{ IsPrivileged = $true })).Severity | Should -Be 'Medium' }
    It 'rates everything else as Info' { (& $Private.Resolve (New-Raw)).Severity | Should -Be 'Info' }
    It 'accepts hashtables' { (& $Private.Resolve @{ Name = 'h'; IsPrivileged = $true }).Name | Should -Be 'h' }
    It 'carries the Protected flag through' { (& $Private.Resolve (New-Raw @{ Protected = $true })).Protected | Should -BeTrue }
}

Describe 'Get-VmPowerPlan' {
    It 'takes pipeline input and returns typed findings' {
        $result = @((New-Raw), (New-Raw @{ Name = 'item-02'; IsPrivileged = $true }) | Get-VmPowerPlan)
        $result.Count | Should -Be 2
        $result[1].Severity | Should -Be 'Medium'
    }
    It 'filters on MinimumSeverity' {
        $result = @((New-Raw), (New-Raw @{ IsPrivileged = $true; IsActive = $false }) | Get-VmPowerPlan -MinimumSeverity High)
        $result.Count | Should -Be 1
        $result[0].Severity | Should -Be 'High'
    }
    It 'ignores null input' { @($null | Get-VmPowerPlan).Count | Should -Be 0 }
}

Describe 'Remove-VmPowerPlan' {
    BeforeEach {
        $backupPath = Join-Path $TestDrive 'backup.json'
        Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
    }

    It 'does nothing under -WhatIf and writes no backup' {
        $result = New-Raw @{ IsPrivileged = $true } | Get-VmPowerPlan | Remove-VmPowerPlan -BackupPath $backupPath -WhatIf
        $result.Result | Should -Be 'Skipped'
        Test-Path $backupPath | Should -BeFalse
    }

    It 'writes the backup before acting' {
        $result = New-Raw @{ Name = 'gone' ; IsPrivileged = $true } | Get-VmPowerPlan | Remove-VmPowerPlan -BackupPath $backupPath -Confirm:$false
        $result.Result | Should -Be 'Removed'
        @(Get-Content $backupPath -Raw | ConvertFrom-Json)[0].Name | Should -Be 'gone'
    }

    It 'never touches protected objects' {
        $result = New-Raw @{ Protected = $true; IsPrivileged = $true } | Get-VmPowerPlan | Remove-VmPowerPlan -BackupPath $backupPath -Confirm:$false -WarningAction SilentlyContinue
        $result.Result | Should -Be 'Skipped'
        $result.Reason | Should -Be 'Protected'
        Test-Path $backupPath | Should -BeFalse
    }

    It 'rejects objects that did not come from Get-VmPowerPlan' {
        { [pscustomobject]@{ Name = 'raw' } | Remove-VmPowerPlan -WhatIf -ErrorAction Stop } | Should -Throw
    }
}

Describe 'ConvertTo-PowerShellLiteral' {
    It 'doubles an apostrophe so the generated string cannot be broken out of' {
        (& $Private.Literal "O'Brien") | Should -Be "O''Brien"
    }
    It 'collapses newlines and tabs, so a generated command stays on one line' {
        (& $Private.Literal "a`r`nb`tc") | Should -Be 'a b c'
    }
    It 'returns an empty string for null' { (& $Private.Literal $null) | Should -Be '' }
}

Describe 'Get-VmPowerPlanCleanupCommand' {
    It 'produces a command that parses' {
        $command = & $Private.Cleanup (New-Raw)
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
    It 'escapes a name that would otherwise end the quoted string' {
        $command = & $Private.Cleanup (New-Raw @{ Name = "it's" })
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0
        $command | Should -BeLike "*it''s*"
    }
}

Describe 'Every finding carries what the report needs' {
    It 'has an id, a cleanup command and a reason when protected' {
        $finding = & $Private.Resolve (New-Raw @{ Protected = $true; IsPrivileged = $true })
        $finding.Id | Should -Not -BeNullOrEmpty
        $finding.CleanupPrimary | Should -Not -BeNullOrEmpty
        $finding.ProtectedReason | Should -Not -BeNullOrEmpty
    }
}
