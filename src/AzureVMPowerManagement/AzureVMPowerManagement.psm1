Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
# The report header and the generated script both show a version; read it from the manifest
# so there is one place to change it.
$script:ModuleVersion = [string](Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'AzureVMPowerManagement.psd1')).ModuleVersion

# Everything a user can see or depend on (type names, tag names, state values) is declared here,
# once. Changing one is a breaking change and goes through the CHANGELOG.
$script:TypeName = @{
    Finding = 'AzureVMPowerManagement.VmPowerPlan'
    Removal = 'AzureVMPowerManagement.VmPowerPlanRemoval'
}

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName
)
