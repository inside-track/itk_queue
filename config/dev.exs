use Mix.Config

config :itk_queue,
  amqp_url: "amqp://localhost:5672",
  amqp_exchange: "development",
  fallback_endpoint: false,
  dead_letter_routing_key: "",
  max_retries: 10
