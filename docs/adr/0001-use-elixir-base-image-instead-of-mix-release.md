# Use Elixir Base Image Instead of Mix Release

## Context and Problem Statement

`save_it` is deployed as a Docker container, but the container is also used as an operational environment for debugging and maintenance. We want to keep `mix`, `elixir`, and Erlang tools available inside the running container, instead of producing a stripped runtime image that only contains a compiled release.

The question is how to package the application for Docker while keeping the image practical for day-to-day operations and avoiding unnecessary deployment complexity for this project.

## Considered Options

* Build a `mix release` artifact and run it in a slim runtime image
* Run the application directly from an Elixir base image
* Use a development-only image for debugging and a separate release image for deployment

## Decision Outcome

Chosen option: "Run the application directly from an Elixir base image", because it keeps the container operationally useful while still allowing a straightforward multi-stage Docker build with cached dependencies and compiled application code.

### Consequences

* Good, because the running container keeps `mix`, `elixir`, and `erl` available for inspection and operational tasks.
* Good, because the Docker build stays simple and matches the current project goal of shipping practical features with controlled complexity.
* Good, because we can still use multi-stage builds to improve cache reuse without switching to `mix release`.
* Bad, because the final image is larger than a minimal runtime-only release image.
* Bad, because the container contains more tooling than is strictly required for production execution.
