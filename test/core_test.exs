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
      name: :test_reporter
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

  test "initializes properly when configured via start_async" do
    metrics = [
      Metrics.counter("http.request.total",
        event_name: [:http, :request, :stop],
        tags: [:method, :code],
        description: "The total number of HTTP requests."
      )
    ]

    async_opts = [
      name: :test_reporter_async,
      validations: [require_seconds: false],
      start_async: true,
      metrics: metrics
    ]

    sync_opts = [
      name: :test_reporter_sync,
      validations: [require_seconds: false],
      start_async: false,
      metrics: metrics
    ]

    async_pid =
      start_supervised!(%{
        id: Keyword.get(async_opts, :name),
        start:
          {GenServer, :start_link,
           [
             Core.Registry,
             async_opts,
             [name: Keyword.get(async_opts, :name), debug: [:statistics]]
           ]}
      })

    sync_pid =
      start_supervised!(%{
        id: Keyword.get(sync_opts, :name),
        start:
          {GenServer, :start_link,
           [
             Core.Registry,
             sync_opts,
             [name: Keyword.get(sync_opts, :name), debug: [:statistics]]
           ]}
      })

    Process.sleep(100)

    assert :ets.info(:test_reporter_async) != :undefined
    assert :ets.info(:test_reporter_async_dist) != :undefined

    assert :ets.info(:test_reporter_sync) != :undefined
    assert :ets.info(:test_reporter_sync_dist) != :undefined

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    async_metrics_scrape = Core.scrape(Keyword.get(async_opts, :name))
    sync_metrics_scrape = Core.scrape(Keyword.get(sync_opts, :name))

    {:ok, async_stats} = :sys.statistics(async_pid, :get)
    {:ok, sync_stats} = :sys.statistics(sync_pid, :get)

    # The async Registry should have 1 more message processed from the inbox
    # due to the handle_info setup call triggered in init
    assert Keyword.get(async_stats, :messages_in) > Keyword.get(sync_stats, :messages_in)

    assert async_metrics_scrape =~ "http_request_total"
    assert sync_metrics_scrape =~ "http_request_total"
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
