# Manual tests

Runs that need a real tenant, a browser or a lab, and therefore have no business in CI. Each script
here is meant to be read before it is run, and to say plainly what it touches.

Rules that came out of doing this badly once:

- **Name the objects the run creates, and delete them at the end.** A test that leaves a custom role
  behind is a finding in somebody's next audit.
- **Never test the write path against an account that matters.** Use a throwaway principal that
  holds nothing else, and say in the script which one it is.
- **Print a PASS/FAIL line per check.** A wall of output nobody reads is not a test.
- **Record the run in `docs/verification.md`**: what ran, on what, how long it took, what it found.
  Nothing goes in the README that has not been through this folder.

Suggested files:

| File | What it proves |
|---|---|
| `real-tenant-read-path.ps1` | The collectors see what the portal sees, and the counts match. |
| `real-tenant-write-path.ps1` | Remove refuses what it must, backs up before it acts, and Restore puts it back. |
| `report-ui.py` | The report's filters, sorting, selection and export work in a real browser. |
