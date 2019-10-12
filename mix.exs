defmodule TelemetryMetricsPrometheus.Core.MixProject do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :telemetry_metrics_prometheus_core,
      version: @version,
      elixir: "~> 1.6",
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
      {:dialyxir, "~> 1.0.0-rc.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.21", only: [:dev, :docs]},
      {:excoveralls, "~> 0.11.2", only: :test, runtime: false},
      {:telemetry, "~> 0.4"},
      {:telemetry_metrics, "~> 0.3"}
    ]
  end

  defp docs do
    [
      main: "overview",
      canonical: "http://hexdocs.pm/telemetry_metrics_prometheus_core",
      source_url: "https://github.com/bryannaegele/telemetry_metrics_prometheus_core",
      source_ref: "v#{@version}",
      extras: [
        "docs/overview.md"
      ]
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
      links: %{"GitHub" => "https://github.com/bryannaegele/telemetry_metrics_prometheus_core"}
    ]
  end
end
