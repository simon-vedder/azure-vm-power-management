#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    $manifestPath = Join-Path $PSScriptRoot '..' 'src' 'AzureVMPowerManagement' 'AzureVMPowerManagement.psd1'
    Import-Module $manifestPath -Force -ErrorAction Stop
    $module = Get-Module AzureVMPowerManagement

    # Private functions are fetched from the module scope once. Invoking the FunctionInfo runs the
    # body inside the module, so $script: variables resolve as they do in production.
    $Private = & $module {
        @{
            Resolve = Get-Command Resolve-VmPowerAction
            Query   = Get-Command Get-VmPowerInventoryQuery
            Graph   = Get-Command Invoke-VmPowerGraphQuery
        }
    }

    # One machine as Resource Graph hands it back: tags are a PSCustomObject, power state is the
    # .code form, and every field is a string.
    function New-Machine {
        param([hashtable]$Override = @{})
        $machine = @{
            id             = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dev/providers/Microsoft.Compute/virtualMachines/vm-01'
            name           = 'vm-01'
            powerState     = 'PowerState/stopped'
            location       = 'westeurope'
            resourceGroup  = 'rg-dev'
            subscriptionId = '00000000-0000-0000-0000-000000000000'
            vmSize         = 'Standard_B2s'
            tags           = [pscustomobject]@{ PowerSchedule = 'office-hours-ch' }
        }
        foreach ($key in $Override.Keys) { $machine[$key] = $Override[$key] }
        [pscustomobject]$machine
    }

    function New-Decision {
        param([hashtable]$Override = @{})
        $decision = @{
            PSTypeName      = 'AzureVMPowerManagement.VmPowerPlan'
            Id              = '/subscriptions/x/resourceGroups/rg-dev/providers/Microsoft.Compute/virtualMachines/vm-01'
            Name            = 'vm-01'
            ResourceGroup   = 'rg-dev'
            SubscriptionId  = 'x'
            Location        = 'westeurope'
            VmSize          = 'Standard_B2s'
            PowerState      = 'PowerState/stopped'
            Schedule        = 'office-hours-ch'
            Action          = 'Deallocate'
            Reason          = 'StoppedNotDeallocated'
            Explanation     = 'billed for compute'
            Protected       = $false
            ProtectedReason = ''
        }
        foreach ($key in $Override.Keys) { $decision[$key] = $Override[$key] }
        [pscustomobject]$decision
    }
}

Describe 'Module' {
    BeforeDiscovery {
        $publicFolder = Join-Path $PSScriptRoot '..' 'src' 'AzureVMPowerManagement' 'Public'
        $publicFunctions = @(Get-ChildItem -Path $publicFolder -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        # A state-changing verb is not the same as changing state: New-VmPowerSchedule builds an
        # object in memory. The help already declares which is which, so the promise in the help is
        # what this reads rather than a second list that would drift from it.
        $stateChanging = @(
            $publicFunctions |
                Where-Object { ($_ -split '-')[0] -in 'Remove', 'Set', 'New', 'Start', 'Stop', 'Restore', 'Update', 'Clear', 'Disable', 'Enable', 'Invoke' } |
                Where-Object { (Get-Content -Path (Join-Path $publicFolder "$_.ps1") -Raw) -notmatch 'Writes:\s*Nothing' }
        )
    }

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions in Public/ and the manifest agrees' {
        $public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src' 'AzureVMPowerManagement' 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be $public
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be $public
    }

    It 'documents <_> with synopsis, description and an example' -ForEach $publicFunctions {
        $help = Get-Help -Name $_ -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.examples.example).Count | Should -BeGreaterThan 0
    }

    It 'names the permissions <_> needs' -ForEach $publicFunctions {
        # The command reference generator fails the build on a missing RequiredPermissions, and a
        # test here means the failure arrives while writing the function rather than in CI.
        ((Get-Help -Name $_ -Full).alertSet.alert | Out-String) | Should -Match 'RequiredPermissions\s*:'
    }

    It '<_> supports ShouldProcess because it changes state' -ForEach $stateChanging {
        (Get-Command $_).Parameters.Keys | Should -Contain 'WhatIf'
    }
}

