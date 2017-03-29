defmodule ITK.Queue.Consumer do
  @moduledoc false

  use GenServer

  def start_link(channel, handler) do
    GenServer.start_link(__MODULE__, %{channel: channel, handler: handler}, [])
  end

  def init(args = %{channel: _channel, handler: _handler}) do
    {:ok, args}
  end

  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_cancel, _}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{delivery_tag: tag}}, state = %{channel: channel, handler: handler}) do
    spawn fn -> consume(channel, tag, payload, handler) end
    {:noreply, state}
  end

  defp consume(channel, tag, payload, handler) do
    parsed_data = Poison.Parser.parse!(payload, keys: :atoms)
    handler.(parsed_data)
    AMQP.Basic.ack(channel, tag)
  end
end
