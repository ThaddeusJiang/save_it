# Keep Runtime Logs Inline and Simple

## Context and Problem Statement

`save_it` uses runtime logs mostly for local operation, deployment diagnosis, and lightweight visibility into important events. Recent resource creation logging introduced a private helper and extra `kind` metadata around a short success message.

That abstraction made a simple log event harder to read and maintain. The question is how much structure runtime logs should carry before the project has a concrete need for routing, dashboards, or automated log processing.

## Considered Options

* Keep dedicated helper functions for repeated log events
* Keep log calls inline and include only useful message fields
* Introduce a custom logging abstraction for structured events

## Decision Outcome

Chosen option: "Keep log calls inline and include only useful message fields", because it keeps runtime output easy to read, avoids log-only indirection, and matches the project's bias toward controlled complexity.

Do not extract helper functions only to wrap `Logger` calls. Do not add metadata such as `kind` unless it is needed by an actual filtering, routing, or operational workflow.

### Consequences

* Good, because logs stay close to the workflow that emits them.
* Good, because simple events such as `resource_created source=url_download file_name=...` remain easy to scan in terminals and deployment logs.
* Good, because the project avoids custom logging layers before there is a concrete operational need.
* Bad, because repeated log message fields may appear in multiple call sites.
* Bad, because adding structured log filtering later may require revisiting existing inline log calls.
