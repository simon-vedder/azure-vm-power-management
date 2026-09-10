@{
    RootModule           = 'AzureVMPowerManagement.psm1'
    ModuleVersion        = '0.1.2'
    CompatiblePSEditions = @('Core')
    GUID                 = '7914b234-b19b-463d-b50b-0c8298306fbf'
    Author               = 'Simon Vedder'
    CompanyName          = 'Simon Vedder'
    Copyright            = '(c) 2026 Simon Vedder. MIT License.'
    Description          = 'Decides which Azure VMs should be off, proves what that saved, and delegates the power operation to Azure.'
    PowerShellVersion    = '7.2'
    # Audit tools: Microsoft.Graph.Authentication and/or Az.Accounts + Az.Resources.
    # Automation tools: keep the minimums at the Az bundle the Azure Automation PowerShell 7.2
    # runtime ships (Az 11.2.0: Az.Accounts 2.15.0, Az.Compute 7.1.1, Az.Resources 6.13.0) and
    # import no Az modules into the Automation Account. A newer Az.Accounts next to the runtime's
    # bundle breaks assembly loading in the sandbox (observed 2026-09-05).
    # Resource Graph is called over REST through Invoke-AzRestMethod, so Az.ResourceGraph is
    # deliberately absent: one fewer module to import next to the runtime's bundle.
    RequiredModules      = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.15.0' }
        @{ ModuleName = 'Az.Compute'; ModuleVersion = '7.1.1' }
    )
    FunctionsToExport    = @(
        'Get-VmPowerPlan'
        'Get-VmPowerSchedule'
        'Invoke-VmPowerPlan'
        'New-VmPowerSchedule'
        'Remove-VmPowerSchedule'
        'Set-VmPowerSchedule'
        'Show-VmPowerScheduleCalendar'
        'Test-VmPowerSchedule'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/simon-vedder/azure-vm-power-management/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/simon-vedder/azure-vm-power-management'
            ReleaseNotes = 'https://github.com/simon-vedder/azure-vm-power-management/blob/main/CHANGELOG.md'
            Prerelease   = 'preview'
        }
    }
}
