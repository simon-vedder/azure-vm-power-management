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
  -p moduleVersion=0.1.3 maximumActions=25 targetResourceGroupName=rg-target
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
| `PM_MinimumDwellMinutes` | `30` | Leave a machine alone this long after acting on it. Needs `PM_LastActionAt`; a schedule may ask for longer |
| `PM_IncludeUntagged` | `false` | Act on machines with no schedule tag |
| `PM_ScheduleTag` | `PowerSchedule` | Tag key whose value names a schedule |
| `PM_ExclusionTag` | `PowerSchedule-Exclude` | Tag key that protects a machine from every rule |
| `PM_SubscriptionId` | empty | Narrow discovery; empty means everything the identity reads |
| `PM_ScheduleCatalog` | the examples | **Owned by the deployment. Overwritten every time.** |
| `PM_ScheduleCatalogCustom` | not created | Owned by `Set-VmPowerSchedule`. Never touched here. |
| `PM_LastActionAt` | `{}` | What the runbook last acted on and when. Written by the runbook, reset by a redeployment. |

The split between `PM_ScheduleCatalog` and `PM_ScheduleCatalogCustom` is deliberate and is the reason
a redeployment cannot eat somebody's schedule — see [ADR 0005](../docs/decisions/0005-json-is-the-storage-format-not-the-authoring-format.md).

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

## The workbook

`workbook.json`, deployed against the Log Analytics workspace and loaded into the template with
`loadTextContent` so the file and the deployment cannot drift.

It reads the runbook's **own job streams** — no data collection rule, no custom table, no second
copy of the truth that could disagree with the job log. The runbook writes one machine-readable line
per machine, prefixed `PMREC`, alongside the readable one.

| Panel | What it answers |
|---|---|
| Is it armed? | Whether the last run acted or only reported |
| Powered off and still billed | The machines in `stopped` rather than `deallocated` |
| Why it did nothing | The reasons behind every skip, as a share |
| Skipped by a guard | Blast radius, dwell, protected, failed |
| Every decision, newest first | The raw log, 200 rows |

**No money figure appears in it, on purpose.** Turning deallocations into currency needs live
pricing per size, region and licence, and a number that looks precise and is guessed is worse than
no number. What it shows is what happened.

Job data is kept for 30 days by Azure Automation, so that is the window. Set `deployWorkbook=false`
to skip it.

## The policies

Two definitions and their assignments, both generated from `scheduleCatalog` so they cannot drift
from the schedules the controller actually reads. Nothing in the policy module names a schedule of
its own.

| Policy | What it does | Default |
|---|---|---|
| `<prefix>-unknown-schedule` | The `PowerSchedule` tag names something not in the catalogue | `Audit` |
| `<prefix>-untagged` | A virtual machine carries no `PowerSchedule` tag at all | `Audit` |

The first catches the typo. Without it, `office-hours-hc` means the machine is reported as
unresolvable and nothing happens to it — which looks exactly like a machine nobody onboarded, and is
the failure mode that is hardest to notice. Set `unknownScheduleEffect=Deny` once the estate is
clean; doing it first blocks work rather than fixing it.

The second is a report, not a rule. An untagged machine is deliberately unmanaged, and this is the
list of machines nobody has decided about yet.

Neither assignment carries an identity, because neither can change anything. Set
`deployPolicies=false` to skip them.

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
