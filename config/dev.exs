use Mix.Config

config :itk_queue,
  amqp_url: "amqp://localhost:5672",
  amqp_exchange: "development",
  fallback_endpoint: false,
  max_retries: 10,
  env: Mix.env()

# silent amqp rabbit_common logging
config :lager,
  error_logger_redirect: true,
  crash_log: false,
  handlers: [level: :critical]
