# deploy/

`main.bicep` deploys the automation: resource group, Automation Account with a system-assigned
identity, the least-privilege custom role it needs, Log Analytics for job logs, the module import
from the PowerShell Gallery, the runbook and its schedule.

`azuredeploy.json` is the compiled form of `main.bicep` for the *Deploy to Azure* button; CI fails
when the two drift apart. Rebuild it with the Bicep version pinned in `.github/workflows/ci.yml`:

```bash
az bicep install --version v0.46.1
az bicep build -f deploy/main.bicep --outfile deploy/azuredeploy.json
```

Subscription-scope deployment, because the custom role definition lives there:

```bash
az deployment sub create -l westeurope -f deploy/main.bicep -p moduleVersion=0.1.0 targetResourceGroupName=rg-target
```

| Resource | Purpose |
|---|---|
| Resource group | everything below |
| Automation Account, system-assigned identity, local auth disabled | runs the runbook |
| Log Analytics workspace + diagnostic settings | job logs and streams |
| Module `AzureVMPowerManagement` (PowerShell 7.2 runtime, uses the runtime's global Az bundle) | the logic |
| Runbook `Invoke-AzureVMPowerManagementRunbook` (PowerShell 7.2) | the thin wrapper from `src/runbooks/` |
| Schedule, every `intervalMinutes`, linked in `Report` mode | the recurring job |
| Custom role `roleName` with `roleActions` | exactly what the runbook needs |
| Role assignment on `targetResourceGroupName`, or the subscription when empty | least privilege |

Nothing changes state by itself: the linked schedule runs in `Report` mode. Switch to `Apply` by
redeploying with `mode=Apply` once the reports look right.

`modulePackageUri` defaults to the Gallery package for `moduleVersion`; override it for a private
build. When the content behind an unchanged URI changes, bump `contentVersion` (defaults to
`moduleVersion`, must look like a `System.Version`, e.g. `0.1.0.2`): Automation only re-imports a
module or re-publishes a runbook when the version stamp on the link changes.

Tearing down: `az group delete` removes the resource group, but the custom role definition lives at
subscription scope and stays behind, as can an orphaned assignment. Remove both:

```bash
role=$(az role definition list --custom-role-only true --query "[?roleName=='AzureVMPowerManagement Operator'].name" -o tsv)
az role assignment list --all --query "[?contains(roleDefinitionId, '$role')].id" -o tsv | xargs -n1 az role assignment delete --ids
az role definition delete --name "AzureVMPowerManagement Operator"
```