Describe 'Get-VmPowerInventoryQuery' {
    It 'reads the power state from .code, not the display string' {
        # displayStatus is 'VM deallocated' - a string for a portal blade. Comparing against it
        # would break the day Microsoft changes the wording or ships a localised one.
        $query = & $Private.Query
        $query | Should -Match 'powerState\.code'
        $query | Should -Not -Match 'displayStatus'
    }

    It 'does not filter, so machines the rules ignore still reach the report' {
        $query = & $Private.Query
        $query | Should -Not -Match "where powerState"
    }
}

Describe 'Resolve-VmPowerAction' {
    Context 'the stranded machine' {
        It 'deallocates a tagged machine that is stopped but still allocated' {
            $decision = & $Private.Resolve -Machine (New-Machine)
            $decision.Action | Should -Be 'Deallocate'
            $decision.Reason | Should -Be 'StoppedNotDeallocated'
            $decision.Protected | Should -BeFalse
        }

        It 'reports an untagged stranded machine but does not act on it' {
            $decision = & $Private.Resolve -Machine (New-Machine @{ tags = [pscustomobject]@{} })
            $decision.Action | Should -Be 'None'
            $decision.Reason | Should -Be 'StrandedButNotOnboarded'
            $decision.Explanation | Should -Match 'still billed for compute'
        }

        It 'acts on an untagged stranded machine only when explicitly told to' {
            $decision = & $Private.Resolve -Machine (New-Machine @{ tags = [pscustomobject]@{} }) -IncludeUntagged
            $decision.Action | Should -Be 'Deallocate'
        }
    }

    Context 'the machines it must leave alone' {
        It 'never touches a machine carrying the exclusion tag, even a stranded one' {
            $machine = New-Machine @{ tags = [pscustomobject]@{ PowerSchedule = 'office-hours-ch'; 'PowerSchedule-Exclude' = 'ticket-4711' } }
            $decision = & $Private.Resolve -Machine $machine
            $decision.Action | Should -Be 'None'
            $decision.Protected | Should -BeTrue
            $decision.ProtectedReason | Should -Match 'PowerSchedule-Exclude'
        }

        It 'does nothing when the power state cannot be read' {
            # A resource with no instance view returns an empty string. Verified against a live
            # tenant on 2026-09-10: non-VM resources come back with powerState ''.
            $decision = & $Private.Resolve -Machine (New-Machine @{ powerState = '' })
            $decision.Action | Should -Be 'None'
            $decision.Reason | Should -Be 'PowerStateUnknown'
        }

        It 'does nothing to a machine in <_>' -ForEach @('PowerState/starting', 'PowerState/stopping', 'PowerState/deallocating') {
            $decision = & $Private.Resolve -Machine (New-Machine @{ powerState = $_ })
            $decision.Action | Should -Be 'None'
            $decision.Reason | Should -Be 'InTransition'
        }

        It 'leaves a running machine alone, because version one has no schedules' {
            $decision = & $Private.Resolve -Machine (New-Machine @{ powerState = 'PowerState/running' })
            $decision.Action | Should -Be 'None'
            $decision.Reason | Should -Be 'NoRuleMatched'
        }

        It 'leaves an already deallocated machine alone' {
            $decision = & $Private.Resolve -Machine (New-Machine @{ powerState = 'PowerState/deallocated' })
            $decision.Action | Should -Be 'None'
        }
    }

    Context 'tags' {
        It 'matches a tag key whatever case Azure returns it in' {
            # Azure is inconsistent about tag key casing, and a lookup that misses would read as
            # "not excluded" - which is the direction that costs somebody an outage.
            $machine = New-Machine @{ tags = [pscustomobject]@{ 'powerschedule-EXCLUDE' = 'yes' } }
            (& $Private.Resolve -Machine $machine).Protected | Should -BeTrue
        }

        It 'reads tags handed over as a hashtable as well as an object' {
            $machine = New-Machine @{ tags = @{ PowerSchedule = 'office-hours-ch' } }
            (& $Private.Resolve -Machine $machine).Action | Should -Be 'Deallocate'
        }

        It 'survives a machine with no tags at all' {
            { & $Private.Resolve -Machine (New-Machine @{ tags = $null }) } | Should -Not -Throw
        }

        It 'honours a custom tag key from the deployment' {
            $machine = New-Machine @{ tags = [pscustomobject]@{ 'company-power' = 'nights' } }
            $decision = & $Private.Resolve -Machine $machine -ScheduleTag 'company-power'
            $decision.Action | Should -Be 'Deallocate'
            $decision.Schedule | Should -Be 'nights'
        }
    }

    It 'always says why, even when it does nothing' {
        foreach ($state in 'PowerState/running', 'PowerState/deallocated', '', 'PowerState/stopping') {
            $decision = & $Private.Resolve -Machine (New-Machine @{ powerState = $state })
            $decision.Reason | Should -Not -BeNullOrEmpty
            $decision.Explanation | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-VmPowerPlan' {
    # These exist because the first live run against an empty tenant produced one phantom machine
    # called "(unnamed)". The rules were right; the plumbing between the graph call and the rules
    # collapsed none, one and many into the wrong shape. Fixtures could not see it, so the counts
    # are asserted here.
    Context 'however many machines come back' {
        It 'returns nothing when the estate has no machines' {
            Mock -CommandName Invoke-VmPowerGraphQuery -ModuleName AzureVMPowerManagement -MockWith { }
            @(Get-VmPowerPlan).Count | Should -Be 0
        }

        It 'returns one decision for one machine' {
            Mock -CommandName Invoke-VmPowerGraphQuery -ModuleName AzureVMPowerManagement -MockWith { New-Machine }
            $plan = @(Get-VmPowerPlan)
            $plan.Count | Should -Be 1
            $plan[0].Name | Should -Be 'vm-01'
        }

        It 'returns one decision per machine for many' {
            Mock -CommandName Invoke-VmPowerGraphQuery -ModuleName AzureVMPowerManagement -MockWith {
                1..3 | ForEach-Object { New-Machine @{ name = "vm-0$_" } }
            }
            $plan = @(Get-VmPowerPlan)
            $plan.Count | Should -Be 3
            @($plan.Name | Sort-Object) | Should -Be @('vm-01', 'vm-02', 'vm-03')
        }

        It 'never invents a machine out of an empty row' {
            Mock -CommandName Invoke-VmPowerGraphQuery -ModuleName AzureVMPowerManagement -MockWith { $null }
            @(Get-VmPowerPlan | Where-Object Name -eq '(unnamed)').Count | Should -Be 0
        }
    }

    Context 'filtering' {
        BeforeEach {
            Mock -CommandName Invoke-VmPowerGraphQuery -ModuleName AzureVMPowerManagement -MockWith {
                @(
                    New-Machine @{ name = 'stranded' }
                    New-Machine @{ name = 'running'; powerState = 'PowerState/running' }
                )
            }
        }

        It 'reports every machine by default, acted on or not' {
            @(Get-VmPowerPlan).Count | Should -Be 2
        }

        It 'returns only what an armed run would touch with -ActionableOnly' {
            $plan = @(Get-VmPowerPlan -ActionableOnly)
            $plan.Count | Should -Be 1
            $plan[0].Name | Should -Be 'stranded'
        }
    }

    It 'reads Resource Graph and writes nothing' {
        # The read path must stay a read path: no Az cmdlet that changes anything belongs in it.
        $body = (Get-Command Get-VmPowerPlan).Definition
        $body | Should -Not -Match '\bStop-AzVM\b'
        $body | Should -Not -Match '\bStart-AzVM\b'
    }
}

Describe 'Invoke-VmPowerPlan' {
    Context 'the blast radius' {
        It 'performs nothing at all when the plan is larger than the cap' {
            # Acting on the first n and then stopping would be the worst of both: a partial change
            # nobody asked for, and no report.
            $plan = 1..5 | ForEach-Object { New-Decision @{ Name = "vm-0$_"; Id = "id-$_" } }
            { $plan | Invoke-VmPowerPlan -MaximumActions 3 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*more than the 3 allowed*'
        }

        It 'counts only what it would act on, not what it would skip' {
            $plan = @(
                New-Decision @{ Id = 'a' }
                New-Decision @{ Id = 'b'; Action = 'None'; Reason = 'NoRuleMatched' }
                New-Decision @{ Id = 'c'; Protected = $true; ProtectedReason = 'excluded' }
            )
            { $plan | Invoke-VmPowerPlan -MaximumActions 1 -WhatIf } | Should -Not -Throw
        }
    }

    Context 'the guards' {
        It 'skips a protected machine and says why' {
            $result = New-Decision @{ Protected = $true; ProtectedReason = 'Excluded by the PowerSchedule-Exclude tag' } |
                Invoke-VmPowerPlan -MaximumActions 10 -WhatIf
            $result.Status | Should -Be 'Skipped'
            $result.Detail | Should -Match 'Exclude'
        }

        It 'skips a machine acted on inside the dwell window' {
            $recent = @{ 'id-1' = [datetime]::UtcNow.AddMinutes(-5) }
            $result = New-Decision @{ Id = 'id-1' } |
                Invoke-VmPowerPlan -MaximumActions 10 -MinimumDwellMinutes 30 -LastActionAt $recent -WhatIf
            $result.Status | Should -Be 'Skipped'
            $result.Detail | Should -Match 'dwell'
        }

        It 'acts on a machine once the dwell window has passed' {
            $old = @{ 'id-1' = [datetime]::UtcNow.AddMinutes(-90) }
            $result = New-Decision @{ Id = 'id-1' } |
                Invoke-VmPowerPlan -MaximumActions 10 -MinimumDwellMinutes 30 -LastActionAt $old -WhatIf
            $result.Status | Should -Be 'WhatIf'
        }

        It 'ignores the dwell check when it is switched off' {
            $recent = @{ 'id-1' = [datetime]::UtcNow.AddMinutes(-1) }
            $result = New-Decision @{ Id = 'id-1' } |
                Invoke-VmPowerPlan -MaximumActions 10 -MinimumDwellMinutes 0 -LastActionAt $recent -WhatIf
            $result.Status | Should -Be 'WhatIf'
        }

        It 'requires a blast radius rather than assuming one' {
            (Get-Command Invoke-VmPowerPlan).Parameters['MaximumActions'].Attributes.Mandatory |
                Should -Contain $true
        }
    }

    Context 'reporting' {
        It 'returns a row for every machine, including the ones it skipped' {
            $plan = @(
                New-Decision @{ Id = 'a' }
                New-Decision @{ Id = 'b'; Action = 'None'; Reason = 'NoRuleMatched' }
            )
            @($plan | Invoke-VmPowerPlan -MaximumActions 10 -WhatIf).Count | Should -Be 2
        }

        It 'changes nothing under -WhatIf' {
            Mock -CommandName Stop-AzVM -ModuleName AzureVMPowerManagement -MockWith { throw 'must not run' }
            $result = New-Decision | Invoke-VmPowerPlan -MaximumActions 10 -WhatIf
            $result.Status | Should -Be 'WhatIf'
            Should -Invoke Stop-AzVM -ModuleName AzureVMPowerManagement -Times 0
        }

        It 'deallocates through Stop-AzVM when it is armed' {
            Mock -CommandName Stop-AzVM -ModuleName AzureVMPowerManagement -MockWith { }
            $result = New-Decision | Invoke-VmPowerPlan -MaximumActions 10 -Confirm:$false
            $result.Status | Should -Be 'Done'
            Should -Invoke Stop-AzVM -ModuleName AzureVMPowerManagement -Times 1 -ParameterFilter {
                $ResourceGroupName -eq 'rg-dev' -and $Name -eq 'vm-01' -and $Force
            }
        }

        It 'records a failure against the machine and carries on with the rest' {
            Mock -CommandName Stop-AzVM -ModuleName AzureVMPowerManagement -MockWith {
                if ($Name -eq 'vm-bad') { throw 'OperationNotAllowed' }
            }
            $plan = @(
                New-Decision @{ Id = 'a'; Name = 'vm-bad' }
                New-Decision @{ Id = 'b'; Name = 'vm-good' }
            )
            $result = @($plan | Invoke-VmPowerPlan -MaximumActions 10 -Confirm:$false)
            ($result | Where-Object Name -eq 'vm-bad').Status | Should -Be 'Failed'
            ($result | Where-Object Name -eq 'vm-bad').Detail | Should -Match 'OperationNotAllowed'
            ($result | Where-Object Name -eq 'vm-good').Status | Should -Be 'Done'
        }
    }
}

Describe 'New-VmPowerSchedule' {
    It 'compiles the weekday shorthand into a start and a stop' {
        # Writing two action entries by hand is how people end up with a stop and no start.
        $s = New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30'
        @($s.Actions).Count | Should -Be 2
        ($s.Actions | Where-Object Action -eq 'Start').At | Should -Be '07:30'
        ($s.Actions | Where-Object Action -eq 'Deallocate').At | Should -Be '18:30'
        @($s.Actions[0].WeekDays) | Should -Be @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
    }

    It 'gives the daily shorthand all seven days' {
        $s = New-VmPowerSchedule -Name lab -TimeZone 'UTC' -Daily '08:00-20:00'
        @($s.Actions[0].WeekDays).Count | Should -Be 7
    }

    It 'makes a schedule with no stop, which is managed but never stopped' {
        # Better than leaving a machine untagged: untagged is indistinguishable from forgotten.
        $s = New-VmPowerSchedule -Name always-on -TimeZone 'UTC' -Start '06:00'
        @($s.Actions).Count | Should -Be 1
        $s.Actions[0].Action | Should -Be 'Start'
    }

    It 'pads a single-digit hour so two ways of writing the same time compare equal' {
        (New-VmPowerSchedule -Name lab -TimeZone 'UTC' -Start '6:05').Actions[0].At | Should -Be '06:05'
    }

    It 'accepts a time zone in either the Windows or the IANA form' {
        # Both resolve on the Linux workers that run PowerShell 7.2 in Azure Automation.
        { New-VmPowerSchedule -Name a-schedule -TimeZone 'W. Europe Standard Time' -Start '06:00' } | Should -Not -Throw
        { New-VmPowerSchedule -Name a-schedule -TimeZone 'Europe/Zurich' -Start '06:00' } | Should -Not -Throw
    }

    Context 'what it refuses' {
        It 'refuses the name <_> because it is also a tag value and a policy allowedValues entry' -ForEach @('Office-Hours', 'ab', 'has spaces', '-leading', 'trailing-') {
            { New-VmPowerSchedule -Name $_ -TimeZone 'UTC' -Start '06:00' } | Should -Throw -ExpectedMessage '*not usable*'
        }

        It 'refuses a time zone this runtime cannot resolve, and names both accepted forms' {
            { New-VmPowerSchedule -Name lab -TimeZone 'Middle-earth/Shire' -Start '06:00' } |
                Should -Throw -ExpectedMessage '*Europe/Zurich*'
        }

        It 'refuses the malformed time <_>' -ForEach @('25:00', '07:60', '0730', 'half eight') {
            { New-VmPowerSchedule -Name lab -TimeZone 'UTC' -Start $_ } | Should -Throw
        }

        It 'refuses a span that is not HH:mm-HH:mm' {
            { New-VmPowerSchedule -Name lab -TimeZone 'UTC' -Weekdays '7-18' } | Should -Throw -ExpectedMessage "*not 'HH:mm-HH:mm'*"
        }

        It 'refuses an exception date that is not yyyy-MM-dd' {
            { New-VmPowerSchedule -Name lab -TimeZone 'UTC' -Start '06:00' -ExceptDate '24.12.2026' } |
                Should -Throw -ExpectedMessage '*Expected yyyy-MM-dd*'
        }
    }
}

Describe 'Test-VmPowerSchedule' {
    It 'reports every problem instead of stopping at the first' {
        # Somebody validating twelve schedules wants twelve answers.
        $catalog = @(
            @{ name = 'good-one'; timeZone = 'UTC'; weekdays = '07:00-19:00' }
            @{ name = 'BadName'; timeZone = 'UTC'; weekdays = '07:00-19:00' }
            @{ name = 'bad-zone'; timeZone = 'Nowhere/Here'; weekdays = '07:00-19:00' }
        )
        $results = @($catalog | Test-VmPowerSchedule)
        $results.Count | Should -Be 3
        @($results | Where-Object Valid).Count | Should -Be 1
        @($results | Where-Object { -not $_.Valid }).Count | Should -Be 2
    }

    It 'catches a duplicate name, which no schema check would' {
        # The second entry silently wins, and nobody can see which of the two is running.
        $catalog = @(
            @{ name = 'office-hours'; timeZone = 'UTC'; weekdays = '07:00-19:00' }
            @{ name = 'office-hours'; timeZone = 'UTC'; weekdays = '08:00-20:00' }
        )
        $results = @($catalog | Test-VmPowerSchedule)
        $results[1].Valid | Should -BeFalse
        $results[1].Problem | Should -Match 'Duplicate name'
    }

    It 'never throws, whatever it is handed' {
        { @{ nonsense = $true } | Test-VmPowerSchedule } | Should -Not -Throw
    }

    It 'returns the expanded schedule with -Detailed' {
        $r = @{ name = 'lab'; timeZone = 'UTC'; weekdays = '07:00-19:00' } | Test-VmPowerSchedule -Detailed
        @($r.Schedule.Actions).Count | Should -Be 2
    }
}

Describe 'Show-VmPowerScheduleCalendar' {
    BeforeAll {
        function Get-Utc { param([int]$y, [int]$m, [int]$d) [datetime]::new($y, $m, $d, 0, 0, 0, [System.DateTimeKind]::Utc) }
    }

    It 'converts a local time to the right instant on both sides of the year' {
        # 07:30 in Zurich is 05:30 UTC in summer and 06:30 UTC in winter. Getting this wrong by an
        # hour is the single most likely way for a power schedule to be quietly useless.
        $s = New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Daily '07:30-18:30'
        $summer = @($s | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 7 1) -Days 1 | Where-Object Action -eq 'Start')
        $winter = @($s | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 12 1) -Days 1 | Where-Object Action -eq 'Start')
        $summer[0].Utc.ToString('HH:mm') | Should -Be '05:30'
        $winter[0].Utc.ToString('HH:mm') | Should -Be '06:30'
    }

    It 'shifts an action out of the spring gap rather than throwing' {
        # 02:30 does not exist on 29 March 2026 in Zurich, and ConvertTimeToUtc throws on it.
        # Unhandled, that takes the runbook down once a year at half past two.
        $s = New-VmPowerSchedule -Name nightly -TimeZone 'Europe/Zurich' -Days Sunday -Start '02:30'
        $occurrence = @($s | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 3 29) -Days 1)[0]
        $occurrence.LocalTime.ToString('HH:mm') | Should -Be '03:00'
        $occurrence.Note | Should -Match 'gap'
    }

    It 'marks the doubled autumn hour instead of smoothing it away' {
        $s = New-VmPowerSchedule -Name nightly -TimeZone 'Europe/Zurich' -Days Sunday -Start '02:30'
        $occurrence = @($s | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 10 25) -Days 1)[0]
        $occurrence.Utc.ToString('HH:mm') | Should -Be '01:30'
        $occurrence.Note | Should -Match 'twice'
    }

    It 'treats a local datetime as local rather than relabelling it' {
        # [datetime]'2026-10-25T00:00:00Z' is not a UTC value: PowerShell converts it to the
        # machine's local time and keeps Kind Local. Relabelling would move the window silently.
        $s = New-VmPowerSchedule -Name office-hours-ch -TimeZone 'UTC' -Daily '12:00-13:00'
        $viaLocal = @($s | Show-VmPowerScheduleCalendar -FromUtc ([datetime]::new(2026, 6, 1, 0, 0, 0, [System.DateTimeKind]::Local)) -Days 1)
        $viaUtc = @($s | Show-VmPowerScheduleCalendar -FromUtc ([datetime]::new(2026, 6, 1, 0, 0, 0, [System.DateTimeKind]::Local).ToUniversalTime()) -Days 1)
        @($viaLocal.Utc) | Should -Be @($viaUtc.Utc)
    }

    It 'skips an exception date and says which one' {
        $s = New-VmPowerSchedule -Name office-hours-ch -TimeZone 'UTC' -Daily '09:00-17:00' -ExceptDate '2026-12-24'
        $day = @($s | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 12 24) -Days 1)
        @($day | Where-Object Skipped).Count | Should -Be 2
        $day[0].Action | Should -Be 'None'
        $day[0].Note | Should -Match '2026-12-24'
    }

    It 'produces nothing on a day the schedule does not cover' {
        $s = New-VmPowerSchedule -Name weekdays-only -TimeZone 'UTC' -Weekdays '09:00-17:00'
        # 2026-06-06 is a Saturday.
        @($s | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 6 6) -Days 2).Count | Should -Be 0
    }

    It 'orders a whole catalogue by instant, not by schedule' {
        $early = New-VmPowerSchedule -Name early-birds -TimeZone 'UTC' -Daily '06:00-14:00'
        $late = New-VmPowerSchedule -Name late-shift -TimeZone 'UTC' -Daily '14:00-22:00'
        $all = @($late, $early | Show-VmPowerScheduleCalendar -FromUtc (Get-Utc 2026 6 1) -Days 1)
        @($all.Utc) | Should -Be @($all.Utc | Sort-Object)
    }
}
