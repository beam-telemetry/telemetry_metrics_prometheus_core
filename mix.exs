defmodule TelemetryMetricsPrometheus.Core.MixProject do
  use Mix.Project

  @version "1.0.2"

  def project do
    [
      app: :telemetry_metrics_prometheus_core,
      version: @version,
      elixir: "~> 1.7",
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
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
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry, "~> 0.4 or ~> 1.0.0"},
      {:dialyxir, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.23", only: [:dev, :docs]},
      {:excoveralls, "~> 0.13.4", only: :test, runtime: false}
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
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_metrics_prometheus_core"}
    ]
  end
end
