# Resource Creation Logger Color

## What happened

Resource creation logs were intended to be easy to spot in runtime output by rendering green. The first change configured `notice: :green` in the logger formatter and emitted `Logger.notice`, but actual output stayed uncolored because Elixir's formatter does not support a separate `notice` color key.

The follow-up fix made the output green, but it also introduced private helper functions and `kind: :resource` metadata around a simple success log. That made a short operational message more complex than the project needs.

## Root cause

The implementation assumed that `Logger.Formatter` can color `:notice` independently from `:info`. In Elixir 1.19, notice logs use the configured info color unless the individual log event passes `ansi_color` metadata.

The logging shape also drifted toward abstraction before there was a concrete filtering, routing, or dashboard workflow that needed the helper or extra metadata.

## Fix applied

Resource creation logs now use `Logger.info` with per-event `ansi_color: :green`. The logs are inline at the call sites and contain only the useful message fields, such as `source`, `file_name`, and `file_count`.

The unused `notice` color configuration was removed, tests now assert green `[info] resource_created` output without `kind=resource` or `[notice]`, and ADR 0006 records the decision to keep runtime logs inline and simple.

## What we learned

Logger appearance should be verified with representative output, not just configuration assertions. Small operational logs should stay close to the workflow that emits them unless there is a real operational need for a helper, metadata, or a structured logging layer.
