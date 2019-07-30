defmodule TelemetryMetricsPrometheus.Core.ReporterSupervisor do
  use Supervisor

  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    children = [
      {:telemetry_poller,
       [measurements: args[:measurements], name: String.to_atom("#{args[:name]}_poller")]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
