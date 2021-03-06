require Logger

defmodule ITKQueue.DefaultErrorHandler do
  alias ITKQueue.Behaviors.QueueErrorHandler

  @moduledoc """
  The default error handler.
  """

  @doc """
  Handles an error that occurred while processing a queue message. Just logs information about the message.
  """
  @behaviour QueueErrorHandler

  @spec handle(
          queue_name :: String.t(),
          routing_key :: String.t(),
          payload :: String.t(),
          e :: Exception.t()
        ) :: no_return
  def handle(queue_name, routing_key, payload, e) do
    Logger.error("An error occurred in #{queue_name} handler (#{routing_key}):")
    Logger.error("Message:")
    Logger.error(inspect(payload, limit: :infinity, printable_limit: :infinity))
    Logger.error(Exception.format(:error, e))
  end
end
