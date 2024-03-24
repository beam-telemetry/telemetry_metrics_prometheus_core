defmodule TelemetryMetricsPrometheus.Core.MixProject do
  use Mix.Project

  @version "1.2.1"

  def project do
    [
      app: :telemetry_metrics_prometheus_core,
      version: @version,
      elixir: "~> 1.12",
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_core_path: "plts",
        plt_local_path: "plts"
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:telemetry_metrics, "~> 0.6 or ~> 1.0"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.28", only: [:dev, :docs]},
      {:excoveralls, "~> 0.17", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "TelemetryMetricsPrometheus.Core",
      canonical: "http://hexdocs.pm/telemetry_metrics_prometheus_core",
      source_url: "https://github.com/beam-telemetry/telemetry_metrics_prometheus_core",
      source_ref: "v#{@version}",
      extras: []
    ]
  end

  defp preferred_cli_env do
    [
      docs: :docs,
      dialyzer: :test,
      "coveralls.json": :test
    ]
  end

  defp description do
    """
    Provides a Prometheus format reporter for Telemetry.Metrics definitions.
    """
  end

  defp package do
    [
      maintainers: ["Bryan Naegele"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_metrics_prometheus_core"}
    ]
  end
end
