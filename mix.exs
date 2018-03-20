defmodule ITKQueue.Mixfile do
  use Mix.Project

  @project_url "https://github.com/inside-track/itk_queue"
  @version "0.8.0"

  def project do
    [
      app: :itk_queue,
      version: @version,
      elixir: "~> 1.6",
      description:
        "Provides convenience methods for subscribing to queues and publishing messages.",
      source_url: @project_url,
      homepage_url: @project_url,
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :amqp],
      mod: {ITKQueue, []}
    ]
  end

  defp deps do
    [
      {:poison, "~> 3.0"},
      {:amqp, "~> 0.2"},
      {:httpoison, "~> 1.0"},
      {:uuid, "~> 1.1"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:credo, git: "https://github.com/rrrene/credo.git", only: [:dev, :test]},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Adam Vaughan", "Grant Austin", "Daniel Hedlund"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @project_url
      }
    ]
  end
end
