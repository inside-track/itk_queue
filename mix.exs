defmodule ITKQueue.Mixfile do
  use Mix.Project

  @project_url "https://github.com/inside-track/itk_queue"
  @version "0.2.4"

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
      mod: {ITKQueue, []}
    ]
  end

  defp deps do
    [
      {:poison, "~> 2.0"},
      {:amqp, "~> 0.2"},
      {:ex_doc, ">= 0.0.0", only: :dev}
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
