# Build-Time OpenAPI Export Without Full Spring Boot Startup

## Overview

ExtraToast services need a repeatable way to generate each service OpenAPI document from source code during the build without starting the full Spring Boot application. The current personal-stack reference flow depends on springdoc output from a running or fully initialized application path: assistant-api and knowledge-api run a tagged integration test against a fully loaded Spring context, while auth-api starts the boot jar briefly. The generated `openapi.json` then gates contract validation by comparing the fresh springdoc output with the committed file.

This feature specifies a springdoc-backed build-time export path that keeps springdoc as the source of truth for schema rendering, but replaces full application startup with a lightweight Spring MVC/springdoc slice. The slice must load controllers, controller advice, Jackson/validation/web configuration, service OpenAPI configuration, and springdoc WebMVC resources only. It must serialize the same JSON or YAML document that `/api/v1/api-docs` would return, without binding a server socket, running the application entry point, starting external infrastructure, or loading persistence/message/runtime adapters.

The capability should live with shared Kotlin/Spring test utilities, not in the contract drift checker and not in the external OpenAPI client plugin. personal-stack should adopt it behind the existing `exportOpenApiSpec` Gradle task name and `openapi.json` output path so `.github/workflows/contract-validate.yml` continues to run the same high-level validation flow while the export implementation changes.

## Reference Behavior

- personal-stack assistant-api currently depends on `org.springdoc:springdoc-openapi-starter-webmvc-ui:3.0.3`, registers `exportOpenApiSpec` as a Gradle `Test` task, includes only the `contract-export` JUnit tag, and writes `services/assistant-api/openapi.json`.
- That assistant-api export test builds `MockMvc` with `webAppContextSetup(webApplicationContext)`, performs `GET /api/v1/api-docs`, pretty-prints the JSON with ordered map entries, and writes the result to the path from `openapi.spec.output`.
- personal-stack knowledge-api mirrors the assistant-api tagged integration-test export shape.
- personal-stack auth-api currently registers `exportOpenApiSpec` as `JavaExec`, depends on `bootJar`, launches `org.springframework.boot.loader.launch.JarLauncher`, and sets an `openapi-export` profile plus `server.port=8099`.
- personal-stack contract validation runs `./gradlew :services:assistant-api:exportOpenApiSpec`, diffs `services/assistant-api/openapi.json`, then runs the assistant-ui type-generation drift check. This workflow must not be broken by the rollout.

## User Scenarios

- A backend maintainer changes assistant-api controllers or DTOs. Running `./gradlew :services:assistant-api:exportOpenApiSpec` regenerates `services/assistant-api/openapi.json` from code without starting the full assistant-api application, and the output matches the runtime springdoc endpoint for the same code.
- A CI run validates an assistant-api pull request. The existing contract validation workflow invokes the same export command and catches stale committed OpenAPI or generated TypeScript output without requiring databases, message brokers, Kubernetes clients, boot jars, or listening ports.
- A platform maintainer applies the same export pattern to knowledge-api and auth-api. Each service declares its service-specific controller slice and collaborator mocks, while the common exporter behavior remains shared and versioned.
- A reviewer evaluates the new technique before rollout. The spec, research table, and success criteria make clear why springdoc-backed slicing is preferred over springdoc Gradle/Maven plugins, full static scanners, or framework migration.

## Functional Requirements (FR-n)

