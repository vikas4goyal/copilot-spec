# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `.spec/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/spec.plan` command. See `.spec/specs/templates/plan-template.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Java 25 (Spring Boot 3.x required per constitution)  
**Primary Dependencies**: Spring Boot 3.x, Spring Security (OAuth2/JWT), Spring Data JPA, Liquibase/Flyway  
**Storage**: PostgreSQL 15+ (primary), Redis for caching (optional)  
**Testing**: JUnit 5, Mockito, AssertJ, TestContainers; Coverage MUST be ≥80% (enforced by JaCoCo)  
**Target Platform**: Linux server / Docker containers  
**Project Type**: REST API web-service (Spring Boot controllers required per constitution)  
**Performance Goals**: [e.g., p95 latency <200ms, 1000 req/s throughput - specify or NEEDS CLARIFICATION]  
**Constraints**: [e.g., OAuth2 authentication required, SQL injection prevention, structured logging mandatory per constitution - or additional constraints if needed]  
**Scale/Scope**: [e.g., 10k users, specify expected endpoints/data volumes - or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitutional requirements per `.spec/memory/constitution.md`:
- ✅ All features exposed via REST endpoints (HTTP methods, RESTful paths)
- ✅ API contracts defined before implementation (in `contracts/` directory)
- ✅ Unit test coverage MUST be ≥80% (measured by JaCoCo, enforced in Maven verify phase)
- ✅ Every endpoint has authentication & authorization (`@PreAuthorize` or OAuth2)
- ✅ Structured JSON logging with trace IDs (SLF4J + Log4j2/Logback)
- ✅ Java 25, Spring Boot 3.x, PostgreSQL, Docker required
- [Mark constitution check items as verified or document any justified exceptions]

## Project Structure

### Documentation (this feature)

```text
.spec/specs/[###-feature]/
├── plan.md              # This file (/spec.plan command output)
├── research.md          # Phase 0 output (/spec.plan command)
├── data-model.md        # Phase 1 output (/spec.plan command)
├── quickstart.md        # Phase 1 output (/spec.plan command)
├── contracts/           # Phase 1 output (/spec.plan command)
└── tasks.md             # Phase 2 output (/spec.tasks command - NOT created by /spec.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: For Spring Boot REST API projects, follow the structure in constitution.md.
  Replace this tree with the actual feature's folder structure.
-->

```text
# Spring Boot REST API (DEFAULT)
src/
├── main/java/com/[org]/[project]/
│   ├── api/
│   │   ├── controller/          # Spring REST controllers
│   │   ├── dto/                 # Request/response DTOs
│   │   └── exception/           # Exception handlers
│   ├── domain/
│   │   ├── entity/              # JPA entities
│   │   ├── model/               # Business domain models
│   │   └── repository/          # Data repositories
│   ├── service/                 # Business logic
│   ├── config/                  # Spring configuration
│   ├── security/                # Security config
│   └── util/                    # Utilities
├── main/resources/
│   ├── application.yml
│   ├── application-dev.yml
│   ├── application-prod.yml
│   ├── db/migration/            # Liquibase/Flyway SQL migrations
│   └── contracts/               # API contract definitions (OpenAPI)
└── test/java/com/[org]/[project]/
    ├── api/
    │   ├── controller/          # REST controller unit tests
    │   └── contract/            # Contract/endpoint integration tests
    ├── service/                 # Service unit tests
    ├── repository/              # Repository tests
    └── util/                    # Utility tests

pom.xml                          # Maven configuration
Dockerfile                       # Docker image definition
docker-compose.yml              # Local development (PostgreSQL, etc.)
README.md                        # Quickstart & documentation
```

**Structure Decision**: [Confirm this structure or document custom layout aligned with constitution requirements]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
