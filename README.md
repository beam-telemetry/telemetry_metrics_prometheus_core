# TelemetryMetricsPrometheus.Core

[![CircleCI](https://circleci.com/gh/beam-telemetry/telemetry_metrics_prometheus_core/tree/master.svg?style=svg)](https://circleci.com/gh/beam-telemetry/telemetry_metrics_prometheus_core/tree/master) [![codecov](https://codecov.io/gh/beam-telemetry/telemetry_metrics_prometheus_core/branch/master/graph/badge.svg?token=ZukGAUDLwH)](https://codecov.io/gh/beam-telemetry/telemetry_metrics_prometheus_core) [![Hex](https://img.shields.io/hexpm/v/telemetry_metrics_prometheus_core.svg)](https://hex.pm/packages/telemetry_metrics_prometheus_core) [![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg?style=flat)](https://hexdocs.pm/telemetry_metrics_prometheus_core/)

TelemetryMetricsPrometheus.Core is a [Telemetry.Metrics Reporter](https://hexdocs.pm/telemetry_metrics/overview.html#reporters) for aggregating and exposing [Prometheus](https://prometheus.io) metrics based on `Telemetry.Metrics` definitions. This package does not provide a built-in web server. TelemetryMetricsPrometheus provides a server out of the box exposing a `/metrics` endpoint, making setup a breeze.

## Web Server

 This library is the core for the [TelemetryMetricsPrometheus](https://github.com/beam-telemetry/telemetry_metrics_prometheus) project. The `TelemetryMetricsPrometheus` libary is a standalone implementation leveraging `TelemetryMetricsPrometheus.Core` which ships with its own web server. Using `TelemetryMetricsPrometheus` allows a quick way to get started with a Cowboy web server that runs along side your application. `TelemetryMetricsPrometheus.Core` should be used if your use case is outside the scope of the `TelemetryMetricsPrometheus` web server.

## Is this the right Prometheus package for me?

If you want to take advantage of consuming `:telemetry` events with the ease of 
defining and managing metrics `Telemetry.Metrics` brings for Prometheus, then yes! 
This package provides a simple and straightforward way to aggregate and report 
Prometheus metrics. Whether you're using [Prometheus](https://prometheus.io/docs/prometheus/latest/getting_started/) servers, [Datadog](https://docs.datadoghq.com/integrations/prometheus/), 
or any other monitoring solution which supports scraping, you're in luck!

If you're not interested in taking advantage of `Telemetry.Metrics` but still 
want to implement Prometheus or use `:telemetry` in your project, have a look at 
something like the [OpenCensus](https://github.com/opencensus-beam) project and 
see if it better meets your needs.

## Installation

The package can be installed by adding `telemetry_metrics_prometheus_core` to your 
list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:telemetry_metrics_prometheus_core, "~> 1.0.0"}
  ]
end
```

See the documentation on [Hexdocs](https://hexdocs.pm/telemetry_metrics_prometheus_core) for more information.


## Contributing

Contributors are highly welcome! 

Additional documentation, tests, and benchmarking are all welcome. 

Please open an issue for discussion before undertaking anything non-trivial before
jumping in and submitting a PR.

