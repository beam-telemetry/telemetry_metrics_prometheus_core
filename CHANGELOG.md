# Changelog

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

