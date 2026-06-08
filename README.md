# api-contract-checks

Shared drift checks for committed OpenAPI specs and generated TypeScript
contract artifacts.

The check follows the personal-stack assistant contract pattern:

- export the current service OpenAPI document into the committed spec path
- compare that fresh spec with the source-controlled file
- regenerate generated TypeScript contract output, including
  `openapi-typescript` output where used
- compare the fresh generated artifacts with the source-controlled files

Drift fails validation with the profile name, stage, affected path, diff output,
and the maintainer-facing regeneration command.

## CLI

Run a single profile directly:

```bash
scripts/api-contract-checks.sh \
  --profile assistant-api \
  --spec-path services/assistant-api/openapi.json \
  --export-command './gradlew :services:assistant-api:exportOpenApiSpec' \
  --types-path services/assistant-ui/src/api/generated.ts \
  --types-generate-command 'pnpm --filter @personal-stack/assistant-ui contract:generate' \
  --guidance './gradlew :services:assistant-api:exportOpenApiSpec && pnpm --filter @personal-stack/assistant-ui contract:generate'
```

Run every profile in a directory, or one named subset:

```bash
scripts/api-contract-checks.sh --profiles-dir .github/contract-profiles
scripts/api-contract-checks.sh --profiles-dir .github/contract-profiles --only assistant-api
```

Profile files are trusted Bash fragments:

```bash
PROFILE_NAME="assistant-api"
SPEC_PATH="services/assistant-api/openapi.json"
SPEC_EXPORT_COMMAND="./gradlew :services:assistant-api:exportOpenApiSpec"
SPEC_NORMALIZE_COMMAND=""
TYPES_PATHS=("services/assistant-ui/src/api/generated.ts")
TYPES_GENERATE_COMMAND="pnpm --filter @personal-stack/assistant-ui contract:generate"
TYPES_NORMALIZE_COMMAND=""
GUIDANCE="./gradlew :services:assistant-api:exportOpenApiSpec && pnpm --filter @personal-stack/assistant-ui contract:generate"
```

Paths are resolved from the command working directory. Export and generation
commands must write their declared committed paths in place. Optional
normalization commands run after generation; they receive
`CONTRACT_PROFILE`, `CONTRACT_STAGE`, `CONTRACT_SPEC_PATH`, and
`CONTRACT_TYPES_PATHS` in the environment.

## Composite Action

Consumers pin the released action tag:

```yaml
- uses: ExtraToast/api-contract-checks@v0.1.0
  with:
    profile: assistant-api
    spec-path: services/assistant-api/openapi.json
    export-command: ./gradlew :services:assistant-api:exportOpenApiSpec
    types-paths: services/assistant-ui/src/api/generated.ts
    types-generate-command: pnpm --filter @personal-stack/assistant-ui contract:generate
    guidance: ./gradlew :services:assistant-api:exportOpenApiSpec && pnpm --filter @personal-stack/assistant-ui contract:generate
```

The artifact coordinate is intentionally short:
`ExtraToast/api-contract-checks@vX.Y.Z`.

## Failure Meanings

- `configuration`: a required profile field is missing or inconsistent.
- `openapi-spec`: the committed spec is missing, the export command failed, the
  normalization command failed, or the exported spec differs.
- `types`: a committed generated artifact is missing, the generation command
  failed, the normalization command failed, or regenerated output differs.

Every drift failure prints a recursive unified diff. Missing files and command
failures are reported separately from content drift.

## Example

`examples/basic` contains a minimal profile and generator pair. The self-test
covers a clean run, spec drift, and generated TypeScript drift:

```bash
tests/self-test.sh
```

## Release

Releases are managed by release-please. Consumers pin exact release tags and
receive Renovate update proposals for new versions. Adopting this check does
not require versioning a consuming application repository.
