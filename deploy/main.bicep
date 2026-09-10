// Subscription-scope deployment of the automation: resource group, Automation Account with a
// system-assigned identity, the least-privilege role it needs, Log Analytics, module import,
// runbook and schedule. Subscription scope because a custom role definition lives there.
//
//   az deployment sub create -l westeurope -f deploy/main.bicep -p moduleVersion=0.1.0
//
// Nothing changes state by itself: the schedule runs the runbook in Report mode until you
// redeploy with mode=Apply.
targetScope = 'subscription'

@description('Region for the resource group and everything in it.')
param location string = 'westeurope'

param resourceGroupName string = 'rg-vm-power-management-weu'
param automationAccountName string = 'aa-vm-power-management-weu'
param logAnalyticsWorkspaceName string = 'log-vm-power-management-weu'

@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('AzureVMPowerManagement module version on the PowerShell Gallery.')
param moduleVersion string

@description('Version stamp written to the module and runbook content links, System.Version form (up to four numeric parts, e.g. 0.1.0.1). Defaults to moduleVersion; bump it to force Automation to re-import unchanged URIs.')
@minLength(0)
param contentVersion string = ''

@description('Override the module package source, for example a GitHub release asset. Empty means the Gallery URL for moduleVersion.')
param modulePackageUri string = ''

@description('Raw URL of the runbook wrapper. Pin to a tag in production.')
param runbookContentUri string = 'https://raw.githubusercontent.com/simon-vedder/azure-vm-power-management/main/src/runbooks/Invoke-AzureVMPowerManagementRunbook.ps1'

@description('Resource group the identity gets the operator role on. Empty assigns the role at subscription scope.')
param targetResourceGroupName string = ''

@description('Runbook mode for the scheduled job: Report changes nothing, Apply removes findings.')
@allowed(['Report', 'Apply'])
param mode string = 'Report'

@minValue(15)
@maxValue(1440)
param intervalMinutes int = 60

@description('First run of the schedule, ISO 8601. Must be at least five minutes in the future; defaults to one hour from deployment.')
param scheduleStartTime string = dateTimeAdd(baseTime, 'PT1H')

param scheduleTimeZone string = 'Etc/UTC'

param roleName string = 'AzureVMPowerManagement Operator'

@description('Exactly the actions the runbook needs. Reader is usually not enough and Contributor is always too much.')
param roleActions array = [
  'Microsoft.Resources/subscriptions/read'
  'Microsoft.Resources/subscriptions/resourceGroups/read'
]

param tags object = {
  Project: 'azure-vm-power-management'
}

param baseTime string = utcNow()

var effectiveModuleUri = empty(modulePackageUri)
  ? 'https://www.powershellgallery.com/api/v2/package/AzureVMPowerManagement/${moduleVersion}'
  : modulePackageUri

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module automation 'modules/automation.bicep' = {
  name: 'automation'
  scope: resourceGroup
  params: {
    location: location
    automationAccountName: automationAccountName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logRetentionDays: logRetentionDays
    tags: tags
    modulePackageUri: effectiveModuleUri
    runbookContentUri: runbookContentUri
    contentVersion: empty(contentVersion) ? moduleVersion : contentVersion
    subscriptionIdForJobs: subscription().subscriptionId
    mode: mode
    intervalMinutes: intervalMinutes
    scheduleStartTime: scheduleStartTime
    scheduleTimeZone: scheduleTimeZone
  }
}

resource operatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, roleName)
  properties: {
    roleName: roleName
    description: 'Exactly what the AzureVMPowerManagement runbook calls, nothing else.'
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: roleActions
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

module assignAtSubscription 'modules/role-assignment-subscription.bicep' = if (empty(targetResourceGroupName)) {
  name: 'operator-role-assignment-subscription'
  params: {
    principalId: automation.outputs.principalId
    roleDefinitionId: operatorRole.id
  }
}

module assignAtResourceGroup 'modules/role-assignment-resourcegroup.bicep' = if (!empty(targetResourceGroupName)) {
  name: 'operator-role-assignment-resourcegroup'
  scope: az.resourceGroup(targetResourceGroupName)
  params: {
    principalId: automation.outputs.principalId
    roleDefinitionId: operatorRole.id
  }
}

output automationAccountId string = automation.outputs.automationAccountId
output principalId string = automation.outputs.principalId
output roleDefinitionId string = operatorRole.id
output workspaceId string = automation.outputs.workspaceId
