# Changelog

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
  a standalone application. See the [docs](https://hexdocs.pm/telemetry_metrics_prometheus_core/TelemetryMetricsPrometheusCore.html#start_link/1) for an example.

