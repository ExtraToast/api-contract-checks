# Security Policy

## Reporting a vulnerability

Report suspected vulnerabilities privately via GitHub Security Advisories
("Report a vulnerability" on the repository's Security tab), not as a public
issue. A maintainer will acknowledge and triage.

## Secrets

- No secrets in the repository. `gitleaks` runs in CI (part of `Pipeline
  Complete`); a hit fails the pipeline.
- Runtime secrets come from Vault, never from committed files.
- Example/fixture credentials must be obviously non-real and live in
  `*.example.*` files (see `.gitleaks.toml`).

## Supported versions

Only the latest released `vX.Y.Z` is supported. Pin exact versions (see
`VERSIONING.md`); do not depend on a moving branch.
