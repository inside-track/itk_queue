defmodule ITKQueue.Channel do
  @moduledoc """
  Provides methods for interacting with AMQP channels.
  """

  @exchange Application.get_env(:itk_queue, :amqp_exchange)
  @dead_letter_routing_key Application.get_env(:itk_queue, :dead_letter_routing_key)
  @consumer_count Application.get_env(:itk_queue, :consumer_count, 10)

  @doc """
  Opens a topic channel on the given connection.

  Returns an `AMQP.Channel`.
  """
  @spec open(connection :: AMQP.Connection.t) :: AMQP.Channel.t
  def open(connection) do
    {:ok, channel} = AMQP.Channel.open(connection)
    AMQP.Exchange.topic(channel, @exchange)
    channel
  end

  @doc """
  Closes a channel.
  """
  @spec close(channel :: AMQP.Channel.t) :: :ok
  def close(channel) do
    AMQP.Channel.close(channel)
  end

  @doc """
  Declares a queue and binds the routing key to it on the given channel. This sets
  up a queue so that messages sent with the routing key get directed to the queue.

  Returns the given `AMQP.Channel`.
  """
  @spec bind(channel :: AMQP.Channel.t, queue_name :: String.t, routing_key :: String.t) :: AMQP.Channel.t
  def bind(channel, queue_name, routing_key) do
    AMQP.Basic.qos(channel, prefetch_count: @consumer_count)
    AMQP.Queue.declare(channel, queue_name, durable: true, auto_delete: false, arguments: bind_arguments())
    AMQP.Queue.bind(channel, queue_name, @exchange, routing_key: routing_key)
    channel
  end

  defp bind_arguments do
    case @dead_letter_routing_key do
      nil -> []
      _ -> [
        {"x-dead-letter-exchange", :longstr, @exchange},
        {"x-dead-letter-routing-key", :longstr, @dead_letter_routing_key}
      ]
    end
  end
end
