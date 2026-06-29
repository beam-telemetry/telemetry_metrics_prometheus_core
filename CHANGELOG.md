# Changelog

## Unreleased

### Fixes

  * Bound the distribution (histogram) sample buffer so it no longer grows without limit when
    the `/metrics` endpoint is scraped infrequently or never. The registry now aggregates
    buffered samples on its own — once `:flush_threshold` samples have accumulated (default
    `10_000`) and at most every `:max_flush_interval_ms` (default `60_000`) as a fallback —
    in addition to aggregating on scrape. Set either option to `:infinity` to restore the
    previous scrape-only behaviour. Fixes
    [#41](https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/issues/41) and
    [#52](https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/issues/52).

### Changes

  * Aggregation now runs inside the registry process, serializing it with the automatic
    flushes and with concurrent scrapes. This removes a pre-existing race in the
    read-modify-write of the cumulative aggregates table when scrapes overlapped.

## v1.2.1

### Changes

  * Support TelemetryMetrics v1.0

## v1.2.0

### Changes

  * Minimum supported Elixir version increased to 1.12

### Fixes

  * Support Elixir v1.15
  * Removed unused dependencies

## v1.1.0

### Fixes

  * Relaxed telemetry version requirement

## v1.0.2

### Changes

  * Allow telemetry 1.0.0

## v1.0.1

### Changes

  * Added a synchronous start option

## v1.0.0

### Changes

  * Marking stable!

## v0.4.2

### Fixes

  * Allow numbers in exported metric names per spec

## v0.4.1

### Changes

  * Support Telemetry.Metrics v0.6

## v0.4.0

### Changes

The major change here is support for Telemetry.Metrics v0.5 which includes some breaking
changes.

  * BREAKING: Distribution buckets must now be passed in `reporter_options`
  * BREAKING: Unit validations have been removed
  * Support for event filtering in Metrics v0.5

### Fixes

  * A few typespecs were updated.

## v0.3.1

### Fixes

  * Tag values containing special characters are escaped to prevent breaking the export
  * Aggregations with tag values which don't implement String.Chars will be logged
    and dropped.

## v0.3.0

### Changes

  * Handlers are no longer detached for missing or invalid measurements or tags.
    They are now logged at `:debug` level. These errors will cause the event to
    be skipped.

### Fixes

  * Type tags and description should only be logged once per distribution definition
    and not per time series

## v0.2.2

### Fixes

  * The last line of the export now includes a new line character per the spec.
  
## v0.2.1

### Changes

  * The reporter will now clean up after itself on a normal exit
  * Included metrics cruft from the library split have been removed

## v0.2.0

### Changes

  * The package has been changed to run under a supervision tree rather than as
  a standalone application. See the [docs](https://hexdocs.pm/telemetry_metrics_prometheus_core/TelemetryMetricsPrometheus.Core.html#start_link/1) for an example.

