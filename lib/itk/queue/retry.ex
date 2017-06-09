defmodule ITKQueue.Retry do
  @moduledoc """
  Handles retrying messages that fail to process.

  This is accomplished by creating a new temporary queue and pubishing the message to that queue.

  The queue is configured so that the message expires after a delay and when it expires it is republished with
  the original routing key.
  """

  alias ITKQueue.{Subscription, Publisher}

  @exchange Application.get_env(:itk_queue, :amqp_exchange)

  @doc """
  Retry the given message after a delay.

  The message will go into a temporary "retry" queue and, after a delay, will be republished with the
  original routing key.
  """
  @spec delay(channel :: AMQP.Channel.t, subscription :: Subscription.t, payload :: String.t, meta :: Map.t) :: no_return
  def delay(channel, %Subscription{routing_key: routing_key}, payload, %{delivery_tag: tag, headers: headers}) do
    retry_count = ITKQueue.Headers.get(headers, "retry_count", 0) + 1
    headers = [{"retry_count", :long, retry_count}]
    queue_name = "retry.queue.#{tag}"

    expiration =
      cond do
        retry_count > 10 -> 10_000
        true -> 1_000 * retry_count
      end

    AMQP.Queue.declare(channel, queue_name, durable: true, auto_delete: false, arguments: [{"x-dead-letter-exchange", :longstr, @exchange}, {"x-message-ttl", :long, expiration}, {"x-expires", :long, expiration * 2}, {"x-dead-letter-routing-key", :longstr, routing_key}])
    AMQP.Queue.bind(channel, queue_name, @exchange, routing_key: queue_name)
    Publisher.publish(queue_name, Poison.Parser.parse!(payload), headers)
  end
end
