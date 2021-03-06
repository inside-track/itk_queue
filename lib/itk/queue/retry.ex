defmodule ITKQueue.Retry do
  @moduledoc """
  Handles retrying messages that fail to process.

  This is accomplished by creating a new temporary queue and publishing the message to that queue.

  The queue is configured so that the message expires after a delay and when it expires it is republished with
  the original routing key.
  """

  alias ITKQueue.{Headers, Publisher, Subscription}

  @doc """
  Retry the given message after a delay.

  The message will go into a temporary "retry" queue and, after a delay, will be republished with the
  original routing key.
  """
  @spec delay(
          channel :: AMQP.Channel.t(),
          subscription :: Subscription.t(),
          message :: ITKQueue.message(),
          meta :: ITKQueue.metadata()
        ) :: :ok | no_return
  def delay(channel, %Subscription{queue_name: queue_name, routing_key: routing_key}, message, %{
        headers: headers
      })
      when is_map(message) do
    retry_count = count(headers) + 1
    headers = [{"retry_count", :long, retry_count}, {"original_queue", :longstr, queue_name}]
    identifier = DateTime.utc_now() |> DateTime.to_unix(:nanosecond)
    queue_name = "retry.queue.#{queue_name}.#{identifier}"
    expiration = expiration_time(retry_count)

    {:ok, _} =
      AMQP.Queue.declare(
        channel,
        queue_name,
        durable: true,
        auto_delete: false,
        arguments: [
          {"x-dead-letter-exchange", :longstr, exchange()},
          {"x-message-ttl", :long, expiration},
          {"x-expires", :long, 30_000},
          {"x-dead-letter-routing-key", :longstr, routing_key}
        ]
      )

    :ok = AMQP.Queue.bind(channel, queue_name, exchange(), routing_key: queue_name)
    Publisher.publish(queue_name, message, headers, [])
  end

  @spec count(Headers.t()) :: non_neg_integer
  def count(headers) do
    Headers.get(headers, "retry_count", 0)
  end

  @spec exchange :: String.t()
  defp exchange do
    Application.get_env(:itk_queue, :amqp_exchange)
  end

  @spec expiration_time(non_neg_integer) :: non_neg_integer
  defp expiration_time(retry_count) when retry_count > 10, do: 10_000
  defp expiration_time(retry_count), do: 1_000 * retry_count
end
