// Subscription scope: two policy definitions and their assignments, both generated from the same
// catalogue the controller reads. Nothing here lists a schedule name of its own - the allowed
// values come from scheduleNames, which main.bicep derives from the catalogue parameter, so the
// two cannot drift apart. That is the entire point of naming a schedule instead of describing one.
targetScope = 'subscription'

@description('The schedule names that exist. Derived from the catalogue, never typed here.')
param scheduleNames array

@description('Tag key whose value names a schedule.')
param scheduleTag string

@description('What to do about a machine whose tag names a schedule that does not exist. Audit reports it; Deny stops the deployment that would create it. Audit first: Deny on an estate that already has typos blocks work rather than fixing it.')
@allowed(['Audit', 'Deny', 'Disabled'])
param unknownScheduleEffect string

@description('What to do about a machine with no schedule tag at all. This is a report, not a rule - an untagged machine is simply not managed, and the list is who has not decided yet.')
@allowed(['Audit', 'Disabled'])
param untaggedEffect string

@description('Scope the assignments apply to. Empty assigns at the subscription.')
param assignmentScopeResourceGroupName string

param policyNamePrefix string
param tags object

var vmTypeCondition = {
  field: 'type'
  equals: 'Microsoft.Compute/virtualMachines'
}

resource unknownSchedule 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: '${policyNamePrefix}-unknown-schedule'
  properties: {
    displayName: 'VM power schedule tag must name a schedule that exists'
    description: 'The ${scheduleTag} tag points at an entry in the controller\'s catalogue. A value that is not in it means the machine is reported as unresolvable and nothing happens to it - which looks exactly like a machine nobody onboarded. This catches the typo at deployment time instead of at half past six.'
    policyType: 'Custom'
    mode: 'Indexed'
    metadata: {
      category: 'Compute'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: unknownScheduleEffect
        allowedValues: ['Audit', 'Deny', 'Disabled']
        metadata: {
          displayName: 'Effect'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          vmTypeCondition
          {
            field: 'tags[${scheduleTag}]'
            exists: true
          }
          {
            field: 'tags[${scheduleTag}]'
            notIn: scheduleNames
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

resource untagged 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: '${policyNamePrefix}-untagged'
  properties: {
    displayName: 'VM has no power schedule tag'
    description: 'Not a rule, a report. A machine without the ${scheduleTag} tag is not managed by the controller, deliberately - opt-in is the design. This is the list of machines nobody has decided about yet.'
    policyType: 'Custom'
    mode: 'Indexed'
    metadata: {
      category: 'Compute'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: untaggedEffect
        allowedValues: ['Audit', 'Disabled']
        metadata: {
          displayName: 'Effect'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          vmTypeCondition
          {
            field: 'tags[${scheduleTag}]'
            exists: false
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

// Audit and Deny need no identity, which is why there is none here. A policy that could change a
// resource would need one, and this pair deliberately cannot.
resource assignUnknownSubscription 'Microsoft.Authorization/policyAssignments@2024-04-01' = if (empty(assignmentScopeResourceGroupName)) {
  name: '${policyNamePrefix}-unknown-schedule'
  properties: {
    displayName: 'VM power schedule tag must name a schedule that exists'
    policyDefinitionId: unknownSchedule.id
    enforcementMode: 'Default'
    metadata: tags
  }
}

resource assignUntaggedSubscription 'Microsoft.Authorization/policyAssignments@2024-04-01' = if (empty(assignmentScopeResourceGroupName)) {
  name: '${policyNamePrefix}-untagged'
  properties: {
    displayName: 'VM has no power schedule tag'
    policyDefinitionId: untagged.id
    enforcementMode: 'Default'
    metadata: tags
  }
}

module assignAtResourceGroup 'policy-assignment-resourcegroup.bicep' = if (!empty(assignmentScopeResourceGroupName)) {
  name: 'power-schedule-policy-assignments'
  scope: resourceGroup(assignmentScopeResourceGroupName)
  params: {
    policyNamePrefix: policyNamePrefix
    unknownScheduleDefinitionId: unknownSchedule.id
    untaggedDefinitionId: untagged.id
    tags: tags
  }
}

output unknownScheduleDefinitionId string = unknownSchedule.id
output untaggedDefinitionId string = untagged.id
output allowedScheduleNames array = scheduleNames
