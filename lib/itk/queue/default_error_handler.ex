require Logger

defmodule ITKQueue.DefaultErrorHandler do
  def handle(queue_name, routing_key, payload, e) do
    Logger.error("An error occurred in #{queue_name} handler (#{routing_key}):")
    Logger.error(inspect(e))
    Logger.error("Message:")
    Logger.error(inspect(payload))
  end
end
