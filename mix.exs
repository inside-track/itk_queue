defmodule ItkQueue.Mixfile do
  use Mix.Project

  @project_url "https://github.com/inside-track/itk_queue"
  @version "0.1.0"

  def project do
    [
      app: :itk_queue,
      version: @version,
      elixir: "~> 1.4",
      description: "Provides convenience methods for subscribing to queues and publishing messages.",
      source_url: @project_url,
      homepage_url: @project_url,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :amqp],
      mod: {ItkQueue, []}
    ]
  end

  defp deps do
    [
      {:poison, "~> 3.1"},
      {:amqp, "~> 0.2"}
    ]
  end

  defp package do
    [
      maintainers: ["Adam Vaughan"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @project_url
      }
    ]
  end
end
