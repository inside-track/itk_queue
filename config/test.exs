use Mix.Config

config :itk_queue,
  amqp_url: "amqp://localhost:5672",
  amqp_exchange: "test",
  fallback_endpoint: false,
  running_library_tests: true,
  max_retries: 10,
  env: Mix.env()
