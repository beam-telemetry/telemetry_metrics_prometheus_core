defmodule CoreTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core

  test "has a child spec" do
    child_spec = Core.child_spec(metrics: [])

    assert child_spec == %{
             id: :prometheus_metrics,
             start:
               {Core.Registry, :start_link,
                [
                  [
                    validations: [consistent_units: true, require_seconds: true],
                    name: :prometheus_metrics,
                    metrics: []
                  ]
                ]}
           }

    assert %{id: :my_metrics} = Core.child_spec(name: :my_metrics, metrics: [])
    assert %{id: :global_metrics} = Core.child_spec(name: {:global, :global_metrics}, metrics: [])

    assert %{id: :via_metrics} =
             Core.child_spec(name: {:via, :example, :via_metrics}, metrics: [])
  end

  test "initializes properly" do
    metrics = [
      Metrics.counter("http.request.total",
        event_name: [:http, :request, :stop],
        tags: [:method, :code],
        description: "The total number of HTTP requests."
      )
    ]

    opts = [
      name: :test_reporter,
      validations: [require_seconds: false]
    ]

    :ok = init_and_wait(metrics, opts)

    assert :ets.info(:test_reporter) != :undefined
    assert :ets.info(:test_reporter_dist) != :undefined

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    metrics_scrape = Core.scrape(:test_reporter)

    assert metrics_scrape =~ "http_request_total"
  end

  test "initializes properly via start_link" do
    metrics = [
      Metrics.counter("http.request.total",
        event_name: [:http, :request, :stop],
        tags: [:method, :code],
        description: "The total number of HTTP requests."
      )
    ]

    opts = [name: :test_reporter, validations: [require_seconds: false]]

    _pid =
      start_supervised!(%{
        id: :test_reporter,
        start: {Core, :start_link, [Keyword.put(opts, :metrics, metrics)]}
      })

    Process.sleep(100)

    assert :ets.info(:test_reporter) != :undefined
    assert :ets.info(:test_reporter_dist) != :undefined

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    metrics_scrape = Core.scrape(:test_reporter)

    assert metrics_scrape =~ "http_request_total"
  end

  test "logs an error for duplicate metric types" do
    metrics = [
      Metrics.last_value("http.request.total"),
      Metrics.last_value("http.request.total")
    ]

    assert capture_log(fn ->
             opts = [name: :test_reporter, validations: false]
             :ok = init_and_wait(metrics, opts)
           end) =~ "Metric name already exists"
  end

  test "logs an error for unsupported metric types" do
    metrics = [
      Metrics.summary("http.request.duration")
    ]

    assert capture_log(fn ->
             opts = [name: :test_reporter, validations: false]
             :ok = init_and_wait(metrics, opts)
           end) =~ "Metric type summary is unsupported."
  end

  defp init_and_wait(metrics, opts) do
    pid = start_supervised!({Core, Keyword.put(opts, :metrics, metrics)})
    _ = :sys.get_state(pid)
    :ok
  end
end
