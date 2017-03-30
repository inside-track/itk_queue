require Logger

defmodule ITK.Queue.Consumer do
  @moduledoc """
  Monitors a queue for new messages and passes them to the subscribed handler.

  See `ITK.Queue.ConsumerSupervisor.start_consumer/1`.
  """

  use GenServer

  alias ITK.Queue.{Connection, Channel, Subscription, Retry}

  @doc false
  def start_link(subscription = %Subscription{}) do
    GenServer.start_link(__MODULE__, subscription, [])
  end

  @doc false
  def init(subscription = %Subscription{queue_name: queue_name, routing_key: routing_key}) do
    Logger.info("Subscribing to #{queue_name} (#{routing_key})")
    channel =
      Connection.connect()
      |> Channel.open()
      |> Channel.bind(queue_name, routing_key)
    {:ok, _} = AMQP.Basic.consume(channel, queue_name, self())
    {:ok, %{channel: channel, subscription: subscription}}
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
    spawn fn -> consume(channel, meta, payload, subscription) end
    {:noreply, state}
  end

  defp consume(channel, meta = %{delivery_tag: tag, headers: headers}, payload, subscription = %Subscription{handler: handler}) do
    try do
      parsed_data = Poison.Parser.parse!(payload, keys: :atoms)
      handler.(parsed_data, headers)
      AMQP.Basic.ack(channel, tag)
    rescue
      _ ->
        Retry.delay(channel, subscription, payload, meta)
        AMQP.Basic.ack(channel, tag)
    end
  end
end
