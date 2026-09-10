// Subscription-scope deployment of the controller: resource group, Automation Account with a
// system-assigned identity, the least-privilege role it needs, Log Analytics, module import,
// runbook and its hourly trigger. Subscription scope because a custom role definition lives there.
//
//   az deployment sub create -l westeurope -f deploy/main.bicep -p moduleVersion=0.1.2 maximumActions=25
//
// It arrives disarmed. The schedule runs the runbook every hour, it decides everything and it
// touches nothing until PM_Armed is set to true - which is one edit in the portal, not a
// redeployment. Read a week of the workbook first; see docs/decisions/0004.
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

@description('Import the module into the Automation Account. Set false when it arrives another way - a private feed, an existing pipeline, or a control plane stood up before the module is published anywhere. The runbook then expects the module to be there already.')
param importModule bool = true

@description('Raw URL of the runbook wrapper. Pin to a tag in production.')
param runbookContentUri string = 'https://raw.githubusercontent.com/simon-vedder/azure-vm-power-management/main/src/runbooks/Invoke-AzureVMPowerManagementRunbook.ps1'

@description('Resource group the identity gets the operator role on. Empty assigns the role at subscription scope. Start with one resource group.')
param targetResourceGroupName string = ''

@description('Whether the deployed controller performs its plan. False plans and reports and changes nothing, which is how it should arrive. Editable afterwards through the PM_Armed variable without a redeployment.')
param armed bool = false

@description('Refuse the whole run if it would act on more machines than this. There is no default that is right for somebody else estate, so it has to be stated.')
@minValue(1)
@maxValue(10000)
param maximumActions int

@description('Leave a machine alone this long after acting on it. Azure bills a five-minute minimum per start, so a schedule that flaps costs money as well as being wrong.')
@minValue(0)
@maxValue(1440)
param minimumDwellMinutes int = 30

@description('Act on machines carrying no schedule tag. Off by default: a machine nobody has tagged is one nobody has decided about. Untagged machines that are powered off and still billed are reported either way.')
param includeUntagged bool = false

@description('Tag key whose value names a schedule in the catalogue.')
param scheduleTag string = 'PowerSchedule'

@description('Tag key that protects a machine from every rule.')
param exclusionTag string = 'PowerSchedule-Exclude'

@description('Comma-separated subscriptions to narrow discovery to. Empty plans across everything the identity can read, which is one Resource Graph query rather than a loop.')
param subscriptionIdFilter string = ''

@description('Schedules that ship with this deployment. Time zones use the Windows form because that is the only one an Automation sandbox resolves - see docs/decisions/0008. Overwritten on every deployment; anything added with Set-VmPowerSchedule lives in PM_ScheduleCatalogCustom and is never touched here. Examples, not a fixed set - see docs/decisions/0005.')
param scheduleCatalog array = [
  {
    name: 'office-hours-ch'
    displayName: 'Office hours, Switzerland'
    timeZone: 'W. Europe Standard Time'
    weekdays: '07:30-18:30'
    minimumDwellMinutes: 30
  }
  {
    name: 'always-on'
    displayName: 'Managed, but never stopped'
    timeZone: 'UTC'
    actions: [
      {
        action: 'Start'
        at: '06:00'
        weekDays: 'All'
      }
    ]
    minimumDwellMinutes: 30
  }
]

@description('How often the controller wakes. Azure Automation cannot go below an hour, and it does not need to: each run plans the hour ahead. See docs/decisions/0006.')
@minValue(60)
@maxValue(1440)
param intervalMinutes int = 60

@description('First run of the schedule, ISO 8601. Must be at least five minutes in the future; defaults to one hour from deployment.')
param scheduleStartTime string = dateTimeAdd(baseTime, 'PT1H')

param scheduleTimeZone string = 'Etc/UTC'

param roleName string = 'AzureVMPowerManagement Operator'

@description('Exactly the actions the runbook calls, and nothing else. Reader cannot start or deallocate; Virtual Machine Contributor can also install extensions, which is code execution as SYSTEM or root on every machine in scope.')
param roleActions array = [
  'Microsoft.Compute/virtualMachines/read'
  'Microsoft.Compute/virtualMachines/start/action'
  'Microsoft.Compute/virtualMachines/deallocate/action'
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
    importModule: importModule
    armed: armed
    maximumActions: maximumActions
    minimumDwellMinutes: minimumDwellMinutes
    includeUntagged: includeUntagged
    scheduleTag: scheduleTag
    exclusionTag: exclusionTag
    subscriptionIdFilter: subscriptionIdFilter
    scheduleCatalog: scheduleCatalog
    intervalMinutes: intervalMinutes
    scheduleStartTime: scheduleStartTime
    scheduleTimeZone: scheduleTimeZone
  }
}

resource operatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, roleName)
  properties: {
    roleName: roleName
    description: 'Read a virtual machine, start it, deallocate it. Nothing else the AzureVMPowerManagement runbook does needs a permission.'
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
output armed bool = armed
