defmodule TelemetryMetricsPrometheus.Core.Aggregator do
  @moduledoc false

  require Logger

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core

  @typep bucket ::
           {upper_bound :: String.t(), count :: non_neg_integer(),
            {measurement :: number(), exemplar_labels :: map(), monotonic_sample_time :: number()}
            | nil}
  @typep sample ::
           {name :: :telemetry.event_name(),
            {labels :: map(), exemplar_labels :: map(), monotonic_sample_time :: number(),
             measurement :: number()}}
  @typep key :: {name :: :telemetry.event_name(), map()}
  @typep aggregation :: {[bucket()], non_neg_integer(), number()}

  @spec aggregate(Core.metrics(), atom(), atom()) :: :ok
  def aggregate(definitions, table_id, dist_table_id) do
    for %Metrics.Distribution{} = metric <- definitions do
      :ets.take(dist_table_id, metric.name)
      |> aggregate_and_store(metric, table_id)
    end

    :ok
  end

  @spec aggregate_and_store(samples :: [sample()], Metrics.Distribution.t(), atom()) :: :ok
  defp aggregate_and_store(samples, metric, tid) do
    samples
    |> group_samples()
    |> Enum.map(fn {name, measurements} ->
      Enum.map(measurements, fn {labels, samples} ->
        key = {name, labels}
        prev_agg = get_aggregation(key, tid)

        Enum.sort(samples)
        |> bucket_measurements(metric.reporter_options[:buckets])
        |> merge(prev_agg)
        |> put_aggregation(key, tid)
      end)
    end)

    :ok
  end

  @spec get_time_series(atom()) :: %{:telemetry.event_name() => [sample()]}
  def get_time_series(table_id) do
    :ets.tab2list(table_id)
    |> Stream.filter(&filter_and_drop_time_series_with_bad_tag_values(&1, table_id))
    |> Enum.group_by(fn row -> row |> elem(0) |> elem(0) end)
  end

  defp filter_and_drop_time_series_with_bad_tag_values({[_, %{}], _}, _), do: true

  defp filter_and_drop_time_series_with_bad_tag_values({key, _}, table_id) do
    key
    |> elem(1)
    |> Enum.map(fn {label_key, value} ->
      case String.Chars.impl_for(value) do
        nil ->
          Logger.warning(
            "Dropping aggregation for bad tag value. metric:=#{inspect(elem(key, 0))} tag: #{inspect(label_key)}"
          )

          delete_aggregation(table_id, key)
          false

        _ ->
          true
      end
    end)
    |> Enum.all?()
  end

  defp delete_aggregation(table_id, key) do
    :ets.delete(table_id, key)
  end

  defp merge(new, {}), do: new

  defp merge({l_b, l_c, l_s}, {r_b, r_c, r_s}) do
    buckets =
      Enum.zip(l_b, r_b)
      |> Enum.map(fn {{bucket, a, a_exemplar}, {bucket, b, b_exemplar}} ->
        {bucket, a + b, select_exemplar(a_exemplar, b_exemplar)}
      end)

    {buckets, l_c + r_c, l_s + r_s}
  end

  @spec get_aggregation(key :: key(), table :: atom()) :: {} | aggregation()
  defp get_aggregation(key, table) do
    case :ets.lookup(table, key) do
      [] -> {}
      [agg] -> agg |> elem(1)
    end
  end

  @spec put_aggregation(aggregation :: nil | aggregation(), key :: key(), table :: atom()) :: true
  def put_aggregation(nil, _, _), do: true

  def put_aggregation(aggregation, key, tid) do
    :ets.insert(tid, {key, aggregation})
  end

  @spec group_samples(samples :: [sample()]) :: %{
          :telemetry.event_name() => %{
            map() => [{number(), exemplar_labels :: map(), integer}]
          }
        }
  def group_samples(samples) do
    Enum.reduce(
      samples,
      %{},
      fn {name, {labels, exemplar_labels, monotonic_sample_time, measurement}}, acc ->
        metric = Map.get(acc, name, %{})
        values = Map.get(metric, labels, [])
        new_values = [{measurement, exemplar_labels, monotonic_sample_time} | values]
        new_metric = Map.put(metric, labels, new_values)
        Map.put(acc, name, new_metric)
      end
    )
  end

  @spec bucket_measurements(
          measurements :: [{number(), map(), integer()}],
          buckets :: Core.Distribution.buckets()
        ) ::
          {[bucket()], non_neg_integer(), number()}
  def bucket_measurements(measurements, [b | buckets]),
    do: bucket(measurements, buckets, b, nil, 0, 0, [])

  defp bucket([], [], _, _exemplar, count, sum, result), do: {Enum.reverse(result), count, sum}

  defp bucket(measurements, [], "+Inf", exemplar, count, sum, result) do
    {new_count, new_sum, new_exemplar} =
      Enum.reduce(measurements, {count, sum, exemplar}, fn {m, _el, _mst} = sample, {c, s, e} ->
        {c + 1, s + m, select_exemplar(sample, e)}
      end)

    bucket([], [], "+Inf", new_exemplar, new_count, new_sum, [
      {"+Inf", new_count, new_exemplar} | result
    ])
  end

  defp bucket([], buckets, cur_bucket, nil, count, sum, result) do
    rest =
      [cur_bucket | buckets]
      |> Enum.reverse()
      |> Enum.map(fn bucket -> {"#{bucket}", count, nil} end)

    bucket([], [], nil, nil, count, sum, rest ++ result)
  end

  defp bucket(
         [],
         buckets,
         cur_bucket,
         {exemplar_value, _el, _emst} = exemplar,
         count,
         sum,
         result
       ) do
    buckets_with_exemplars =
      case Enum.split_while([cur_bucket | buckets], fn bucket ->
             bucket != "+Inf" and exemplar_value > bucket
           end) do
        {le_buckets, [first_g_bucket | rest_g_buckets] = g_buckets} ->
          Enum.map(le_buckets, &{&1, nil}) ++
            [{first_g_bucket, exemplar} | Enum.map(rest_g_buckets, &{&1, nil})]
      end

    rest =
      buckets_with_exemplars
      |> Enum.reverse()
      |> Enum.map(fn {bucket, exemplar} -> {"#{bucket}", count, exemplar} end)

    bucket([], [], nil, exemplar, count, sum, rest ++ result)
  end

  defp bucket(
         [{measurement, _exemplar_labels, _monotonic_sample_time} = sample | r_m] = measurements,
         [b | r_b] = buckets,
         cur_bucket,
         exemplar,
         count,
         sum,
         result
       ) do
    cond do
      measurement <= cur_bucket ->
        bucket(
          r_m,
          buckets,
          cur_bucket,
          select_exemplar(sample, exemplar),
          count + 1,
          sum + measurement,
          result
        )

      true ->
        bucket(measurements, r_b, b, nil, count, sum, [
          {"#{cur_bucket}", count, exemplar} | result
        ])
    end
  end

  defp select_exemplar(nil, nil) do
    nil
  end

  defp select_exemplar(
         {_lm, _ll, left_monotonic_sample_time} = left,
         nil
       ) do
    left
  end

  defp select_exemplar(
         nil,
         {_rm, _rl, right_monotonic_sample_time} = right
       ) do
    right
  end

  defp select_exemplar(
         {_lm, _ll, left_monotonic_sample_time} = left,
         {_rm, _rl, right_monotonic_sample_time} = right
       ) do
    if left_monotonic_sample_time <= right_monotonic_sample_time do
      right
    else
      left
    end
  end
end
