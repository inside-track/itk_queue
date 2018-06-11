defmodule ITKQueue.Channel do
  @moduledoc """
  Provides methods for interacting with AMQP channels.
  """

  @doc """
  Opens a topic channel on the given connection.

  Returns an `AMQP.Channel`.
  """
  @spec open(connection :: AMQP.Connection.t()) :: AMQP.Channel.t()
  def open(connection) do
    if testing?() do
      %AMQP.Channel{}
    else
      {:ok, channel} = AMQP.Channel.open(connection)
      AMQP.Exchange.topic(channel, default_exchange())
      channel
    end
  end

  @doc """
  Closes a channel.
  """
  @spec close(channel :: AMQP.Channel.t()) :: :ok
  def close(channel) do
    if testing?() do
      :ok
    else
      AMQP.Channel.close(channel)
    end
  end

  @doc """
  Declares a queue and binds the routing key to it on the given channel. This sets
  up a queue so that messages sent with the routing key get directed to the queue.

  Returns the given `AMQP.Channel`.
  """
  @spec bind(
          channel :: AMQP.Channel.t(),
          queue_name :: String.t(),
          routing_key :: String.t(),
          options :: Keyword.t()
        ) :: AMQP.Channel.t()
  def bind(channel, queue_name, routing_key, options \\ []) do
    unless ITKQueue.testing?() do
      exchange = options |> bind_options() |> Keyword.get(:exchange)

      declare_queue(channel, queue_name, declare_options(options))
      AMQP.Basic.qos(channel, prefetch_count: consumer_count())
      AMQP.Queue.bind(channel, queue_name, exchange, routing_key: routing_key)
    end

    channel
  end

  @doc """
  Declares a queue.
  """
  @spec declare_queue(
          channel :: AMQP.Channel.t(),
          queue_name :: String.t(),
          options :: Keyword.t()
        ) :: AMQP.Channel.t()
  def declare_queue(channel, queue_name, options \\ []) do
    unless ITKQueue.testing?() do
      {:ok, _} = AMQP.Queue.declare(channel, queue_name, declare_options(options))
    end

    channel
  end

  @doc """
  Deletes a queue.
  """
  @spec delete_queue(channel :: AMQP.Channel.t(), queue_name :: String.t()) :: AMQP.Channel.t()
  def delete_queue(channel, queue_name) do
    unless ITKQueue.testing?() do
      {:ok, _} = AMQP.Queue.delete(channel, queue_name)
    end

    channel
  end

  defp default_exchange do
    Application.get_env(:itk_queue, :amqp_exchange)
  end

  defp consumer_count do
    Application.get_env(:itk_queue, :consumer_count, 10)
  end

  defp bind_options(options) do
    options
    |> Keyword.put_new(:exchange, default_exchange())
  end

  defp declare_options(options) do
    options
    |> Keyword.put_new(:arguments, [])
    |> Keyword.put_new(:auto_delete, false)
    |> Keyword.put_new(:durable, true)
  end

  @spec testing?() :: boolean
  defp testing? do
    Mix.env() == :test && !Application.get_env(:itk_queue, :running_library_tests, false)
  end
end
