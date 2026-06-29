defmodule TelemetryMetricsPrometheus.Core.Distribution do
  @moduledoc false

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core.EventHandler

  @typedoc """
  Distribution metric bucket boundaries.

  Bucket boundaries are represented by a non-empty list of increasing numbers.

  ## Examples
      [0, 100, 200, 300]
      # Buckets: [-inf, 0], [0, 100], [100, 200], [200, 300], [300, +inf]
      [99.9]
      # Buckets: [-inf, 99.9], [99.9, +inf]
  """
  @type buckets :: [number(), ...]

  @typedoc """
  Trigger that bounds the size of the buffered-sample (`:duplicate_bag`) table.

  `staged` counts buffered samples, `flush_pending` de-bounces the signal so a burst over the
  threshold enqueues a single flush, and `registry` is the process that performs the
  (serialized) aggregation. `flush_threshold` is `:infinity` to disable size-based flushing.
  """
  @type flush_ctx :: %{
          registry: pid(),
          staged: :atomics.atomics_ref(),
          flush_pending: :atomics.atomics_ref(),
          flush_threshold: pos_integer() | :infinity
        }

  @type config :: %{
          keep: Metrics.keep(),
          measurement: Metrics.measurement(),
          metric_name: String.t(),
          name: Metrics.normalized_metric_name(),
          table: atom(),
          tags: Metrics.tags(),
          tag_values_fun: Metrics.tag_values(),
          type: :histogram,
          unit: Metrics.unit(),
          flush_ctx: flush_ctx()
        }

  @spec register(
          metric :: Metrics.Distribution.t(),
          table_id :: atom(),
          owner :: pid(),
          flush_ctx :: flush_ctx()
        ) ::
          {:ok, :telemetry.handler_id()} | {:error, :already_exists}

  def register(metric, table_id, owner, flush_ctx \\ disabled_flush_ctx()) do
    handler_id = EventHandler.handler_id(metric.name, owner)

    with :ok <-
           :telemetry.attach(
             handler_id,
             metric.event_name,
             &__MODULE__.handle_event/4,
             %{
               keep: metric.keep,
               measurement: metric.measurement,
               metric_name: "",
               name: metric.name,
               table: table_id,
               tags: metric.tags,
               tag_values_fun: metric.tag_values,
               type: :histogram,
               unit: metric.unit,
               flush_ctx: flush_ctx
             }
           ) do
      {:ok, handler_id}
    else
      {:error, :already_exists} = error ->
        error
    end
  end

  @spec handle_event(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          config()
        ) :: :ok
  def handle_event(_event, measurements, metadata, config) do
    with true <- EventHandler.keep?(config.keep, metadata),
         {:ok, measurement} <-
           EventHandler.get_measurement(measurements, metadata, config.measurement),
         mapped_values <- config.tag_values_fun.(metadata),
         :ok <- EventHandler.validate_tags_in_tag_values(config.tags, mapped_values),
         labels <- Map.take(mapped_values, config.tags) do
      true = :ets.insert(config.table, {config.name, {labels, measurement}})

      maybe_request_flush(config.flush_ctx)
    else
      false -> :ok
      error -> EventHandler.handle_event_error(error, config)
    end
  end

  # Used when a distribution is registered outside the registry (e.g. in tests): no registry to
  # flush to, so size-based flushing is disabled and the dist table is drained on scrape only.
  @spec disabled_flush_ctx() :: flush_ctx()
  defp disabled_flush_ctx do
    %{
      registry: self(),
      staged: :atomics.new(1, []),
      flush_pending: :atomics.new(1, []),
      flush_threshold: :infinity
    }
  end

  # Lock-free, on the hot path: bump the staged-sample counter and, only when it crosses the
  # threshold, ask the registry to flush. `compare_exchange/4` guarantees a single in-flight
  # request per drain cycle, so a burst over the threshold never floods the registry mailbox.
  @spec maybe_request_flush(flush_ctx()) :: :ok
  defp maybe_request_flush(%{flush_threshold: :infinity}), do: :ok

  defp maybe_request_flush(%{flush_threshold: threshold} = ctx) do
    if :atomics.add_get(ctx.staged, 1, 1) >= threshold and
         :atomics.compare_exchange(ctx.flush_pending, 1, 0, 1) == :ok do
      send(ctx.registry, :flush)
    end

    :ok
  end
end
