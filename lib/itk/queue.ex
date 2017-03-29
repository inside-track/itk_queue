require Logger

defmodule ITK.Queue do
  @moduledoc """
  Provides convenience methods for subscribing to queues and publishing messages.
  """

  use GenServer

  alias ITK.Queue.Subscription

  @url Application.get_env(:itk_queue, :amqp_url)
  @exchange Application.get_env(:itk_queue, :amqp_exchange)
  @name :itk_queue

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: @name])
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_cast({:subscribe, subscription}, state) do
    Logger.info("Subscribing to #{subscription.queue_name} (#{subscription.routing_key})")
    connection = state[:connection] || connect()
    subscriptions = [subscription | Map.get(state, :subscriptions, [])]
    state =
      state
      |> Map.put(:connection, connection)
      |> Map.put(:subscriptions, subscriptions)

    subscribe(connection, subscription)
    {:noreply, state}
  end

  def handle_cast({:publish, routing_key, message}, state) do
    connection = state[:connection] || connect()
    state = state |> Map.put(:connection, connection)
    channel = open_channel(connection)
    {:ok, payload} = Poison.encode(message)

    AMQP.Basic.publish(channel, @exchange, routing_key, payload, persistent: true)
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    connection = connect()
    state = state |> Map.put(:connection, connection)

    state
    |> Map.get(:subscriptions, [])
    |> Enum.each(fn(subscription) -> subscribe(connection, subscription) end)
    {:noreply, state}
  end

  @doc """
  Subscribes to a queue. The given process will need to handle casts for `{:message, data}` where data is the parsed message.

  ## Examples

      iex> ITK.Queue.subscribe("students-data-sync", "data.sync", self())

  """
  def subscribe(queue_name, routing_key, handler) when is_pid(handler) do
    subscribe(queue_name, routing_key, fn(data) ->
      GenServer.cast(handler, {:message, data})
    end)
  end

  @doc """
  Subscribes to a queue. The handler function will be called with the parsed message when received.

  ## Examples

      iex> ITK.Queue.subscribe("students-data-sync", "data.sync", fn(message) -> IO.puts(inspect(message)) end)

  """
  def subscribe(queue_name, routing_key, handler) when is_function(handler, 1) do
    subscription = %Subscription{queue_name: queue_name, routing_key: routing_key, handler: handler}
    GenServer.cast(@name, {:subscribe, subscription})
  end

  @doc """
  Publish a message. Expects the message to be something that can be encoded as JSON.

  ## Examples

      iex> ITK.Queue.publish("data.sync", %{type: "user", data: %{name: "Test User"}})

  """
  def publish(routing_key, message) do
    GenServer.cast(@name, {:publish, routing_key, message})
  end

  defp subscribe(connection, %Subscription{queue_name: queue_name, routing_key: routing_key, handler: handler}) do
    channel =
      connection
      |> open_channel
      |> bind_channel(queue_name, routing_key)

    {:ok, _} = AMQP.Queue.subscribe(channel, queue_name, fn (data, _) ->
      parsed_data = Poison.Parser.parse!(data, keys: :atoms)
      handler.(parsed_data)
    end)
  end

  defp connect do
    case AMQP.Connection.open(@url) do
      {:ok, connection} ->
        Process.monitor(connection.pid)
        connection
      {:error, _} ->
        Process.sleep(5000)
        connect()
    end
  end

  defp open_channel(connection) do
    {:ok, channel} = AMQP.Channel.open(connection)
    AMQP.Exchange.topic(channel, @exchange)
    channel
  end

  defp bind_channel(channel, queue_name, routing_key) do
    AMQP.Basic.qos(channel, prefetch_count: 1)
    AMQP.Queue.declare(channel, queue_name, durable: true, auto_delete: false)
    AMQP.Queue.bind(channel, queue_name, @exchange, routing_key: routing_key)
    channel
  end
end
