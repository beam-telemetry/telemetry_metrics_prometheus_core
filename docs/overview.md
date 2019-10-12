# Overview

TelemetryMetricsPrometheus.Core is a [Telemetry.Metrics Reporter](https://hexdocs.pm/telemetry_metrics/overview.html#reporters) for aggregating and exposing [Prometheus](https://prometheus.io) metrics based on `Telemetry.Metrics` definitions. 

The reporter runs as a supervised process but does not include a web server to expose
your metrics. [TelemetryMetricsPrometheus](https://github.com/bryannaegele/telemetry_metrics_prometheus) provides an out of the box
solution with an included web server.

## Getting Started

Once you have the package added to your dependencies, you can start 
TelemetryMetricsPrometheus.Core by initiating the application during
your application startup.

```elixir
def start(_type, _args) do
  # List all child processes to be supervised
  children = [
    {TelemetryMetricsPrometheus.Core, [metrics: metrics()]}
    ...
  ]

  opts = [strategy: :one_for_one, name: ExampleApp.Supervisor]
  Supervisor.start_link(children, opts)
end

defp metrics, do:
  [
    counter("http.request.count"),
    sum("http.request.payload_size", unit: :byte),
    last_value("vm.memory.total", unit: :byte)
  ]

```

Note that aggregations for distributions (histogram) only occur at scrape time.
These aggregations only have to process events that have occurred since the last
scrape, so it's recommended at this time to keep an eye on scrape durations if
you're reporting a large number of disributions or you have a high tag cardinality.

## Telemetry.Metrics to Prometheus equivalents

Metric types:
* Counter - Counter
* Distribution - Histogram
* LastValue - Gauge
* Sum - Counter
* Summary - Summary (Not supported)

### Units

Prometheus recommends the usage of base units for compatibility - [Base Units](https://prometheus.io/docs/practices/naming/#base-units).
This is simple to do with `:telemetry` and `Telemetry.Metrics` as all memory
related measurements in the BEAM are reported in bytes and Metrics provides
automatic time unit conversions.

Note that measurement unit should used as part of the reported name in the case of
histograms and gauges to Prometheus. As such, it is important to explicitly define
the unit of measure for these types when the unit is time or memory related.

It is suggested to not mix units, e.g. seconds with milliseconds.

It is required to define your buckets according to the end unit translation
since this measurements are converted at the time of handling the event, prior
to bucketing.

#### Memory

Report memory as `:byte`.

#### Time

Report durations as `:second`. The BEAM and `:telemetry` events use `:native` time
units. Converting to seconds is as simple as adding the conversion tuple for
the unit - `{:native, :second}`

### Naming

`Telemetry.Metrics` definition names do not translate easily to Prometheus naming
conventions. By default, the name provided when creating your definition uses parts
of the provided name to determine what event to listen to and which event measurement
to use.

For example, `"http.request.duration"` results in listening for  `[:http, :request]`
events and use `:duration` from the event measurements. Prometheus would recommend
a name of `"http_request_duration_seconds"` as a good name.

It is therefore recommended to use the name in your definition to reflect the name
you wish to see reported, e.g. `"http.request.duration.seconds"` or `[:http, :request, :duration, :seconds]` and use the `:event_name` override and `:measurement` options in your definition.

Example:
```
Metrics.distribution(
  "http.request.duration.seconds",
  buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1],
  event_name: [:http, :request, :complete],
  measurement: :duration,
  unit: {:native, :second}
)
```

The exporter sanitizes names to Prometheus' requirements [Naming](https://prometheus.io/docs/instrumenting/writing_exporters/#naming) and joins the event name parts with an underscore.

### Labels

Labels in Prometheus are referred to as `:tags` in `Telemetry.Metrics` - see the docs
for more information on tag usage.

*Important: Each tag + value results in a separate time series. For distributions, this
is further complicated as a time series is created for each bucket plus one for measurements
exceeding the limit of the last bucket - `+Inf`.*

It is recommended, but not required, to abide by Prometheus' best practices regarding labels -
[Label Best Practices](https://prometheus.io/docs/practices/naming/#labels)

