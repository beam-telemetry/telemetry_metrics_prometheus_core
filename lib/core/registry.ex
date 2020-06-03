defmodule TelemetryMetricsPrometheus.Core.Registry do
  @moduledoc false
  use GenServer

  require Logger

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core
  alias TelemetryMetricsPrometheus.Core.{Counter, Distribution, LastValue, Sum}

  @type name :: atom()
  @type metric_exists_error() :: {:error, :already_exists, Core.metric()}
  @type unsupported_metric_type_error() :: {:error, :unsupported_metric_type, :summary}
  @type validation_opts() :: [consistent_units: bool(), require_seconds: bool()]

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

    Process.flag(:trap_exit, true)

    send(self(), {:setup, opts})

    {:ok,
     %{
       config: %{aggregates_table_id: aggregates_table_id, dist_table_id: dist_table_id},
       metrics: []
     }}
  end

  @spec register(Core.metric(), atom()) ::
          :ok | metric_exists_error() | unsupported_metric_type_error()
  def register(metric, name \\ __MODULE__) do
    # validate metrics units ?

    GenServer.call(name, {:register, metric})
  end

  @spec validate_units(Core.metrics(), validation_opts()) ::
          Core.metrics()
  def validate_units(metrics, opts) do
    time_units =
      metrics
      |> Enum.filter(&match?(%Metrics.Distribution{}, &1))
      |> Enum.reduce(MapSet.new([]), fn
        %{unit: {_from, to}}, acc -> MapSet.put(acc, to)
        %{unit: unit}, acc when is_atom(unit) -> MapSet.put(acc, unit)
      end)
      |> MapSet.to_list()

    validate_consistent_units(time_units, opts[:consistent_units])
    validate_units_seconds(time_units, opts[:require_seconds])

    metrics
  end

  @spec validate_consistent_units([Metrics.time_unit()], bool()) :: :ok
  defp validate_consistent_units(_, false), do: :ok

  defp validate_consistent_units(units, true) when length(units) > 1 do
    Logger.warn(
      "Multiple time units found in your Telemetry.Metrics definitions.\n\nPrometheus recommends using consistent time units to make view creation simpler.\n\nYou can disable this validation check by adding `consistent_units: false` in the validations options on reporter init."
    )

    :ok
  end

  defp validate_consistent_units(_units, _), do: :ok

  def validate_distribution_buckets!(%Metrics.Distribution{} = metric) do
    reporter_options = metric.reporter_options

    unless reporter_options != nil do
      raise ArgumentError, "expected reporter_options to be on metric"
    end

    unless Keyword.get(reporter_options, :buckets) != nil do
      raise ArgumentError, "expected :buckets to be in `reporter_options`"
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

  def validate_distribution_buckets!({first..last, step} = buckets) when is_integer(step) do
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

  @spec validate_units_seconds([Metrics.time_unit()], bool()) :: :ok
  defp validate_units_seconds(_, false), do: :ok
  defp validate_units_seconds([:second], _), do: :ok
  defp validate_units_seconds([], _), do: :ok

  defp validate_units_seconds(_, _) do
    Logger.warn(
      "Prometheus requires that time units MUST only be offered in seconds according to their guidelines, though this is not always practical.\n\nhttps://prometheus.io/docs/instrumenting/writing_clientlibs/#histogram.\n\nYou can disable this validation check by adding `require_seconds: false` in the validations options on reporter init."
    )

    :ok
  end

  @spec config(name()) :: %{aggregates_table_id: atom(), dist_table_id: atom()}
  def config(name) do
    GenServer.call(name, :get_config)
  end

  @spec metrics(name()) :: [{Core.metric(), :telemetry.handler_id()}]
  def metrics(name) do
    GenServer.call(name, :get_metrics)
  end

  @impl true
  def handle_info({:setup, opts}, state) do
    metrics = Keyword.get(opts, :metrics, [])
    registered = register_metrics(metrics, opts[:validations], state.config)

    {:noreply, %{state | metrics: registered}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  def handle_call(:get_metrics, _from, state) do
    metrics = Enum.map(state.metrics, &elem(&1, 0))
    {:reply, metrics, state}
  end

  @impl true
  @spec handle_call({:register, Core.metric()}, GenServer.from(), map()) ::
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

  @spec create_table(name :: atom, type :: atom) :: :ets.tid() | atom
  defp create_table(name, type) do
    :ets.new(name, [:named_table, :public, type, {:write_concurrency, true}])
  end

  @spec register_metrics(
          Core.metrics(),
          validation_opts(),
          %{}
        ) :: :ok
  defp register_metrics(metrics, validations, config) do
    metrics
    |> validate_units(validations)
    |> Enum.reduce([], fn metric, acc ->
      case register_metric(metric, config) do
        {:ok, metric} ->
          [metric | acc]

        {:error, :already_exists, metric_name} ->
          Logger.warn(
            "Metric name already exists. Dropping measure. metric_name:=#{inspect(metric_name)}"
          )

          acc

        {:error, :unsupported_metric_type, metric_type} ->
          Logger.warn(
            "Metric type #{metric_type} is unsupported. Dropping measure. metric_name:=#{
              inspect(metric.name)
            }"
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
    case Sum.register(metric, config.aggregates_table_id, self()) do
      {:ok, handler_id} -> {:ok, {metric, handler_id}}
      {:error, :already_exists} -> {:error, :already_exists, metric.name}
    end
  end

  defp register_metric(%Metrics.Distribution{} = metric, config) do
    validate_distribution_buckets!(metric)

    case Distribution.register(metric, config.dist_table_id, self()) do
      {:ok, handler_id} ->
        reporter_options = Keyword.update!(
          metric.reporter_options,
          :buckets,
          &(&1 ++ ["+Inf"])
        )
        {:ok, {%{metric | reporter_options: reporter_options}, handler_id}}
      {:error, :already_exists} -> {:error, :already_exists, metric.name}
    end
  end

  defp register_metric(%Metrics.Summary{}, _config) do
    {:error, :unsupported_metric_type, :summary}
  end

  defp unregister_metric({_metric, handler_id}) do
    :telemetry.detach(handler_id)
  end
end
