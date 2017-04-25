use Mix.Config

config :itk_queue,
  amqp_url: "amqp://localhost:5672",
  amqp_exchange: "test",
  fallback_endpoint: false
