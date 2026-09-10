# Contributing

Thanks for looking at this. The bar is simple: **anything that changes state must have run against
a real target before it is merged**, and anything with logic has a test.

## Ground rules

- PowerShell 7.2 or newer. Windows PowerShell 5.1 is not a target.
- Approved verbs. Comment-based help on every public function, including the exact permissions it
  needs. One function per file.
- `-WhatIf` / `-Confirm` on every function that changes state. Read-only functions never prompt.
- Rules are pure functions in `Private/` with a Pester test on a fixture. No Azure or Graph call
  inside a rule.
- No secrets, tenant IDs, subscription IDs or customer names anywhere: not in code, tests, docs or
  issues.
- Tests: `Invoke-Pester ./tests`. Analyzer:
  `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`.
  Both must be clean. CI runs the same.

## Pull requests

- One topic per PR, imperative commit messages ("Add pending-reboot check", not "changes").
- Update `CHANGELOG.md` under *Unreleased*.
- If behaviour or setup changed, the README changes in the same PR.
- A claim of "verified" needs the run behind it in `docs/verification.md`.
