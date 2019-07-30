defmodule TelemetryMetricsPrometheus.Core.Telemetry do
  @moduledoc false

  def dispatch_table_stats(table) do
    info = :ets.info(table) |> Map.new()

    measurements = Map.take(info, [:memory, :size])

    metadata = Map.drop(info, [:memory, :size])

    :telemetry.execute([:telemetry_metrics_prometheus, :table, :status], measurements, metadata)
  end
end
