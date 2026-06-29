defmodule TelemetryMetricsPrometheus.Core.Registry do
  @moduledoc false
  use GenServer

  require Logger

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core.{Aggregator, Counter, Distribution, LastValue, Sum}

  @type name :: atom()
  @type metric_exists_error() :: {:error, :already_exists, Metrics.t()}
  @type unsupported_metric_type_error() :: {:error, :unsupported_metric_type, :summary}

  # metric_name should be the validated and normalized prometheus
  # name - https://prometheus.io/docs/instrumenting/writing_exporters/#naming

  def start_link(opts) do
    case Keyword.get(opts, :metrics) do
      nil -> raise "no :metrics key defined in options"
      _ -> :ok
    end

    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    name = opts[:name]
    aggregates_table_id = create_table(name, :set)
    dist_table_id = create_table(String.to_atom("#{name}_dist"), :duplicate_bag)
    start_async = Keyword.get(opts, :start_async, true)

    Process.flag(:trap_exit, true)

    # Distribution (histogram) samples are buffered in the dist table and only folded into
    # the aggregates table when aggregated. To keep that buffer bounded even when the
    # `/metrics` endpoint is scraped infrequently (or never), the registry aggregates on its
    # own: as soon as `flush_threshold` samples have been buffered (tracked lock-free in the
    # event handlers via `staged`), and at most every `max_flush_interval_ms` as a fallback
    # for low-volume metrics. `flush_pending` ensures a burst over the threshold enqueues a
    # single flush rather than one per event. Set either option to `:infinity` to disable it.
    flush_threshold = normalize_limit(Keyword.get(opts, :flush_threshold, 10_000))
    max_flush_interval_ms = normalize_limit(Keyword.get(opts, :max_flush_interval_ms, 60_000))

    config = %{
      aggregates_table_id: aggregates_table_id,
      dist_table_id: dist_table_id,
      flush_threshold: flush_threshold,
      staged: :atomics.new(1, []),
      flush_pending: :atomics.new(1, [])
    }

    state = %{config: config, metrics: [], max_flush_interval_ms: max_flush_interval_ms}

    schedule_flush_timer(max_flush_interval_ms)

    if start_async do
      send(self(), {:setup, opts})

      {:ok, state}
    else
      registered = setup_registry(opts, state.config)

      {:ok, %{state | metrics: registered}}
    end
  end

  defp normalize_limit(:infinity), do: :infinity
  defp normalize_limit(nil), do: :infinity
  defp normalize_limit(n) when is_integer(n) and n > 0, do: n

  defp schedule_flush_timer(:infinity), do: :ok
  defp schedule_flush_timer(interval), do: Process.send_after(self(), :flush_timer, interval)

  @spec register(Metrics.t(), atom()) ::
          :ok | metric_exists_error() | unsupported_metric_type_error()
  def register(metric, name \\ __MODULE__) do
    GenServer.call(name, {:register, metric})
  end

  def validate_distribution_buckets!(%Metrics.Distribution{} = metric) do
    reporter_options = metric.reporter_options

    unless reporter_options != nil do
      raise ArgumentError,
            "reporter_options with a valid buckets property are required to be defined for Distribution metrics"
    end

    unless Keyword.get(reporter_options, :buckets) != nil do
      raise ArgumentError,
            "reporter_options is missing the required buckets property for Distribution metrics"
    end

    validate_distribution_buckets!(reporter_options[:buckets])
  end

  @spec validate_distribution_buckets!(term()) :: Distribution.buckets() | no_return()
  def validate_distribution_buckets!([_ | _] = buckets) do
    unless Enum.all?(buckets, &is_number/1) do
      raise ArgumentError,
            "expected buckets list to contain only numbers, got #{inspect(buckets)}"
    end

    unless buckets == Enum.sort(buckets) do
      raise ArgumentError, "expected buckets to be ordered ascending, got #{inspect(buckets)}"
    end

    buckets
  end

  def validate_distribution_buckets!({first..last//_, step} = buckets) when is_integer(step) do
    if first >= last do
      raise ArgumentError, "expected buckets range to be ascending, got #{inspect(buckets)}"
    end

    if rem(last - first, step) != 0 do
      raise ArgumentError,
            "expected buckets range first and last to fall within all range steps " <>
              "(i.e. rem(last - first, step) == 0), got #{inspect(buckets)}"
    end

    first
    |> Stream.iterate(&(&1 + step))
    |> Enum.take_while(&(&1 <= last))
  end

  def validate_distribution_buckets!(term) do
    raise ArgumentError,
          "expected buckets to be a non-empty list or a {range, step} tuple, got #{inspect(term)}"
  end

  @spec validate_prometheus_type!(Metrics.t()) :: :ok | no_return()
  def validate_prometheus_type!(%Metrics.Sum{reporter_options: reporter_options})
      when is_list(reporter_options) do
    case Keyword.get(reporter_options, :prometheus_type) do
      nil ->
        :ok

      :gauge ->
        :ok

      :counter ->
        :ok

      prometheus_type ->
        raise ArgumentError,
              "expected prometheus_type to be one of :gauge or :counter, got #{inspect(prometheus_type)}"
    end
  end

  def validate_prometheus_type!(_metric), do: :ok

  @spec config(name()) :: %{aggregates_table_id: atom(), dist_table_id: atom()}
  def config(name) do
    GenServer.call(name, :get_config)
  end

  @spec metrics(name()) :: [{Metrics.t(), :telemetry.handler_id()}]
  def metrics(name) do
    GenServer.call(name, :get_metrics)
  end

  @doc """
  Aggregate buffered distribution samples into the aggregates table.

  Runs inside the registry process so it is serialized with the periodic/threshold flushes,
  making the read-modify-write of the cumulative aggregates table race-free even when several
  scrapes (or a scrape and a flush) happen concurrently.
  """
  @spec aggregate(name()) :: :ok
  def aggregate(name) do
    GenServer.call(name, :aggregate)
  end

  @impl true
  def handle_info({:setup, opts}, state) do
    registered = setup_registry(opts, state.config)

    {:noreply, %{state | metrics: registered}}
  end

  # Threshold-triggered flush from the event handlers: drain only, no timer involved.
  def handle_info(:flush, state) do
    {:noreply, do_aggregate(state)}
  end

  # Fallback-interval flush: drain, then re-arm exactly one successor timer so the periodic
  # chain never multiplies (threshold flushes deliberately do not reschedule).
  def handle_info(:flush_timer, state) do
    state = do_aggregate(state)
    schedule_flush_timer(state.max_flush_interval_ms)
    {:noreply, state}
  end

  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  def handle_call(:get_metrics, _from, state) do
    metrics = Enum.map(state.metrics, &elem(&1, 0))
    {:reply, metrics, state}
  end

  def handle_call(:aggregate, _from, state) do
    {:reply, :ok, do_aggregate(state)}
  end

  @impl true
  @spec handle_call({:register, Metrics.t()}, GenServer.from(), map()) ::
          {:reply, :ok, map()}
          | {:reply, metric_exists_error() | unsupported_metric_type_error(), map()}
  def handle_call({:register, metric}, _from, state) do
    case register_metric(metric, state.config) do
      {:ok, metric} -> {:reply, :ok, %{state | metrics: [metric | state.metrics]}}
      other -> {:reply, other, state}
    end
  end

  @impl true
  def terminate(_reason, %{metrics: metrics, config: config} = _state) do
    with :ok <- Enum.each(metrics, &unregister_metric/1),
         true <- :ets.delete(config.aggregates_table_id),
         true <- :ets.delete(config.dist_table_id),
         do: :ok
  end

  # Drains the distribution buffer into the aggregates table and re-arms the flush trigger.
  # The order matters: aggregate (which `:ets.take`s the buffered samples) first, then reset
  # the staged counter, then clear `flush_pending` so the next over-threshold event can
  # enqueue a fresh flush.
  defp do_aggregate(%{config: config, metrics: metrics} = state) do
    definitions = Enum.map(metrics, &elem(&1, 0))
    :ok = Aggregator.aggregate(definitions, config.aggregates_table_id, config.dist_table_id)
    :atomics.put(config.staged, 1, 0)
    :atomics.put(config.flush_pending, 1, 0)
    state
  end

  defp setup_registry(opts, config) do
    opts
    |> Keyword.get(:metrics, [])
    |> register_metrics(config)
  end

  @spec create_table(name :: atom, type :: atom) :: :ets.tid() | atom
  defp create_table(name, type) do
    :ets.new(name, [:named_table, :public, type, {:write_concurrency, true}])
  end

  @spec register_metrics([Metrics.t()], map()) :: [Metrics.t()]
  defp register_metrics(metrics, config) do
    metrics
    |> Enum.reduce([], fn metric, acc ->
      case register_metric(metric, config) do
        {:ok, metric} ->
          [metric | acc]

        {:error, :already_exists, metric_name} ->
          Logger.warning(
            "Metric name already exists. Dropping measure. metric_name:=#{inspect(metric_name)}"
          )

          acc

        {:error, :unsupported_metric_type, metric_type} ->
          Logger.warning(
            "Metric type #{metric_type} is unsupported. Dropping measure. metric_name:=#{inspect(metric.name)}"
          )

          acc
      end
    end)
  end

  defp register_metric(%Metrics.Counter{} = metric, config) do
    case Counter.register(metric, config.aggregates_table_id, self()) do
      {:ok, handler_id} -> {:ok, {metric, handler_id}}
      {:error, :already_exists} -> {:error, :already_exists, metric.name}
    end
  end

  defp register_metric(%Metrics.LastValue{} = metric, config) do
    case LastValue.register(metric, config.aggregates_table_id, self()) do
      {:ok, handler_id} -> {:ok, {metric, handler_id}}
      {:error, :already_exists} -> {:error, :already_exists, metric.name}
    end
  end

  defp register_metric(%Metrics.Sum{} = metric, config) do
    validate_prometheus_type!(metric)

    case Sum.register(metric, config.aggregates_table_id, self()) do
      {:ok, handler_id} -> {:ok, {metric, handler_id}}
      {:error, :already_exists} -> {:error, :already_exists, metric.name}
    end
  end

  defp register_metric(%Metrics.Distribution{} = metric, config) do
    validate_distribution_buckets!(metric)

    flush_ctx = %{
      registry: self(),
      staged: config.staged,
      flush_pending: config.flush_pending,
      flush_threshold: config.flush_threshold
    }

    case Distribution.register(metric, config.dist_table_id, self(), flush_ctx) do
      {:ok, handler_id} ->
        reporter_options =
          Keyword.update!(
            metric.reporter_options,
            :buckets,
            &(&1 ++ ["+Inf"])
          )

        {:ok, {%{metric | reporter_options: reporter_options}, handler_id}}

      {:error, :already_exists} ->
        {:error, :already_exists, metric.name}
    end
  end

  defp register_metric(%Metrics.Summary{}, _config) do
    {:error, :unsupported_metric_type, :summary}
  end

  defp unregister_metric({_metric, handler_id}) do
    :telemetry.detach(handler_id)
  end
end
