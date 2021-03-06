defmodule ITKQueue.Mixfile do
  use Mix.Project

  @project_url "https://github.com/inside-track/itk_queue"
  @version "0.12.1"

  def project do
    [
      app: :itk_queue,
      version: @version,
      elixir: "~> 1.8",
      description:
        "Provides convenience methods for subscribing to queues and publishing messages.",
      source_url: @project_url,
      homepage_url: @project_url,
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix],
        plt_add_deps: true
      ]
    ]
  end

  def application do
    [
      extra_applications: [:lager, :logger, :amqp],
      mod: {ITKQueue, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.2"},
      {:httpoison, "~> 1.7"},
      {:amqp, "~> 1.5"},
      {:uuid, "~> 1.1"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, "~> 0.19.0", only: :dev},
      {:credo, "~> 1.4.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Maruika Wei", "Grady Griffin"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @project_url
      }
    ]
  end
end
