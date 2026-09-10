# deploy/

`main.bicep` deploys the controller: resource group, Automation Account with a system-assigned
identity, the least-privilege custom role it needs, Log Analytics for job logs, the module import
from the PowerShell Gallery, the runbook, its hourly trigger and every setting the runbook reads.

`azuredeploy.json` is the compiled form of `main.bicep` for the *Deploy to Azure* button; CI fails
when the two drift apart. Rebuild it with the Bicep version pinned in `.github/workflows/ci.yml`:

```bash
az bicep install --version v0.46.1
az bicep build -f deploy/main.bicep --outfile deploy/azuredeploy.json
```

Subscription-scope deployment, because the custom role definition lives there:

```bash
az deployment sub create -l westeurope -f deploy/main.bicep \
  -p moduleVersion=0.1.0 maximumActions=25 targetResourceGroupName=rg-target
```

## It arrives disarmed

`armed` defaults to false. The schedule runs every hour, the controller decides everything, writes
every decision to the job log, and touches no machine. That is the intended first week.

Arming it is **one edit**, not a redeployment: set the Automation variable `PM_Armed` to `true`.
Everything else the runbook reads is a variable too, for the same reason — Automation ignores a PUT
on a job schedule that is already linked, so a setting passed as a job parameter freezes at its
first value while the redeployment reports success.

| Variable | Default | What it does |
|---|---|---|
| `PM_Armed` | `false` | Whether the plan is performed or only reported |
| `PM_MaximumActions` | from `maximumActions` | Refuse the whole run above this many machines |
| `PM_MinimumDwellMinutes` | `30` | Leave a machine alone this long after acting on it |
| `PM_IncludeUntagged` | `false` | Act on machines with no schedule tag |
| `PM_ScheduleTag` | `PowerSchedule` | Tag key whose value names a schedule |
| `PM_ExclusionTag` | `PowerSchedule-Exclude` | Tag key that protects a machine from every rule |
| `PM_SubscriptionId` | empty | Narrow discovery; empty means everything the identity reads |
| `PM_ScheduleCatalog` | the examples | **Owned by the deployment. Overwritten every time.** |
| `PM_ScheduleCatalogCustom` | not created | Owned by `Set-VmPowerSchedule`. Never touched here. |

The split between the last two is deliberate and is the reason a redeployment cannot eat somebody's
schedule — see [ADR 0005](../docs/decisions/0005-json-is-the-storage-format-not-the-authoring-format.md).

## What it creates

| Resource | Purpose |
|---|---|
| Resource group | everything below |
| Automation Account, system-assigned identity, local auth disabled | runs the runbook |
| Log Analytics workspace + diagnostic settings | job logs and streams |
| Module `AzureVMPowerManagement` (PowerShell 7.2 runtime, uses the runtime's global Az bundle) | the rules |
| Runbook `Invoke-AzureVMPowerManagementRunbook` (PowerShell 7.2) | the thin wrapper from `src/runbooks/` |
| Schedule `run-vm-power-management`, hourly | the heartbeat — one trigger, however many schedules |
| Job schedule, **with no parameters** | see above |
| Eight Automation variables | everything the runbook reads |
| Custom role `roleName` with `roleActions` | exactly what the runbook needs |
| Role assignment on `targetResourceGroupName`, or the subscription when empty | least privilege |

## The role

Four actions, and no more:

```
Microsoft.Compute/virtualMachines/read
Microsoft.Compute/virtualMachines/start/action
Microsoft.Compute/virtualMachines/deallocate/action
Microsoft.Resources/subscriptions/resourceGroups/read
```

Reader cannot start or deallocate. Virtual Machine Contributor can, and can also install extensions
— which is code execution as SYSTEM or root on every machine in scope. Neither is the right answer
for a tool whose whole job is two power operations.

The identity needs no permission on its own Automation Account: the runbook reads its settings
through `Get-AutomationVariable`, which works from inside the sandbox without RBAC.

## Start with one resource group

Pass `targetResourceGroupName`. The role is then assigned there rather than across the subscription,
so the blast radius of a mistake is bounded by Azure as well as by `PM_MaximumActions`. Widen it
once a month of the workbook has been boring.
