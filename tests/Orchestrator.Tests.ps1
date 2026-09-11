#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The runbook is the only file nothing else covers. The module has unit tests, the template has a
# drift check, and between them sits the wrapper that reads the settings, merges the catalogue,
# calls the plan, calls the executor and writes back what it did. Every assertion here failed at
# least once against code that passed all 168 tests in the file next door.
#
# Run in a child process on purpose: the scenarios stub Stop-AzVM, Set-AzContext and
# Invoke-AzRestMethod in the global scope, and a global Stop-AzVM would follow every other test
# file around for the rest of the session.

BeforeAll {
    $scenarioScript = Join-Path $PSScriptRoot 'orchestrator' 'Invoke-OrchestratorScenarios.ps1'
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "vmpower-scenarios-$([guid]::NewGuid()).json"
    $pwsh = if ($IsWindows) { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'pwsh' }

    & $pwsh -NoProfile -File $scenarioScript -OutputPath $outputPath | Out-Null
    if (-not (Test-Path $outputPath)) { throw "The scenario runner wrote nothing to $outputPath." }

    $scenarios = @{}
    foreach ($entry in (Get-Content -Raw $outputPath | ConvertFrom-Json).scenarios) { $scenarios[$entry.name] = $entry }
    Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
}

Describe 'The runbook, end to end' {
    Context 'disarmed' {
        It 'touches nothing' {
            $scenarios['disarmed'].stops | Should -Be 0
        }

        It 'still reports a decision for every machine, including the ones it leaves alone' {
            @($scenarios['disarmed'].records).Count | Should -Be 4
        }

        It 'reports what an armed run would do, not the word WhatIf' {
            $statuses = @($scenarios['disarmed'].records | ForEach-Object { $_.status })
            $statuses | Should -Contain 'StoppedNotDeallocated'
            $statuses | Should -Contain 'MatchesSchedule'
            $statuses | Should -Not -Contain 'WhatIf'
        }

        It 'refuses a blast radius set too low, so a first week finds it instead of the arming day' {
            $scenarios['blast radius, disarmed'].refused | Should -Match 'more than the 1 allowed'
            $scenarios['blast radius, disarmed'].stops | Should -Be 0
        }
    }

    Context 'armed, across two subscriptions' {
        # Both machines are called vm-app and both live in a resource group called rg-shared. Only
        # the subscription tells them apart, and Stop-AzVM has no parameter for it.
        It 'deallocates both, one in each subscription' {
            $ids = @($scenarios['armed across two subscriptions'].stoppedIds | Where-Object { $_ -like '*vm-app' })
            @($ids | Sort-Object -Unique).Count | Should -Be 2
        }

        It 'acts on the machine in the second subscription rather than the first one twice' {
            $ids = @($scenarios['armed across two subscriptions'].stoppedIds | Where-Object { $_ -like '*vm-app' })
            @($ids | Sort-Object -Unique).Count | Should -Be 2
            ($ids -join ' ') | Should -Match '11111111-1111-1111-1111-111111111111'
            ($ids -join ' ') | Should -Match '22222222-2222-2222-2222-222222222222'
        }

        It 'writes down what it touched, with the zone intact' {
            # ConvertFrom-Json hands an ISO string back as a DateTime, and [string] on that drops
            # the Z. The store then aged by the local offset and pruned itself empty.
            $scenarios['armed across two subscriptions'].lastActionAt | Should -Match 'Z"'
            @(($scenarios['armed across two subscriptions'].lastActionAt | ConvertFrom-Json).PSObject.Properties).Count | Should -Be 3
        }
    }

    Context 'the schedule catalogue, in the shape Automation returns it' {
        # Get-AutomationVariable deserialises a variable into a Newtonsoft JObject, which indexes
        # case-sensitively and exposes no PowerShell properties. Bicep writes camelCase; the module
        # used to write PascalCase. Reading one way found the deployment's entries and returned an
        # empty key for every custom one, so all but the last were silently dropped - and a machine
        # tagged with a lost schedule reported ScheduleNotInCatalogue, which is indistinguishable
        # from a machine nobody onboarded. Found against a real Automation Account on 2026-09-11.
        It 'keeps every schedule from both variables, whichever case they were written in' {
            $line = @($scenarios['armed across two subscriptions'].lines | Where-Object { $_ -like 'Catalogue*' })[0]
            $line | Should -Match '4 schedule\(s\)'
            $line | Should -Match 'lab-down-now'
            $line | Should -Match 'lab-up-now'
        }

        It 'acts on a machine tagged with the schedule that used to disappear' {
            $record = @($scenarios['armed across two subscriptions'].records | Where-Object { $_.vm -eq 'vm-sched-down' })[0]
            $record.action | Should -Be 'Deallocate'
            $record.status | Should -Be 'Done'
        }

        It 'reads a catalogue holding exactly one schedule' {
            # The shape that broke while two or more worked: Automation returns a JArray, PowerShell
            # unrolls it out of the function, and one level further a JObject becomes its own
            # fields. A deployment shipping a single schedule would have failed every run.
            $line = @($scenarios['one schedule in each variable'].lines | Where-Object { $_ -like 'Catalogue*' })[0]
            $line | Should -Match '2 schedule\(s\)'
            $line | Should -Match 'lab-down-now'
            $scenarios['one schedule in each variable'].refused | Should -BeNullOrEmpty
        }

        It 'still acts on the machine that schedule covers' {
            $record = @($scenarios['one schedule in each variable'].records | Where-Object { $_.vm -eq 'vm-sched-down' })[0]
            $record.action | Should -Be 'Deallocate'
        }

        It 'stops the run when an entry has no readable name, rather than keying it on nothing' {
            $scenarios['catalogue entry with no name'].refused | Should -Match 'no readable name'
            $scenarios['catalogue entry with no name'].stops | Should -Be 0
        }
    }

    Context 'the dwell guard' {
        It 'holds back a machine it acted on minutes ago' {
            $scenarios['inside the dwell window'].stops | Should -Be 0
        }

        It "uses the schedule's own dwell rather than the run-wide one" {
            # office-hours-ch asks for 45; PM_MinimumDwellMinutes is 30. The longer one wins.
            ($scenarios['inside the dwell window'].lines -join ' ') | Should -Match '45 minute dwell'
        }

        It 'lets it through once the window has passed' {
            $scenarios['past the dwell window'].stops | Should -Be 1
        }

        It 'stops the run when the store cannot be read, rather than standing the guard down' {
            $scenarios['corrupt dwell store'].refused | Should -Match 'PM_LastActionAt'
            $scenarios['corrupt dwell store'].stops | Should -Be 0
        }
    }
}
