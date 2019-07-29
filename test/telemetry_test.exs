defmodule TelemetryMetricsPrometheus.Core.TelemetryTest do
  use ExUnit.Case, async: false

  alias TelemetryMetricsPrometheus.Core

  test "table stats are dispatched" do
    _pid = start_supervised!({Core.Registry, [metrics: [], monitor_reporter: true]})
    :telemetry.attach("test_handler", [:telemetry_metrics_prometheus, :table, :status], &echo_event/4, %{caller: self()})

    Process.sleep(100)

    assert_received({:event, [:telemetry_metrics_prometheus, :table, :status], _, _})
  end

  def echo_event(event, measurements, metadata, config) do
    send(config.caller, {:event, event, measurements, metadata})
  end
end
