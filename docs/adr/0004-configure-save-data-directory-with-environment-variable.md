# Configure Save Data Directory with Environment Variable

## Context and Problem Statement

`save_it` writes downloaded media cache files and per-chat settings to local disk. The path must differ between local development and container deployments: local runs should default to `./data`, while the Docker image should default to `/data`.

The question is how operators should configure this path without adding unnecessary startup complexity.

## Considered Options

* Configure the save data directory with a runtime environment variable
* Add a `--data-dir` command-line argument
* Keep hard-coded paths in `SaveIt.FileHelper`
* Read the path from a separate config file

## Decision Outcome

Chosen option: "Configure the save data directory with a runtime environment variable", because it matches the existing `config/runtime.exs` pattern, works naturally in Docker and hosting platforms, and keeps the application startup command simple.

The application reads `SAVE_IT_DATA_DIR`, defaults to `./data` when it is unset, and the Docker image sets `SAVE_IT_DATA_DIR=/data`.

### Consequences

* Good, because local development and Docker deployments can use different defaults without changing application code.
* Good, because Docker Compose and hosting templates can persist `/data` with volumes while keeping the runtime command unchanged.
* Good, because this avoids introducing command-line parsing and Docker entrypoint behavior only for one setting.
* Bad, because users who expect a Typesense-style `--data-dir` flag must use an environment variable instead.
* Bad, because deployments must avoid setting `SAVE_IT_DATA_DIR` to an empty value if they want the default path.
