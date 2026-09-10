// Resource-group scope: Automation Account with identity, Log Analytics, the module import, the
// runbook, its hourly trigger and every setting the runbook reads. Called from main.bicep, which
// owns the custom role and its assignment.
targetScope = 'resourceGroup'

param location string
param automationAccountName string
param logAnalyticsWorkspaceName string
param logRetentionDays int
param tags object

@description('Where the AzureVMPowerManagement module package comes from. PowerShell Gallery URL by default.')
param modulePackageUri string

@description('Raw URL of the runbook script. Pinned to a tag or commit in production.')
param runbookContentUri string

@description('Version stamp for the module package and runbook content. Change it to force a re-import.')
param contentVersion string

param armed bool
param maximumActions int
param minimumDwellMinutes int
param includeUntagged bool
param scheduleTag string
param exclusionTag string
param subscriptionIdFilter string
param scheduleCatalog array
param intervalMinutes int
param scheduleStartTime string
param scheduleTimeZone string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
    disableLocalAuth: true
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: automationAccount
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'JobLogs'
        enabled: true
      }
      {
        category: 'JobStreams'
        enabled: true
      }
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}

// No Az module imports on purpose. The PowerShell 7.2 runtime ships a global Az bundle
// (11.2.0 at the time of writing: Az.Accounts 2.15.0, Az.Compute 7.1.1, Az.Resources 6.13.0).
// Importing a newer Az.Accounts next to it broke assembly loading in the sandbox
// (observed 2026-09-05). The module's manifest minimums match the runtime defaults instead, and
// Resource Graph and the Automation variables are reached over REST rather than through
// Az.ResourceGraph and Az.Automation, which are not in that bundle at all.
resource toolModule 'Microsoft.Automation/automationAccounts/powershell72Modules@2023-11-01' = {
  parent: automationAccount
  name: 'AzureVMPowerManagement'
  properties: {
    contentLink: {
      uri: modulePackageUri
      version: contentVersion
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Invoke-AzureVMPowerManagementRunbook'
  location: location
  tags: tags
  properties: {
    // 'PowerShell72' selects the PowerShell 7.2 runtime; 'PowerShell' would be Windows PowerShell 5.1.
    runbookType: 'PowerShell72'
    logProgress: false
    logVerbose: false
    description: 'Decides which Azure VMs should be off, proves what that saved, and delegates the power operation to Azure.'
    publishContentLink: {
      uri: runbookContentUri
      version: contentVersion
    }
  }
  dependsOn: [
    toolModule
  ]
}

// Every setting the runbook reads is a variable, not a job parameter. Automation ignores a PUT on
// a job schedule whose runbook and schedule are already linked: it reports Created, changes
// nothing, and the old parameters stay. Arming a deployment through a job parameter would
// therefore mean deleting the link first, and a redeploy that looked successful would have done
// nothing. A variable is one edit in the portal.
var settings = [
  {
    name: 'PM_Armed'
    value: string(armed)
    description: 'false plans and reports without touching a machine. Set it to true only after reading a week of the workbook.'
  }
  {
    name: 'PM_MaximumActions'
    value: string(maximumActions)
    description: 'Refuse the whole run if it would act on more machines than this. A jump in the count usually means a tag or a schedule changed, not the estate.'
  }
  {
    name: 'PM_MinimumDwellMinutes'
    value: string(minimumDwellMinutes)
    description: 'Leave a machine alone this long after acting on it. Azure bills a five-minute minimum per start.'
  }
  {
    name: 'PM_IncludeUntagged'
    value: string(includeUntagged)
    description: 'Act on machines carrying no schedule tag. Off by default: opt-in is the rule. Untagged stranded machines are reported either way.'
  }
  {
    name: 'PM_ScheduleTag'
    value: scheduleTag
    description: 'Tag key whose value names a schedule in the catalogue.'
  }
  {
    name: 'PM_ExclusionTag'
    value: exclusionTag
    description: 'Tag key that protects a machine from every rule, whatever else is true.'
  }
  {
    name: 'PM_SubscriptionId'
    value: subscriptionIdFilter
    description: 'Comma-separated subscriptions to narrow discovery to. Empty plans across everything the identity can read.'
  }
  {
    name: 'PM_ScheduleCatalog'
    value: string(scheduleCatalog)
    description: 'The schedules that ship with this deployment. Overwritten on every deployment - put your own in PM_ScheduleCatalogCustom.'
  }
]

resource settingVariables 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = [
  for setting in settings: {
    parent: automationAccount
    name: setting.name
    properties: {
      // Never encrypted. The workbook reads these over ARM, and an encrypted variable does not
      // return its value there. None of them is a secret.
      isEncrypted: false
      value: string(setting.value)
      description: setting.description
    }
  }
]

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'run-vm-power-management'
  properties: {
    description: 'Heartbeat for the AzureVMPowerManagement controller. One trigger, however many schedules - see docs/decisions/0006.'
    frequency: 'Minute'
    interval: intervalMinutes
    startTime: scheduleStartTime
    timeZone: scheduleTimeZone
  }
}

// No parameters on the link, deliberately. See the comment on the variables above: a link that
// already exists keeps its parameters and reports success anyway, so anything passed here would
// silently freeze at its first value.
resource job 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, schedule.name, runbook.name)
  properties: {
    schedule: {
      name: schedule.name
    }
    runbook: {
      name: runbook.name
    }
  }
  dependsOn: [
    settingVariables
  ]
}

output principalId string = automationAccount.identity.principalId
output automationAccountId string = automationAccount.id
output workspaceId string = workspace.id
