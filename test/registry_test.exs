defmodule TelemetryMetricsPrometheus.Core.RegistryTest do
  use ExUnit.Case

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core.Registry

  setup do
    definitions = [
      Metrics.counter("http.request.count"),
      Metrics.distribution("some.plug.call.duration", reporter_options: [buckets: [0, 1, 2]]),
      Metrics.last_value("vm.memory.total"),
      Metrics.sum("cache.invalidations.total"),
      Metrics.summary("http.request.duration")
    ]

    opts = [name: :test, metrics: []]

    %{definitions: definitions, opts: opts}
  end

  test "registers each supported metric type", %{definitions: definitions, opts: opts} do
    {:ok, _pid} = start_supervised({Registry, opts})

    definitions
    |> Enum.each(fn definition ->
      result = Registry.register(definition, :test)

      if match?(%Metrics.Summary{}, definition) do
        assert(result == {:error, :unsupported_metric_type, :summary})
      else
        assert(result == :ok)
      end
    end)

    cleanup()
  end

  test "errors if metrics aren't set" do
    assert {:error, _} = start_supervised({Registry, [name: :test]})
  end

  test "returns an error for duplicate events", %{definitions: definitions, opts: opts} do
    {:ok, _pid} = start_supervised({Registry, opts})

    supported_defs = Enum.reject(definitions, &match?(%Metrics.Summary{}, &1))

    Enum.each(supported_defs, fn definition ->
      result = Registry.register(definition, :test)
      assert(result == :ok)
    end)

    Enum.each(supported_defs, fn definition ->
      result = Registry.register(definition, :test)
      assert(result == {:error, :already_exists, definition.name})
    end)

    cleanup()
  end

  test "validates for distribution buckets" do
    assert_raise ArgumentError, fn ->
      Metrics.distribution("some.plug.call.duration")
      |> Registry.validate_distribution_buckets!()
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("some.plug.call.duration",
        reporter_options: [
          buckets: {300..100, 100}
        ]
      )
      |> Registry.validate_distribution_buckets!()
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("some.plug.call.duration",
        reporter_options: [
          buckets: {100..350, 100}
        ]
      )
      |> Registry.validate_distribution_buckets!()
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("some.plug.call.duration",
        reporter_options: [
          buckets: [0, 200, 100]
        ]
      )
      |> Registry.validate_distribution_buckets!()
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("some.plug.call.duration",
        reporter_options: [
          buckets: []
        ]
      )
      |> Registry.validate_distribution_buckets!()
    end
  end

  test "validates for prometheus_type" do
    assert_raise ArgumentError, fn ->
      Metrics.sum("some.plug.call.total", reporter_options: [prometheus_type: :invalid])
      |> Registry.validate_prometheus_type!()
    end

    assert Metrics.sum("some.plug.call.total", reporter_options: [prometheus_type: :counter])
           |> Registry.validate_prometheus_type!() == :ok

    assert Metrics.sum("some.plug.call.total", reporter_options: [prometheus_type: :gauge])
           |> Registry.validate_prometheus_type!() == :ok

    assert Metrics.sum("some.plug.call.total", reporter_options: [])
           |> Registry.validate_prometheus_type!() == :ok

    assert Metrics.sum("some.plug.call.total")
           |> Registry.validate_prometheus_type!() == :ok
  end

  test "retrieves the config", %{opts: opts} do
    {:ok, _pid} = start_supervised({Registry, opts})
    config = Registry.config(:test)

    assert Map.has_key?(config, :aggregates_table_id)
    assert Map.has_key?(config, :dist_table_id)

    cleanup()
  end

  test "retrieves the registered metrics", %{definitions: definitions, opts: opts} do
    {:ok, _pid} = start_supervised({Registry, opts})

    supported_defs = Enum.reject(definitions, &match?(%Metrics.Summary{}, &1))

    Enum.each(supported_defs, fn definition ->
      Registry.register(definition, :test)
    end)

    metrics = Registry.metrics(:test)

    Enum.each(metrics, fn
      %Metrics.Counter{} -> assert true
      %Metrics.Distribution{} -> assert true
      %Metrics.LastValue{} -> assert true
      %Metrics.Sum{} -> assert true
      _ -> flunk("non-metric returned")
    end)

    cleanup()
  end

  test "cleans up after itself on terminate", %{definitions: definitions, opts: opts} do
    {:ok, pid} = Registry.start_link(opts)

    supported_defs = Enum.reject(definitions, &match?(%Metrics.Summary{}, &1))

    Enum.each(supported_defs, fn definition ->
      Registry.register(definition, :test)
    end)

    %{config: config} = :sys.get_state(pid)

    true = Process.exit(pid, :normal)

    # give it a second to clean up
    Process.sleep(50)

    assert :telemetry.list_handlers([]) == []
    assert :ets.info(config.aggregates_table_id) == :undefined
    assert :ets.info(config.dist_table_id) == :undefined
  end

  defp cleanup() do
    :telemetry.list_handlers([])
    |> Enum.each(&:telemetry.detach(&1.id))
  end
end
