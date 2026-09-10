# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository. Do not open a public issue for
anything that could be exploited. You will get an answer within a few days.

## What to never put in an issue

Tenant IDs, subscription IDs, resource IDs, principal names from production, raw command output.
Redact first.

## Design notes relevant to security

- The read path is read-only and asks for read scopes only. The write path is opt-in and prompts
  per object.
- Every object is written to a local backup file before it is changed.
- Objects marked protected (break-glass accounts, PIM-managed assignments) are reported, never touched.
- No telemetry, no phone-home.
- Runs under a managed identity the customer owns; the project never holds credentials. The custom
  role in `deploy/main.bicep` lists exactly the actions the runbook needs.
