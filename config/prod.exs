use Mix.Config

config :itk_queue,
  env: Mix.env()

# silent amqp rabbit_common logging
config :lager,
  error_logger_redirect: false,
  crash_log: false,
  handlers: [level: :critical]