- FR-1: The export capability must generate an OpenAPI JSON document from service code during a Gradle build without invoking `SpringApplication.run`, `bootRun`, `bootJar` execution, `JarLauncher`, `forkedSpringBootRun`, or any application main class.
- FR-2: The export capability must not start an embedded servlet container, bind an HTTP port, or require `server.port` configuration.
- FR-3: The export capability must not start service external dependencies, including databases, migration runners, message brokers, Redis, Vault, Kubernetes clients, upstream HTTP clients, or Testcontainers.
- FR-4: The export capability must use springdoc as the OpenAPI renderer for Spring MVC services so controller mappings, DTO schemas, validation annotations, OpenAPI annotations, controller advice, Jackson configuration, and service `OpenAPI` beans are interpreted by the same library family as runtime `/v3/api-docs` output.
- FR-5: The export capability must run through a lightweight web slice that includes only the service controllers selected for export, REST exception handlers, needed Spring MVC configuration, needed Jackson modules, validation support, service OpenAPI configuration, and springdoc WebMVC API auto-configuration.
- FR-6: The export capability must allow each service to provide mocks or no-op substitutes for controller collaborators so controller constructors can be instantiated without loading application services or infrastructure adapters.
- FR-7: The export capability must support the service's configured springdoc path, including personal-stack's `/api/v1/api-docs`, while remaining able to write directly to a declared output path such as `services/assistant-api/openapi.json`.
- FR-8: The export capability must support JSON output and may support YAML output; JSON output must be deterministic enough for source-controlled diffs.
- FR-9: JSON serialization must use a deterministic policy equivalent to ordered object keys plus stable pretty-printing, or a documented normalization step that produces byte-stable output for unchanged code.
- FR-10: Each service export must fail with a clear message when a controller dependency is missing, a required MVC/springdoc/Jackson bean is missing, the springdoc document cannot be serialized, or the output path cannot be written.
- FR-11: During initial personal-stack adoption, the assistant-api build-time slice output must be compared against the current full-context springdoc output and accepted only when the generated documents are byte-equal after the same deterministic formatting policy.
- FR-12: The personal-stack `:services:assistant-api:exportOpenApiSpec` task name, committed `services/assistant-api/openapi.json` path, and contract validation user guidance must remain stable during the first rollout.
- FR-13: The contract validation flow must continue to diff the freshly exported spec against the committed `openapi.json` before checking generated TypeScript contract output.
- FR-14: The rollout must document the per-service slice membership: controllers included, extra configuration imported, controller advice included, collaborator mocks provided, and any runtime-only beans intentionally excluded.
- FR-15: The export utility must expose enough hooks for service-specific OpenAPI customization beans and springdoc properties without forcing unrelated services to adopt assistant-api-specific configuration.
- FR-16: The export utility must be reusable for assistant-api, knowledge-api, and auth-api before the old full-context or boot-jar export paths are removed.
- FR-17: The shared utility must be consumed as test/build support and must not become a runtime dependency of service application artifacts.

## Success Criteria (SC-n, measurable)

- SC-1: On unchanged assistant-api code, the new build-time slice export produces `services/assistant-api/openapi.json` that is byte-equal to the current full-context springdoc export after the same deterministic formatter is applied.
- SC-2: Running `./gradlew :services:assistant-api:exportOpenApiSpec` after adoption completes without `bootJar`, `JarLauncher`, `bootRun`, `forkedSpringBootRun`, `SpringApplication.run`, Testcontainers startup, or a bound server port appearing in the execution path.
- SC-3: With a deliberate assistant-api controller or DTO contract change, `./gradlew :services:assistant-api:exportOpenApiSpec` changes `services/assistant-api/openapi.json`, and the existing contract validation diff reports that file as stale when it is not committed.
- SC-4: With a missing controller collaborator mock in the slice, the export task exits non-zero and names the missing dependency or bean class.
- SC-5: personal-stack `.github/workflows/contract-validate.yml` can keep invoking `./gradlew :services:assistant-api:exportOpenApiSpec` and then `pnpm --filter @personal-stack/assistant-ui contract:check` without changing the committed spec path or generated TypeScript comparison target.
- SC-6: knowledge-api and auth-api can each define a service slice and generate an OpenAPI document without copying assistant-api-specific exporter logic.
- SC-7: A reviewer can inspect one service slice manifest and determine which controllers, OpenAPI configuration, controller advice, Jackson modules, and mocks participate in that service's export.
- SC-8: A clean export run leaves no git diff in the committed spec path when service code has not changed.

## Assumptions

- personal-stack remains on Spring Boot 4.x and springdoc-openapi 3.x for the first rollout; the reference dependency observed on 2026-06-08 is springdoc `3.0.3`.
- The committed service OpenAPI document remains the reviewed API contract and remains source-controlled.
- The current runtime springdoc output remains the fidelity baseline until a reviewer approves the slice technique.
- Service controllers can be instantiated with mocks or no-op collaborators for documentation generation because springdoc inspects request mappings and type metadata rather than executing business logic.
- OpenAPI output is not intentionally dependent on runtime data from databases, message queues, Kubernetes, or upstream services.
- If a service has dynamic OpenAPI customizers that read runtime environment, those customizers can be provided deterministic test values in the slice.

## Edge Cases

- A controller uses a custom argument resolver, converter, formatter, or validation group that is present in runtime MVC configuration but omitted from the slice.
- A controller advice contributes response schemas or error media types and is accidentally left out of the export slice.
- Jackson module differences change Kotlin nullability, Java time formats, enum names, map schemas, or polymorphic schema rendering.
- Security configuration blocks the docs path in the slice even though the runtime service allows `/api/v1/api-docs`.
- A service OpenAPI bean declares server URLs, security schemes, tags, or components that are not discovered unless the service `OpenApiConfig` is imported.
- springdoc conditional scanning differs when the slice limits packages, controllers, paths, or grouped APIs.
- Runtime-only actuator, websocket, repository, or functional endpoints appear in full runtime output but are intentionally excluded from a REST controller export.
- OpenAPI operation ordering, schema ordering, or pretty-printing changes after a springdoc/Jackson upgrade.
- A controller constructor has a required collaborator that should be mocked for documentation generation but has side effects during bean construction.
- A service later adds WebFlux or functional routes; this specification covers Spring MVC controller export first.

