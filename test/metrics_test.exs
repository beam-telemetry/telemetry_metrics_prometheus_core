defmodule TelemetryMetricsPrometheus.Core.MetricsTest do
  use ExUnit.Case

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Core.{Counter, Distribution, LastValue, Sum}

  import ExUnit.CaptureLog

  setup do
    tid = :ets.new(:test_table, [:named_table, :public, :set, {:write_concurrency, true}])

    dist_tid =
      :ets.new(:test_dist_table, [
        :named_table,
        :public,
        :duplicate_bag,
        {:write_concurrency, true}
      ])

    %{tid: tid, dist_tid: dist_tid}
  end

  describe "counter" do
    # for metric <- [Counter, Distribution, LastValue, Sum]
    test "registers a handler", %{tid: tid} do
      metric =
        Metrics.counter("http.request.count",
          description: "HTTP Request Count",
          unit: :each,
          tags: [:status]
        )

      {:ok, handler_id} = Counter.register(metric, tid, self())

      handlers = :telemetry.list_handlers([])
      assert Enum.any?(handlers, &match?(^handler_id, &1.id))
      cleanup(tid)
    end

    test "records a times series for each tag kv pair", %{tid: tid} do
      metric =
        Metrics.counter("http.request.count",
          description: "HTTP Request Count",
          drop: &match?(%{a: "drop"}, &1),
          unit: :each,
          tags: [:method, :status]
        )

      {:ok, _handler_id} = Counter.register(metric, tid, self())

      :telemetry.execute([:http, :request], %{latency: 17}, %{method: "GET", status: 200})
      :telemetry.execute([:http, :request], %{latency: 20}, %{method: "GET", status: 200})
      :telemetry.execute([:http, :request], %{latency: 22}, %{method: "GET", status: 404})

      :telemetry.execute([:http, :request], %{latency: 100}, %{
        method: "GET",
        status: 404,
        a: "drop"
      })

      [t1] = :ets.lookup(tid, {metric.name, %{method: "GET", status: 200}})
      [t2] = :ets.lookup(tid, {metric.name, %{method: "GET", status: 404}})

      assert elem(t1, 1) == 2
      assert elem(t2, 1) == 1
      cleanup(tid)
    end
  end

  describe "gauge" do
    # for metric <- [Counter, Distribution, LastValue, Sum]
    test "registers a handler", %{tid: tid} do
      metric =
        Metrics.last_value("vm.memory.total",
          description: "BEAM VM memory",
          unit: :bytes,
          tags: []
        )

      {:ok, handler_id} = LastValue.register(metric, tid, self())

      handlers = :telemetry.list_handlers([])
      assert Enum.any?(handlers, &match?(^handler_id, &1.id))
      cleanup(tid)
    end

    test "records a times series for each tag kv pair", %{tid: tid} do
      metric =
        Metrics.last_value("vm.memory.total",
          description: "BEAM VM memory",
          drop: &match?(%{a: "drop"}, &1),
          unit: :bytes,
          tags: [:some_tag]
        )

      {:ok, _handler_id} = LastValue.register(metric, tid, self())

      :telemetry.execute([:vm, :memory], %{total: 200_000, system: 1_000}, %{some_tag: "a"})
      [t1] = :ets.lookup(tid, {metric.name, %{some_tag: "a"}})

      :telemetry.execute([:vm, :memory], %{total: 190_000, system: 998}, %{some_tag: "b"})
      [t2] = :ets.lookup(tid, {metric.name, %{some_tag: "b"}})

      :telemetry.execute([:vm, :memory], %{total: 210_000, system: 1_100}, %{some_tag: "a"})

      :telemetry.execute([:vm, :memory], %{total: 210_000, system: 1_100}, %{
        some_tag: "a",
        a: "drop"
      })

      [t3] = :ets.lookup(tid, {metric.name, %{some_tag: "a"}})

      assert elem(t1, 1) == 200_000
      assert elem(t2, 1) == 190_000
      assert elem(t3, 1) == 210_000
      cleanup(tid)
    end

    test "records a time series for sum/2 that are specified as gauges", %{tid: tid} do
      metric =
        Metrics.sum("vm.memory.total",
          description: "BEAM VM memory",
          unit: :bytes,
          reporter_options: [prometheus_type: :gauge]
        )

      {:ok, _handler_id} = Sum.register(metric, tid, self())

      :telemetry.execute([:vm, :memory], %{total: 200_000}, %{})
      [t1] = :ets.lookup(tid, {metric.name, %{}})

      :telemetry.execute([:vm, :memory], %{total: -190_000}, %{})
      [t2] = :ets.lookup(tid, {metric.name, %{}})

      :telemetry.execute([:vm, :memory], %{total: -10_000}, %{})
      [t3] = :ets.lookup(tid, {metric.name, %{}})

      assert elem(t1, 1) == 200_000
      assert elem(t2, 1) == 10_000
      assert elem(t3, 1) == 0
      cleanup(tid)
    end
  end

  describe "sum" do
    # for metric <- [Counter, Distribution, LastValue, Sum]
    test "registers a handler", %{tid: tid} do
      metric =
        Metrics.sum("cache.invalidation.total",
          description: "Total cache invalidations",
          measurement: :count,
          unit: :each,
          tags: [:name]
        )

      {:ok, handler_id} = Sum.register(metric, tid, self())

      handlers = :telemetry.list_handlers([])
      assert Enum.any?(handlers, &match?(^handler_id, &1.id))
      cleanup(tid)
    end

    test "records a times series for each tag kv pair", %{tid: tid} do
      metric =
        Metrics.sum("cache.invalidation.total",
          description: "Total cache invalidations",
          drop: &match?(%{a: "drop"}, &1),
          measurement: :count,
          unit: :each,
          tags: [:name]
        )

      {:ok, _handler_id} = Sum.register(metric, tid, self())

      :telemetry.execute([:cache, :invalidation], %{count: 23}, %{name: "users"})
      [t1] = :ets.lookup(tid, {metric.name, %{name: "users"}})

      :telemetry.execute([:cache, :invalidation], %{count: 3}, %{name: "clients"})
      [t2] = :ets.lookup(tid, {metric.name, %{name: "clients"}})

      :telemetry.execute([:cache, :invalidation], %{count: 5}, %{name: "users"})
      :telemetry.execute([:cache, :invalidation], %{count: 10}, %{name: "users", a: "drop"})
      [t3] = :ets.lookup(tid, {metric.name, %{name: "users"}})

      assert elem(t1, 1) == 23
      assert elem(t2, 1) == 3
      assert elem(t3, 1) == 28
      cleanup(tid)
    end

    test "records a times series for each tag kv pair and uses measurement from metadata", %{
      tid: tid
    } do
      metric =
        Metrics.sum("cache.invalidation.memory_total",
          description: "Total cache invalidation memory freed",
          measurement: fn _measurements, metadata ->
            metadata.cache_size
          end,
          unit: :kilobyte,
          tags: [:name]
        )

      {:ok, _handler_id} = Sum.register(metric, tid, self())

      :telemetry.execute([:cache, :invalidation], %{count: 23}, %{name: "users", cache_size: 1024})

      :telemetry.execute([:cache, :invalidation], %{count: 3}, %{name: "clients", cache_size: 512})

      :telemetry.execute([:cache, :invalidation], %{count: 5}, %{name: "users", cache_size: 256})

      [t1] = :ets.lookup(tid, {metric.name, %{name: "users"}})
      [t2] = :ets.lookup(tid, {metric.name, %{name: "clients"}})

      assert elem(t1, 1) == 1280
      assert elem(t2, 1) == 512

      cleanup(tid)
    end
  end

  describe "histogram" do
    # for metric <- [Counter, Distribution, LastValue, Sum]
    test "registers a handler", %{dist_tid: tid} do
      metric =
        Metrics.distribution("some.plug.call.duration",
          buckets: [
            0.005,
            0.01,
            0.025,
            0.05,
            0.075,
            0.1,
            0.15,
            0.2,
            0.3,
            0.5,
            1,
            2.5,
            5.0,
            7.5,
            10.0
          ],
          description: "Request length",
          event_name: [:some, :plug, :call, :stop],
          measurement: :duration,
          unit: {:native, :second},
          tags: [:method, :path_root],
          tag_values: fn %{conn: conn} ->
            %{
              method: conn.method,
              path_root: List.first(conn.path_info) || ""
            }
          end
        )

      {:ok, handler_id} = Distribution.register(metric, tid, self())

      handlers = :telemetry.list_handlers([])
      assert Enum.any?(handlers, &match?(^handler_id, &1.id))
      cleanup(tid)
    end

    test "records a times series for each tag kv pair using a measurement from the metadata", %{
      dist_tid: tid
    } do
      buckets = [
        256,
        512,
        1024,
        2048,
        4096
      ]

      metric =
        Metrics.distribution("some.plug.call.resp_payload_size",
          buckets: buckets,
          description: "Plug call response payload size",
          event_name: [:some, :plug, :call, :stop],
          measurement: fn _measurements, metadata ->
            metadata.conn.resp_size
          end,
          unit: :kilobyte,
          tags: [:method],
          tag_values: fn %{conn: conn} ->
            %{
              method: conn.method
            }
          end
        )

      {:ok, _handler_id} = Distribution.register(metric, tid, self())

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 5.6e7}, %{
        conn: %{method: "GET", path_info: ["users", "123"], resp_size: 180}
      })

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 1.1e8}, %{
        conn: %{method: "POST", path_info: ["products", "238"], resp_size: 4_000}
      })

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 8.7e7}, %{
        conn: %{method: "GET", path_info: ["users", "123"], resp_size: 2_000}
      })

      # , %{method: "GET", path_root: "users"}}
      key_1 = metric.name
      samples = :ets.lookup(tid, key_1)

      assert length(samples) == 3

      assert hd(samples) == {[:some, :plug, :call, :resp_payload_size], {%{method: "GET"}, 180}}

      cleanup(tid)
    end

    test "records a times series for each tag kv pair", %{dist_tid: tid} do
      buckets = [
        0.005,
        0.01,
        0.025,
        0.05,
        0.075,
        0.1,
        0.15,
        0.2,
        0.3,
        0.5,
        1,
        2.5,
        5.0,
        7.5,
        10.0
      ]

      metric =
        Metrics.distribution("some.plug.call.duration",
          buckets: buckets,
          description: "Plug call duration",
          event_name: [:some, :plug, :call, :stop],
          drop: &match?(%{conn: %{path_info: ["skip"]}}, &1),
          measurement: :duration,
          unit: {:native, :second},
          tags: [:method, :path_root],
          tag_values: fn %{conn: conn} ->
            %{
              method: conn.method,
              path_root: List.first(conn.path_info) || ""
            }
          end
        )

      {:ok, _handler_id} = Distribution.register(metric, tid, self())

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 5.6e7}, %{
        conn: %{method: "GET", path_info: ["users", "123"]}
      })

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 1.1e8}, %{
        conn: %{method: "POST", path_info: ["products", "238"]}
      })

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 8.7e7}, %{
        conn: %{method: "GET", path_info: ["users", "123"]}
      })

      :telemetry.execute([:some, :plug, :call, :stop], %{duration: 1.7e7}, %{
        conn: %{method: "GET", path_info: ["skip"]}
      })

      # , %{method: "GET", path_root: "users"}}
      key_1 = metric.name
      samples = :ets.lookup(tid, key_1)

      assert length(samples) == 3

      assert hd(samples) ==
               {[:some, :plug, :call, :duration], {%{method: "GET", path_root: "users"}, 0.056}}

      cleanup(tid)
    end
  end

  describe "error handling" do
    test "logs an error for missing measurement", %{tid: tid, dist_tid: dist_tid} do
      [
        {Metrics.last_value("test.event.measure",
           measurement: :nonexistent
         ), LastValue, tid},
        {Metrics.sum("test.event.measure",
           measurement: :nonexistent
         ), Sum, tid},
        {Metrics.distribution("test.event.measure",
           buckets: [1, 2, 3],
           measurement: :nonexistent
         ), Distribution, dist_tid}
      ]
      |> Enum.each(fn {metric, module, table} ->
        {:ok, handler_id} = apply(module, :register, [metric, table, self()])

        assert capture_log(fn ->
                 :telemetry.execute(metric.event_name, %{measure: 1})
               end) =~ "Measurement not found"

        [handler] = :telemetry.list_handlers(metric.event_name)

        assert handler.config.name == metric.name

        :telemetry.detach(handler_id)
      end)
    end

    test "logs an error for non-numeric measurement", %{tid: tid, dist_tid: dist_tid} do
      [
        {Metrics.last_value("test.event.measure",
           measurement: :measure
         ), LastValue, tid},
        {Metrics.sum("test.event.measure",
           measurement: fn _ -> "this isn't a number..." end
         ), Sum, tid},
        {Metrics.distribution("test.event.measure",
           buckets: [1, 2, 3],
           measurement: :measure
         ), Distribution, dist_tid}
      ]
      |> Enum.each(fn {metric, module, table} ->
        {:ok, handler_id} = apply(module, :register, [metric, table, self()])

        assert capture_log(fn ->
                 :telemetry.execute(metric.event_name, %{measure: "a"})
               end) =~ "Expected measurement to be a number"

        [handler] = :telemetry.list_handlers(metric.event_name)

        assert handler.config.name == metric.name

        :telemetry.detach(handler_id)
      end)
    end

    test "logs an error for missing tags", %{tid: tid, dist_tid: dist_tid} do
      [
        {Metrics.counter("test.event.measure",
           measurement: :measure,
           tags: [:missing_tag]
         ), Counter, tid},
        {Metrics.last_value("test.event.measure",
           measurement: :measure,
           tags: [:missing_tag]
         ), LastValue, tid},
        {Metrics.sum("test.event.measure",
           measurement: :measure,
           tags: [:missing_tag]
         ), Sum, tid},
        {Metrics.distribution("test.event.measure",
           buckets: [1, 2, 3],
           measurement: :measure,
           tags: [:missing_tag]
         ), Distribution, dist_tid}
      ]
      |> Enum.each(fn {metric, module, table} ->
        {:ok, handler_id} = apply(module, :register, [metric, table, self()])

        assert capture_log(fn ->
                 :telemetry.execute(metric.event_name, %{measure: 1}, %{})
               end) =~ "Tags missing from tag_values"

        [handler] = :telemetry.list_handlers(metric.event_name)

        assert handler.config.name == metric.name

        :telemetry.detach(handler_id)
      end)
    end
  end

  def cleanup(tid) do
    :ets.delete_all_objects(tid)

    :telemetry.list_handlers([])
    |> Enum.each(&:telemetry.detach(&1.id))
  end

  def fetch_metric(table_id, key) do
    case :ets.lookup(table_id, key) do
      [result] -> result
      _ -> :error
    end
  end
end
