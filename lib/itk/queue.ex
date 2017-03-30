defmodule ITK.Queue do
  @moduledoc """
  Provides convenience methods for subscribing to queues and publishing messages.
  """

  alias ITK.Queue.{Publisher, ConsumerSupervisor, Subscription}

  @doc """
  Subscribes to a queue.

  The handler is expected to be a function that handles the message. If the function raises an exception the message
  will not be acknowledged and will be left in the queue for another consumer to handle.

  ## Examples

      iex> ITK.Queue.subscribe("students-data-sync", "data.sync", fn(message) -> IO.puts(inspect(message)) end)

  """
  def subscribe(queue_name, routing_key, handler) when is_function(handler, 1) do
    subscription = %Subscription{queue_name: queue_name, routing_key: routing_key, handler: handler}
    {:ok, _pid} = ConsumerSupervisor.start_consumer(subscription)
  end

  @doc """
  Publish a message. Expects the message to be something that can be encoded as JSON.

  ## Examples

      iex> ITK.Queue.publish("data.sync", %{type: "user", data: %{name: "Test User"}})

  """
  def publish(routing_key, message) do
    Publisher.publish(routing_key ,message)
  end
end
