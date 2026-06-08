# Bootstrapping a new ExtraToast repo from this template

1. **Create the repo from the template** (GitHub "Use this template", or
   `gh repo create ExtraToast/<name> --template ExtraToast/repo-template
   --private`).
2. **Apply the branch ruleset** so `Pipeline Complete` is required:
   ```bash
   scripts/apply-ruleset.sh ExtraToast/<name>
   ```
3. **Wire the real CI**: replace the placeholder `lint`/`test`/`build` jobs in
   `.github/workflows/ci.yml` with this repo's actual jobs (or calls into
   reusable workflows from `ExtraToast/github-workflows`). Keep the
   `pipeline-complete` aggregator and list every gating job in its `needs:`.
4. **Set the release artifact**: edit `release.yml`'s `publish` job for this
   repo's artifact type (Maven / npm / image), and set `release-type` in
   `release-please-config.json` accordingly.
5. **Set the starting version** in `.release-please-manifest.json`.
6. **CODEOWNERS / README**: adjust owners and replace this README's body with
   the repo's purpose.
7. **Enable Renovate** (GitHub App) on the repo; `renovate.json` is already
   present.

## What this template provides

| File | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | One CI pipeline ending in the `Pipeline Complete` gate |
| `.github/workflows/release.yml` | release-please tag/release + artifact publish |
| `.github/rulesets/main.json` + `scripts/apply-ruleset.sh` | Org ruleset as code (requires `Pipeline Complete`) |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR template (tracking + verification + versioning) |
| `.github/ISSUE_TEMPLATE/*` | Bug / feature / task forms |
| `.github/CODEOWNERS`, `dependabot.yml`, `renovate.json` | Ownership + dependency automation |
| `release-please-config.json`, `.release-please-manifest.json` | Versioning state |
| `CONTRIBUTING.md`, `VERSIONING.md`, `SECURITY.md` | Conventions |
| `.editorconfig`, `.gitignore`, `.gitleaks.toml`, `LICENSE` | Baseline hygiene |
