// Resource-group scope: Automation Account with identity, Log Analytics, the module import, the
// runbook and its schedule. Called from main.bicep, which owns the role and its assignment.
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

param subscriptionIdForJobs string
param mode string
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
// (observed 2026-09-05). The module's manifest minimums match the runtime defaults instead.
// The version property is what makes ARM re-import when the package behind the same URI
// changed; without it a redeploy with an unchanged URI is a no-op.
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

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'run-vm-power-management'
  properties: {
    description: 'Runs the AzureVMPowerManagement runbook in ${mode} mode.'
    frequency: 'Minute'
    interval: intervalMinutes
    startTime: scheduleStartTime
    timeZone: scheduleTimeZone
  }
}

// Job schedules are immutable once linked: a parameter change needs a new schedule name or a
// redeploy after deleting the link. Anything that may change often belongs in an Automation
// variable the runbook reads, not in a job parameter.
resource job 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, mode, runbook.name)
  properties: {
    schedule: {
      name: schedule.name
    }
    runbook: {
      name: runbook.name
    }
    parameters: {
      SubscriptionId: subscriptionIdForJobs
      Mode: mode
    }
  }
}

output principalId string = automationAccount.identity.principalId
output automationAccountId string = automationAccount.id
output workspaceId string = workspace.id
