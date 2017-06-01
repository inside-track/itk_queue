require Logger

defmodule ITKQueue.Consumer do
  @moduledoc """
  Monitors a queue for new messages and passes them to the subscribed handler.

  See `ITKQueue.ConsumerSupervisor.start_consumer/1`.
  """

  use GenServer

  alias ITKQueue.{Connection, Channel, Subscription, Retry}

  @use_atom_keys Application.get_env(:itk_queue, :use_atom_keys, true)
  @error_handler Application.get_env(:itk_queue, :error_handler, &ITKQueue.DefaultErrorHandler.handle/4)

  @doc false
  def start_link(subscription = %Subscription{}) do
    GenServer.start_link(__MODULE__, subscription, [])
  end

  @doc false
  def init(subscription) do
    subscribe(subscription)
  end

  @doc false
  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_info({:basic_cancel, _}, state) do
    {:stop, :normal, state}
  end

  @doc false
  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_info({:basic_deliver, payload, meta}, state = %{channel: channel, subscription: subscription}) do
    Task.start(fn -> consume(channel, meta, payload, subscription) end)
    {:noreply, state}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, _error}, %{subscription: subscription}) do
    # connection died, resubscribe
    {:ok, state} = subscribe(subscription)
    {:noreply, state}
  end

  defp subscribe(subscription = %Subscription{queue_name: queue_name, routing_key: routing_key}) do
    Logger.info("Subscribing to #{queue_name} (#{routing_key})")
    connection = Connection.connect()
    Process.monitor(connection.pid)
    channel =
      connection
      |> Channel.open()
      |> Channel.bind(queue_name, routing_key)
    {:ok, _} = AMQP.Basic.consume(channel, queue_name, self())
    {:ok, %{channel: channel, subscription: subscription}}
  end

  defp consume(channel, meta = %{delivery_tag: tag, headers: headers}, payload, subscription = %Subscription{queue_name: queue_name, routing_key: routing_key, handler: handler}) do
    try do
      parsed_data =
        case @use_atom_keys do
          true -> Poison.Parser.parse!(payload, keys: :atoms)
          _ -> Poison.Parser.parse!(payload)
        end
      handler.(parsed_data, headers)
      AMQP.Basic.ack(channel, tag)
    rescue
      e ->
        @error_handler.(queue_name, routing_key, payload, e)
        Retry.delay(channel, subscription, payload, meta)
        AMQP.Basic.ack(channel, tag)
    end
  end
end
