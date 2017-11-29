use Mix.Config

config :logger, :console, metadata: [:message_id, :queue_name, :routing_key]

case Mix.env() do
  :dev -> import_config "dev.exs"
  :test -> import_config "test.exs"
end
