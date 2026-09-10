// Resource-group scope: the two assignments, when the deployment is scoped to one resource group
// rather than the whole subscription. Same definitions either way - only the scope differs.
targetScope = 'resourceGroup'

param policyNamePrefix string
param unknownScheduleDefinitionId string
param untaggedDefinitionId string
param tags object

resource assignUnknown 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${policyNamePrefix}-unknown-schedule'
  properties: {
    displayName: 'VM power schedule tag must name a schedule that exists'
    policyDefinitionId: unknownScheduleDefinitionId
    enforcementMode: 'Default'
    metadata: tags
  }
}

resource assignUntagged 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: '${policyNamePrefix}-untagged'
  properties: {
    displayName: 'VM has no power schedule tag'
    policyDefinitionId: untaggedDefinitionId
    enforcementMode: 'Default'
    metadata: tags
  }
}
