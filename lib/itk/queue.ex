defmodule ITKQueue do
  @moduledoc """
  Provides convenience functions for subscribing to queues and publishing messages.
  """
  use Application

  alias ITKQueue.{Channel, ConnectionPool, ConsumerSupervisor, Publisher, Subscription}

  @type message :: %{String.t() => any}
  @type metadata :: %{atom => any}

  @doc false
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: ITKQueue.Supervisor]

    Mix.env()
    |> children
    |> Supervisor.start_link(opts)
  end

  defp children(:test) do
    if running_library_tests?() do
      children()
    else
      []
    end
  end

  defp children(_), do: children()

  defp children do
    import Supervisor.Spec

    [
      worker(ITKQueue.ConnectionPool, []),
      supervisor(ITKQueue.ConsumerSupervisor, []),
      worker(ITKQueue.Workers, [])
    ]
  end

  @doc """
  Subscribes to a queue.

  The handler is expected to be a function that handles the message. If the function raises an exception the message
  will be moved to a temporary queue and retried after a delay.

  ## Examples

      iex> ITKQueue.subscribe("students-data-sync", "data.sync", fn(message) -> IO.puts(inspect(message)) end)

  """
  @spec subscribe(
          queue_name :: String.t(),
          routing_key :: String.t(),
          handler :: (any() -> any())
        ) :: {:ok, pid}
  def subscribe(queue_name, routing_key, handler) when is_function(handler, 1) do
    subscribe(queue_name, routing_key, fn message, _headers -> handler.(message) end)
  end

  @spec subscribe(
          queue_name :: String.t(),
          routing_key :: String.t(),
          handler :: (any(), any() -> any())
        ) :: {:ok, pid}
  def subscribe(queue_name, routing_key, handler) when is_function(handler, 2) do
    if Mix.env() == :test && !running_library_tests?() do
      {:ok, :ok}
    else
      subscription = %Subscription{
        queue_name: queue_name,
        routing_key: routing_key,
        handler: handler
      }

      {:ok, _pid} = ConsumerSupervisor.start_consumer(subscription)
    end
  end

  @doc """
  Publish a message. Expects the message to be something that can be encoded as JSON.

  ## Examples

      iex> ITKQueue.publish("data.sync", %{type: "user", data: %{name: "Test User"}})

  """
  @spec publish(routing_key :: String.t(), message :: map(), options :: Keyword.t()) :: :ok
  def publish(routing_key, message, options \\ []) do
    stacktrace = Process.info(self(), :current_stacktrace)
    Publisher.publish(routing_key, message, [], elem(stacktrace, 1), options)
  end

  @doc """
  Declares a queue.
  """
  @spec declare_queue(queue_name :: String.t(), options :: Keyword.t()) :: :ok | no_return
  def declare_queue(queue_name, options \\ []) do
    unless testing?() do
      ConnectionPool.with_channel(fn channel ->
        Channel.declare_queue(channel, queue_name, options)
      end)
    end

    :ok
  end

  @doc """
  Deletes a queue.
  """
  @spec delete_queue(queue_name :: String.t()) :: :ok | no_return
  def delete_queue(queue_name) do
    unless testing?() do
      ConnectionPool.with_channel(fn channel ->
        Channel.delete_queue(channel, queue_name)
      end)
    end

    :ok
  end

  @doc false
  def testing? do
    Mix.env() == :test && !running_library_tests?()
  end

  @doc false
  def running_library_tests? do
    Application.get_env(:itk_queue, :running_library_tests, false)
  end
end
