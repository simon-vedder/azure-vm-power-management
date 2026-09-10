Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
# The report header and the generated script both show a version; read it from the manifest
# so there is one place to change it.
$script:ModuleVersion = [string](Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'AzureVMPowerManagement.psd1')).ModuleVersion

# Everything a user can see or depend on (type names, tag names, state values) is declared here,
# once. Changing one is a breaking change and goes through the CHANGELOG.
$script:TypeName = @{
    Plan       = 'AzureVMPowerManagement.VmPowerPlan'
    Result     = 'AzureVMPowerManagement.VmPowerPlanResult'
    Schedule   = 'AzureVMPowerManagement.VmPowerSchedule'
    Occurrence = 'AzureVMPowerManagement.VmPowerOccurrence'
    Validation = 'AzureVMPowerManagement.VmPowerScheduleValidation'
}

# A schedule name is also a tag value and an allowedValues entry in the generated policy, so it is
# constrained to what is safe in all three: lowercase, no spaces, no leading or trailing hyphen.
$script:ScheduleNamePattern = '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'

# One action type per entry, because that is how Microsoft.ComputeSchedule models a scheduled
# action. Hibernate is deliberately absent until it is tested against a machine that supports it.
$script:ScheduleActions = @('Start', 'Deallocate')

# Monday first: the working week is what these schedules are about.
$script:WeekDayNames = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')

# The two halves of the catalogue, and who owns each. The deployment overwrites the first on every
# run and never touches the second; Set-VmPowerSchedule writes only the second. See ADR 0005.
$script:CatalogVariable = @{
    Deployment = 'PM_ScheduleCatalog'
    Custom     = 'PM_ScheduleCatalogCustom'
}

$script:AutomationApiVersion = '2024-10-23'

$script:MonthNames = @(
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
)

# Power state as Resource Graph reports it, in the .code form. The .displayStatus form
# ('VM deallocated') is a string for a portal blade and is not compared against anywhere.
$script:PowerState = @{
    Running     = 'PowerState/running'
    Stopped     = 'PowerState/stopped'
    Deallocated = 'PowerState/deallocated'
}

# Something is already happening to a machine in one of these, so no rule acts on it.
$script:TransitionalPowerStates = @(
    'PowerState/starting'
    'PowerState/stopping'
    'PowerState/deallocating'
)

# Default tag keys. The deployment can override both; they are declared here so the module and
# the runbook cannot disagree about what opts a machine in.
$script:DefaultTag = @{
    Schedule  = 'PowerSchedule'
    Exclusion = 'PowerSchedule-Exclude'
}

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName
)
