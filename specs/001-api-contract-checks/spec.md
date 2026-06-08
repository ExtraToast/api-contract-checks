# Shared API Contract Drift Checks

## Overview

ExtraToast/api-contract-checks defines shared internal checks for API contract drift. The feature exists so service repositories can prevent API changes from landing unless the committed OpenAPI spec and the generated TypeScript contract artifacts are updated in the same change.

The immediate reference behavior is the personal-stack contract validation flow for assistant-api and assistant-ui: an exported Spring OpenAPI spec is compared with `services/assistant-api/openapi.json`, then generated TypeScript output is compared with `services/assistant-ui/src/api/generated.ts`. The website repository has analogous OpenAPI generation and frontend client validation for `services/api/openapi.json` and the Blueshell frontend client outputs. This repository supplies the reusable contract-check specification for those consumers rather than duplicating drift logic in each repository.

## User Scenarios

- A personal-stack service maintainer changes assistant-api controllers or DTOs. Validation exports the current OpenAPI spec and fails if it no longer matches the committed `services/assistant-api/openapi.json`, preventing stale service contracts from reaching the continuously deployed environment.
- A frontend maintainer updates API usage but does not refresh generated TypeScript contract artifacts. Validation regenerates the declared artifacts and fails when the committed output is stale, making the missing regeneration step explicit.
- A website maintainer changes `services/api` and runs the same class of contract check for `services/api/openapi.json` and the generated Blueshell frontend client paths. Drift is reported consistently even though the service repository uses different generation commands and output paths.
- A platform maintainer updates the shared check version in a consumer repository. The consumer pins a released artifact from this repository, receives version update proposals through Renovate, and does not assign a release version to personal-stack itself.

## Functional Requirements (FR-n)

- FR-1: The feature must define a reusable contract-drift check owned by ExtraToast/api-contract-checks and consumable by personal-stack and website as a versioned artifact.
- FR-2: The reusable check must be usable from local validation and CI validation in a consumer repository through at least one supported invocation surface suitable for command-line, script, or composite-action use.
- FR-3: The reusable check must be parameterized per service profile rather than hard-coded to assistant-api, assistant-ui, personal-stack, or website paths.
- FR-4: Each service profile must identify the service name, committed OpenAPI spec path, spec export behavior, generated TypeScript artifact path or paths, type regeneration behavior, and human-readable regeneration guidance.
- FR-5: The reusable check must fail when the exported OpenAPI spec for a service profile differs from the committed spec after any profile-declared normalization rules are applied.
- FR-6: The reusable check must fail when regenerated TypeScript OpenAPI contract artifacts, including openapi-typescript output where used, differ from the committed generated artifacts.
- FR-7: The reusable check must report the failing service profile, failing stage, affected file path or paths, and local regeneration command guidance whenever drift is detected.
- FR-8: The reusable check must make the diff or equivalent file comparison evidence available in validation output so the required commit update is inspectable.
- FR-9: The reusable check must support multiple service profiles in one consumer repository and must allow validation of all profiles or a named subset.
- FR-10: The reusable check must treat missing committed spec files, missing committed generated artifacts, failed export commands, and failed regeneration commands as validation failures with distinct messages.
- FR-11: The reusable check must allow service profiles to include deterministic banner, provenance, or post-generation normalization steps before comparison so generated headers do not create false drift.
- FR-12: The reusable check must keep first-party per-change validation separate from third-party upstream OpenAPI refreshes unless a service profile explicitly opts into external spec inputs.
- FR-13: The distribution model must use short artifact coordinates and must not use doubled plugin-marker names or repeated marker terms in both coordinate group and artifact identifiers.
- FR-14: Consumers must pin versions of the shared artifact and receive updates through Renovate-managed version bumps.
- FR-15: personal-stack must remain continuously auto-deployed and must not become versioned as part of adopting this shared check.
- FR-16: Consumer-facing documentation must describe the required profile fields, success and failure meanings, and the regeneration commands a maintainer should run after an API change.

## Success Criteria (SC-n, measurable)

- SC-1: Given a personal-stack assistant-api profile and a changed exported OpenAPI spec, validation exits non-zero and names `services/assistant-api/openapi.json` plus the local spec regeneration command.
- SC-2: Given a personal-stack assistant-ui profile with a current committed spec but stale generated TypeScript output, validation exits non-zero and names `services/assistant-ui/src/api/generated.ts` plus the local type regeneration command.
- SC-3: Given a clean personal-stack assistant-api and assistant-ui contract state, validation exits zero and leaves no diff in the declared committed spec and generated TypeScript artifact paths.
- SC-4: Given a website profile and a stale Blueshell OpenAPI spec or generated frontend client output, validation exits non-zero and reports every declared website path included in the failed comparison.
- SC-5: Given a consumer repository with two configured service profiles, validation can run both profiles in one invocation and can run either profile by name without changing the profile definitions.
- SC-6: Given any drift failure, validation output includes the service profile name, failing stage, affected path or paths, and at least one maintainer-facing regeneration instruction.
- SC-7: Given a released shared artifact, personal-stack and website can each pin one artifact version and receive Renovate version update proposals without adding a personal-stack application version.
- SC-8: Given proposed artifact coordinates, the coordinate string uses short identifiers and has no repeated marker term across group and artifact segments.

## Assumptions

- Consuming repositories own the commands that export their OpenAPI specs and regenerate their TypeScript contract artifacts.
- Committed OpenAPI specs and generated TypeScript artifacts remain source-controlled in the consumer repositories.
- The shared check validates first-party service contracts by default; external upstream API specs are validated only when explicitly configured by a service profile.
- The exact artifact packaging channel is selected during planning, but the observable contract is a Renovate-pinned versioned artifact with short coordinates.
- personal-stack continues to deploy from its existing continuous deployment flow and does not gain application release versions for this feature.

## Edge Cases

- A spec export command succeeds but produces nondeterministic ordering or formatting.
- A generated TypeScript artifact includes a banner or provenance block that must be applied before comparison.
- A service profile declares multiple generated output paths instead of one generated file.
- A declared committed spec or generated artifact is deleted, renamed, or moved without updating the service profile.
- A service has a valid OpenAPI spec drift but no TypeScript consumer yet.
- A third-party upstream spec changes independently of a first-party service change.
- A consumer repository has both Gradle and Node/Yarn/pnpm tooling in the same validation flow.

## Key Entities

- Consumer Repository: A repository such as personal-stack or website that pins and invokes the shared contract-drift check.
- Service Profile: A named set of per-service paths, generation behaviors, comparison targets, and maintainer guidance.
- Committed OpenAPI Spec: The source-controlled OpenAPI document that represents the reviewed API contract.
- Exported OpenAPI Spec: The current spec emitted from the service under validation.
- Generated TypeScript Artifact: A source-controlled TypeScript contract output generated from the committed OpenAPI spec.
- Drift Report: The validation failure output that identifies what changed and how to regenerate the committed artifacts.
- Versioned Artifact: The released deliverable from ExtraToast/api-contract-checks that consumers pin through Renovate.

## Out of Scope

- Implementing the reusable check, CLI, script, composite action, or release pipeline.
- Rewriting personal-stack or website OpenAPI generation commands.
- Changing service controllers, DTOs, or generated client contents in consumer repositories.
- Publishing or deploying personal-stack, website, or any service application.
- Assigning application versions to personal-stack.
- Managing third-party upstream OpenAPI update policy beyond allowing explicit opt-in profiles.
- Replacing consumer CI systems or their existing language/toolchain setup actions.
