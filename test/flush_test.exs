defmodule FlushTest do
  use ExUnit.Case

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core

  # Regression coverage for the unbounded growth of the distribution buffer when the `/metrics`
  # endpoint is scraped infrequently or never. See:
  #   - https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/issues/41
  #   - https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/issues/52

  defp dist_metric(name, event_name) do
    Metrics.distribution(name,
      event_name: event_name,
      measurement: :duration,
      reporter_options: [buckets: [10, 50, 100]]
    )
  end

  defp init(metrics, opts) do
    pid = start_supervised!({Core, Keyword.put(opts, :metrics, metrics)})
    _ = :sys.get_state(pid)
    :ok
  end

  test "distributions are aggregated automatically once flush_threshold samples buffer, with no scrape" do
    :ok =
      init([dist_metric("test.flush.size", [:test, :flush, :size])],
        name: :flush_size_reporter,
        flush_threshold: 5,
        max_flush_interval_ms: :infinity
      )

    for _ <- 1..20, do: :telemetry.execute([:test, :flush, :size], %{duration: 42})
    # Synchronize on the registry so the enqueued :flush has been processed.
    _ = :sys.get_state(:flush_size_reporter)

    # Aggregated into the cumulative table without anyone calling scrape/1...
    assert :ets.tab2list(:flush_size_reporter) != []
    # ...and the buffer was drained well below the 20 samples emitted.
    assert :ets.info(:flush_size_reporter_dist, :size) < 20
  end

  test "distributions are aggregated on the fallback interval even when the threshold is never reached" do
    :ok =
      init([dist_metric("test.flush.time", [:test, :flush, :time])],
        name: :flush_time_reporter,
        flush_threshold: :infinity,
        max_flush_interval_ms: 50
      )

    for _ <- 1..3, do: :telemetry.execute([:test, :flush, :time], %{duration: 42})

    # Wait past the fallback interval, then synchronize on the registry.
    Process.sleep(150)
    _ = :sys.get_state(:flush_time_reporter)

    assert :ets.info(:flush_time_reporter_dist, :size) == 0
    assert :ets.tab2list(:flush_time_reporter) != []

    # The periodic chain must keep firing: a second batch drains on the next interval without
    # any scrape. (Regression guard for the timer re-arming exactly once.)
    for _ <- 1..3, do: :telemetry.execute([:test, :flush, :time], %{duration: 42})
    assert :ets.info(:flush_time_reporter_dist, :size) == 3

    Process.sleep(150)
    _ = :sys.get_state(:flush_time_reporter)
    assert :ets.info(:flush_time_reporter_dist, :size) == 0
  end

  test "auto-flush can be disabled, leaving the buffer to be drained on scrape only" do
    :ok =
      init([dist_metric("test.flush.off", [:test, :flush, :off])],
        name: :flush_off_reporter,
        flush_threshold: :infinity,
        max_flush_interval_ms: :infinity
      )

    for _ <- 1..10, do: :telemetry.execute([:test, :flush, :off], %{duration: 42})
    _ = :sys.get_state(:flush_off_reporter)
    Process.sleep(50)

    # Nothing drains the buffer with both triggers disabled and no scrape.
    assert :ets.info(:flush_off_reporter_dist, :size) == 10

    # A scrape still aggregates and drains it.
    _ = Core.scrape(:flush_off_reporter)
    assert :ets.info(:flush_off_reporter_dist, :size) == 0
  end
end
