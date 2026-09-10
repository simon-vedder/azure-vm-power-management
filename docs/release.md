# Releasing

1. `CHANGELOG.md`: move *Unreleased* under the new version with today's date.
2. `src/AzureVMPowerManagement/AzureVMPowerManagement.psd1`: set `ModuleVersion`; drop `Prerelease` for a stable
   release or keep it for `-preview`.
3. Run locally: `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
   and `Invoke-Pester ./tests`. Both clean.
4. Rebuild the command reference and commit it: `./tools/New-CommandReference.ps1`. CI runs it with
   `-Check` and refuses a stale one.
5. Commit on a branch, open the PR, merge to `main`.
6. Tag: `git tag v0.1.0 && git push origin v0.1.0`. The release workflow refuses a tag that does not
   match the manifest version, runs the analyzer and the tests, publishes to the PowerShell Gallery
   with the `PSGALLERY_API_KEY` secret and attaches the module zip to the GitHub release.
7. Check the Gallery listing (`Find-Module AzureVMPowerManagement -AllowPrerelease`) and the GitHub release.
   Users of `deploy/main.bicep` point `moduleVersion` at the new version; the module link resolves
   to the Gallery package by default.
8. Deploy the Bicep into the lab once against the new version before you tell anyone. A runbook
   that cannot import its module fails at 3am, not in CI.

The Gallery API key is scoped to this package and expires after a year. Rotate it in the repository
secret `PSGALLERY_API_KEY` before then; the release workflow fails on the next tag without it.
Note the expiry date here: `<date>`, and put a reminder somewhere that will actually fire.

What never goes into a release: lab resource ids, subscription or tenant ids, SAS URLs, credentials.