## Key Entities

- Build-Time OpenAPI Export: A Gradle-invoked process that writes a service OpenAPI document from compiled service code without starting the full application.
- Service OpenAPI Slice: The minimal Spring MVC/springdoc test context for one service's REST contract.
- Slice Manifest: The per-service declaration of controllers, controller advice, OpenAPI configuration, Jackson/MVC extras, springdoc properties, and collaborator mocks used by the export.
- Runtime Baseline: The current full-context or running-service springdoc output used to prove the slice has equivalent fidelity before rollout.
- Deterministic Serializer: The JSON/YAML formatting and ordering policy used before writing the committed spec.
- Export Task: The consumer-facing Gradle task, such as `:services:assistant-api:exportOpenApiSpec`, that writes the committed spec path.
- Contract Validation Flow: The CI and local validation sequence that exports the spec, diffs the committed OpenAPI document, and checks generated client artifacts.

## Researched Options

Research date: 2026-06-08.

| Option | Source and version/date | Fidelity to runtime springdoc | Boots or starts the app? | Effort | Spring Boot 4 compatibility | Maintenance risk |
| --- | --- | --- | --- | --- | --- | --- |
| springdoc-openapi Gradle plugin | Gradle Plugin Portal lists `org.springdoc.openapi-gradle-plugin` `1.9.0`, created 2024-06-22; springdoc plugin docs were last updated 2025-05-04; plugin README says `generateOpenApiDocs` starts the Spring Boot app through `forkedSpringBootRun` and then downloads the docs URL. Sources: [Gradle Portal](https://plugins.gradle.org/plugin/org.springdoc.openapi-gradle-plugin), [springdoc plugins](https://springdoc.org/plugins.html), [plugin README](https://github.com/springdoc/springdoc-openapi-gradle-plugin). | High, because it downloads the same endpoint from the running app. | Yes. It forks and starts the Spring Boot application, then calls the docs endpoint. That counts as booting. | Low setup, but conflicts with this feature's no-full-startup goal. | Unclear for Boot 4. The plugin is current at `1.9.0` but examples still show older Boot versions; springdoc runtime `3.0.3` supports Boot 4. | Medium. Simple to use, but startup timing, profiles, ports, and environment dependencies remain in the export path. |
| springdoc-openapi Maven plugin | springdoc docs describe Maven plugin `1.5`; Maven Central/Javadoc list `1.5` current, published 2025-05-04. It works with `spring-boot-maven-plugin` during integration tests. Sources: [springdoc plugins](https://springdoc.org/plugins.html), [Javadoc index](https://javadoc.io/doc/org.springdoc/springdoc-openapi-maven-plugin/latest/index.html), [Maven Central directory](https://repo1.maven.org/maven2/org/springdoc/springdoc-openapi-maven-plugin/1.5/). | High, because it fetches the running app's docs endpoint. | Yes. The documented setup starts and stops the Spring Boot application around generation. That counts as booting. | Low for Maven services; not directly useful for personal-stack Gradle services. | Runtime springdoc supports Boot 4, but the plugin still depends on starting the app and is Maven-specific. | Medium. It automates the current boot-based pattern rather than removing it. |
| Current personal-stack full-context MockMvc export | Observed locally on 2026-06-08: assistant-api and knowledge-api tagged export tests use `webAppContextSetup` and full integration test bases; auth-api launches the boot jar. | High for assistant-api/knowledge-api because it calls the springdoc endpoint from the full context; high for auth-api because it runs the boot jar. | assistant-api/knowledge-api do not bind a server socket, but they still load the full Spring context. auth-api starts the application. Both violate the no-full-application-startup objective. | Already present for some services. | Works today with Boot 4.0.6 and springdoc 3.0.3 in personal-stack. | High. Full context can pull in databases, messaging, migrations, runtime adapters, and slow or brittle test infrastructure. |
| Springdoc-backed Spring MVC slice export | Spring Boot 4.0.6 `@WebMvcTest` focuses on Spring MVC components and auto-configures `MockMvc`; Spring Boot testing docs say the default mock web environment does not start embedded servers; Spring Framework MockMvc docs distinguish `webAppContextSetup` from `standaloneSetup` and note that a web app context tests actual MVC configuration. Sources: [WebMvcTest 4.0.6 Javadoc](https://docs.spring.io/spring-boot/api/java/org/springframework/boot/webmvc/test/autoconfigure/WebMvcTest.html), [Spring Boot testing reference](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html), [Spring MockMvc setup choices](https://docs.spring.io/spring/reference/6.1/testing/spring-mvc-test-framework/server-setup-options.html). springdoc `3.0.3` docs list WebMVC API/UI starters for Boot integration. Source: [springdoc v4 docs](https://springdoc.org/v4/). | High if the slice includes the same controllers, OpenAPI config, Jackson modules, controller advice, MVC extensions, and springdoc customizers. Must be proven by byte-equality against assistant-api runtime output first. | No full app startup and no server socket. It creates a narrow Spring test context. | Medium. Requires per-service slice manifests and mocks, plus a shared exporter helper. | Good. `@WebMvcTest` is documented for Boot 4.0.6, and springdoc `3.0.3` is current for the Boot 4 line. springdoc `v3.0.0` release notes include the Boot 4 upgrade. Source: [springdoc releases](https://github.com/springdoc/springdoc-openapi/releases). | Medium-low after the first baseline proof. Risk is missed runtime beans causing spec drift; the slice manifest and byte-equality acceptance gate manage that risk. |
| Standalone MockMvc with manually instantiated controllers | Spring Framework MockMvc docs describe `standaloneSetup` as closer to a unit test that avoids loading Spring configuration. Source: [Spring MockMvc setup choices](https://docs.spring.io/spring/reference/6.1/testing/spring-mvc-test-framework/server-setup-options.html). | Medium-low. It can document simple controllers, but it is easy to miss actual MVC config, advice, argument resolvers, converters, Jackson modules, and springdoc auto-configuration. | No. | Medium-high because much of MVC/springdoc wiring must be recreated manually. | Compatible with Spring Framework, but springdoc fidelity is weaker than a slice context. | High. Manual wiring can silently diverge from runtime behavior. |
| Fully static annotation scanning or compile-time generation for Spring MVC | Swagger Maven Plugin is intended for JAX-RS services and requires configured JAX-RS resource packages. Source: [Swagger Maven Plugin](https://github.com/openapi-tools/swagger-maven-plugin). SmallRye has Spring/JAX-RS/Vert.x entry points and build plugins; its Gradle plugin `4.3.3` was created 2026-05-13. Sources: [SmallRye repo](https://github.com/smallrye/smallrye-open-api), [SmallRye Gradle Portal](https://plugins.gradle.org/plugin/io.smallrye.openapi). OpenAPI Generator's Spring generator is primarily spec-first and can generate Spring servers from an existing spec. Source: [OpenAPI Generator Spring](https://openapi-generator.tech/docs/generators/spring/). | Low to medium for personal-stack because the runtime source of truth is springdoc's Spring MVC/Jackson/application-context interpretation. Static scanners may miss Boot conditional config, Kotlin/Jackson behavior, controller advice, security metadata, or springdoc customizers. | No. | Medium-high. Would require adopting a different annotation model or accepting output differences. | Mixed. Some tools are current, but not proven to reproduce springdoc 3.x Boot 4 output. | High. Lower runtime fidelity and likely recurring drift from the reviewed springdoc baseline. |
| Micronaut compile-time OpenAPI | Micronaut OpenAPI `5.2.0` docs say it produces OpenAPI 3.x YAML at compilation time using regular Micronaut annotations and Javadoc comments, with `micronaut-openapi` on the annotation processor path. Source: [Micronaut OpenAPI 5.2.0](https://micronaut-projects.github.io/micronaut-openapi/5.2.0/guide/). | High inside Micronaut because the framework is designed around compile-time metadata. Low for current Spring services unless they migrate frameworks. | No full runtime app startup for generation. | Not applicable to current services without a framework migration. | Not a Spring Boot 4 solution. | Low in Micronaut, high as a migration strategy for personal-stack. |
| Quarkus SmallRye OpenAPI build-time storage | Quarkus SmallRye OpenAPI extension page lists latest `3.36.1`, released 2026-06-03. Quarkus docs say generated schema documents can be stored on build, and that extra run stages execute at build time to better match runtime output. Sources: [Quarkus extension](https://quarkus.io/extensions/io.quarkus/quarkus-smallrye-openapi/), [Quarkus OpenAPI guide](https://quarkus.io/guides/openapi-swaggerui). | High inside Quarkus because build-time augmentation is part of the framework model. Low for current Spring services unless they migrate frameworks. | No normal runtime server for stored schema generation, though Quarkus performs framework-specific build-time augmentation. | Not applicable to current services without a framework migration. | Not a Spring Boot 4 solution. | Low in Quarkus, high as a migration strategy for personal-stack. |

## Recommended Approach

Use a springdoc-backed Spring MVC slice/test export. The shared helper should create or participate in a narrow web slice, invoke the springdoc WebMVC docs path through `MockMvc` or the equivalent springdoc resource in that slice, normalize output deterministically, and write the declared spec file. The first personal-stack adoption must prove assistant-api byte-equality against the current full-context springdoc output before the old export path is replaced.

This approach best satisfies the constraints:

- It preserves springdoc as the renderer, which gives much higher fidelity than static scanners for Spring MVC/Kotlin/Jackson behavior.
- It avoids the springdoc Gradle/Maven plugin limitation because those plugins start or fork the app before downloading the docs endpoint.
- It avoids a server socket and full application graph while still using real Spring MVC and springdoc configuration, unlike pure `standaloneSetup`.
- It stays inside the current Spring Boot 4 / springdoc 3 line used by personal-stack.
- It can be introduced behind the existing `exportOpenApiSpec` task and CI workflow, limiting rollout risk.

The accepted shape should be:

- A service-local slice manifest selects the controllers and imports service OpenAPI configuration, controller advice, Jackson/MVC extras, validation support, and springdoc WebMVC API configuration.
- Collaborator mocks or no-op beans satisfy controller constructors without loading application services or infrastructure.
- The exporter uses the configured docs path, usually `/api/v1/api-docs`, and writes `openapi.json` or `.yaml`.
- The output writer applies stable formatting and ordering.
- A baseline test or rollout command compares slice output to the current runtime springdoc output for assistant-api before CI switches to the slice export implementation.

## Home & Rollout

### Recommended Home

Place the Spring-specific export helper in `ExtraToast/kotlin-spring-commons`, module `test-support`, under an OpenAPI test-support package. This module already exists as a publishable shared test-support artifact and has Spring Boot test plus Spring Test dependencies. The capability is a test/build utility for Kotlin/Spring services, not a runtime service dependency.

The optional Gradle task wiring can remain service-local during the first rollout. If repeated task registration later becomes noisy, that wiring belongs in shared Gradle conventions, while the springdoc/MVC exporter helper still belongs in `kotlin-spring-commons:test-support`.

Do not put the renderer helper in `api-contract-checks`. That repository owns contract drift orchestration: run an export command, diff the committed spec, regenerate TypeScript artifacts, and report drift. It should stay language-agnostic and should not take Spring Boot, springdoc, MockMvc, or Kotlin test dependencies.

Do not put this in `openapi-client-gradle`. That repository is specified for typed client generation from external OpenAPI documents supplied by consumers. It is not responsible for generating internal Spring service specs from code.

### personal-stack Rollout

1. Add the shared exporter helper to `kotlin-spring-commons:test-support` and publish a versioned artifact.
2. Add the helper as a test-support dependency for assistant-api.
3. Create an assistant-api slice export test that imports only the controller set, `OpenApiConfig`, REST exception handlers, needed Jackson/MVC configuration, springdoc WebMVC API configuration, and mocks/no-op collaborators.
4. Run both the existing full-context export and the new slice export for assistant-api in a one-time rollout check. Accept the slice only when the formatted documents are byte-equal.
5. Change `:services:assistant-api:exportOpenApiSpec` to run the slice export test while keeping the task name, group, `openapi.spec.output` property, and `services/assistant-api/openapi.json` output stable.
6. Keep `.github/workflows/contract-validate.yml` behavior stable: export assistant-api, diff `services/assistant-api/openapi.json`, then run the assistant-ui type-generation check.
7. After assistant-api is stable, apply the same pattern to knowledge-api and auth-api. auth-api should be prioritized next because its current `JavaExec` task starts the boot jar.
8. Remove or quarantine full-context/boot-jar export paths only after each service has a passing byte-equality baseline and the existing drift workflow remains green.

## Out of Scope

- Implementing the exporter helper, slice tests, Gradle task changes, or personal-stack rollout in this spec PR.
- Changing service controllers, DTOs, security rules, OpenAPI annotations, or generated client artifacts.
- Replacing springdoc as the runtime OpenAPI renderer for Spring services.
- Migrating personal-stack services to Micronaut, Quarkus, JAX-RS, or a spec-first server generator.
- Replacing `api-contract-checks` drift validation or `openapi-typescript` output validation.
- Generating third-party client code or refreshing external vendor specs.
