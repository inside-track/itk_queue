defmodule ITKQueue do
  @moduledoc """
  Provides convenience functions for subscribing to queues and publishing messages.
  """
  use Application

  alias ITKQueue.{Publisher, ConsumerSupervisor, Subscription}

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(ITKQueue.Connection, []),
      worker(ITKQueue.Publisher, []),
      supervisor(ITKQueue.ConsumerSupervisor, [])
    ]

    opts = [strategy: :one_for_one, name: ITKQueue.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Subscribes to a queue.

  The handler is expected to be a function that handles the message. If the function raises an exception the message
  will be moved to a temporary queue and retried after a delay.

  ## Examples

      iex> ITKQueue.subscribe("students-data-sync", "data.sync", fn(message) -> IO.puts(inspect(message)) end)

  """
  def subscribe(queue_name, routing_key, handler) when is_function(handler, 1) do
    subscribe(queue_name, routing_key, fn(message, _headers) -> handler.(message) end)
  end

  def subscribe(queue_name, routing_key, handler) when is_function(handler, 2) do
    subscription = %Subscription{queue_name: queue_name, routing_key: routing_key, handler: handler}
    {:ok, _pid} = ConsumerSupervisor.start_consumer(subscription)
  end

  @doc """
  Publish a message. Expects the message to be something that can be encoded as JSON.

  ## Examples

      iex> ITKQueue.publish("data.sync", %{type: "user", data: %{name: "Test User"}})

  """
  def publish(routing_key, message) do
    Publisher.publish(routing_key ,message)
  end
end
