require Logger

defmodule ITKQueue.Consumer do
  @moduledoc """
  Monitors a queue for new messages and passes them to the subscribed handler.

  See `ITKQueue.ConsumerSupervisor.start_consumer/1`.
  """

  use GenServer

  alias ITKQueue.{ConnectionPool, Channel, Headers, Subscription, Retry, DefaultErrorHandler}

  @doc false
  def start_link(subscription = %Subscription{}) do
    GenServer.start_link(__MODULE__, subscription, [])
  end

  @doc false
  def init(subscription) do
    Process.flag(:trap_exit, true)
    subscribe(subscription)
  end

  @doc false
  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_info({:basic_cancel, _}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_info(
        {:basic_deliver, payload, meta},
        state = %{channel: channel, subscription: subscription}
      ) do
    consume(channel, meta, payload, subscription)
    {:noreply, state}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, _error}, %{
        subscription:
          subscription = %Subscription{queue_name: queue_name, routing_key: routing_key}
      }) do
    # connection died
    Logger.info(
      "Connection for subscription to #{queue_name} (#{routing_key}) closed",
      queue_name: queue_name,
      routing_key: routing_key
    )

    # wait for a connection to become available
    Process.sleep(5000)

    # resubscribe
    {:ok, state} = subscribe(subscription)
    {:noreply, state}
  end

  @doc false
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  defp subscribe(subscription = %Subscription{queue_name: queue_name, routing_key: routing_key}) do
    Logger.info(
      "Subscribing to #{queue_name} (#{routing_key})",
      queue_name: queue_name,
      routing_key: routing_key
    )

    ConnectionPool.with_connection(fn connection ->
      connection_monitor = Process.monitor(connection.pid)

      channel =
        connection
        |> Channel.open()
        |> Channel.bind(queue_name, routing_key)

      {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue_name, self())

      {:ok,
       %{
         channel: channel,
         subscription: subscription,
         connection_monitor: connection_monitor,
         consumer_tag: consumer_tag
       }}
    end)
  end

  defp consume(
         channel,
         meta = %{headers: headers},
         payload,
         subscription = %Subscription{queue_name: queue_name, routing_key: routing_key}
       ) do
    message = payload |> parse_payload |> set_message_uuid
    retry_count = Headers.get(headers, "retry_count")

    if retry_count do
      Logger.info(
        "Starting retry ##{retry_count} on #{payload}",
        message_id: message_uuid(message),
        queue_name: queue_name,
        routing_key: routing_key
      )
    else
      Logger.info(
        "Starting on #{payload}",
        message_id: message_uuid(message),
        queue_name: queue_name,
        routing_key: routing_key
      )
    end

    try do
      consume_message(message, channel, meta, subscription)
    rescue
      e ->
        Logger.error(
          "Queue error #{Exception.format(:error, e, System.stacktrace())}",
          message_id: message_uuid(message),
          queue_name: queue_name,
          routing_key: routing_key
        )

        retry_or_die(message, channel, meta, subscription, e)
    end
  end

  defp parse_payload(payload) do
    case use_atom_keys?() do
      true -> Poison.decode!(payload, keys: :atoms)
      _ -> Poison.decode!(payload)
    end
  end

  defp set_message_uuid(message = %{metadata: %{uuid: _}}), do: message

  defp set_message_uuid(message = %{"metadata" => %{"uuid" => _}}), do: message

  defp set_message_uuid(message = %{"metadata" => metadata}) do
    metadata = Map.put(metadata, "uuid", UUID.uuid4())
    Map.put(message, "metadata", metadata)
  end

  defp set_message_uuid(message) do
    metadata =
      message
      |> Map.get(:metadata, %{})
      |> Map.put(:uuid, UUID.uuid4())

    Map.put(message, :metadata, metadata)
  end

  defp message_uuid(%{metadata: %{uuid: uuid}}), do: uuid

  defp message_uuid(%{"metadata" => %{"uuid" => uuid}}), do: uuid

  defp message_uuid(_), do: nil

  defp consume_message(
         message,
         channel,
         meta = %{delivery_tag: tag, headers: headers},
         subscription = %Subscription{
           queue_name: queue_name,
           routing_key: routing_key,
           handler: handler
         }
       ) do
    res = handler.(message, headers)

    case res do
      {:retry, reason} ->
        retry_or_die(message, channel, meta, subscription, reason)

      {:reject, reason} ->
        reject(message, channel, meta, subscription, reason)

      _ ->
        AMQP.Basic.ack(channel, tag)

        Logger.info(
          "Completed",
          message_id: message_uuid(message),
          queue_name: queue_name,
          routing_key: routing_key
        )
    end
  end

  defp retry_or_die(
         message,
         channel,
         meta = %{headers: headers},
         subscription = %Subscription{},
         reason
       )
       when is_binary(reason) do
    if should_retry?(headers) do
      retry(message, channel, meta, subscription, reason)
    else
      reject(message, channel, meta, subscription, reason)
    end
  end

  defp retry_or_die(
         message,
         channel,
         meta = %{headers: headers},
         subscription = %Subscription{queue_name: queue_name, routing_key: routing_key},
         error
       ) do
    reason = Exception.message(error)

    if should_retry?(headers) do
      retry(message, channel, meta, subscription, reason)
    else
      error_handler().(queue_name, routing_key, Poison.encode!(message), error)
      reject(message, channel, meta, subscription, reason)
    end
  end

  defp should_retry?(headers) do
    max_retries() < 0 || Retry.count(headers) < max_retries()
  end

  defp retry(
         message,
         channel,
         meta = %{delivery_tag: tag},
         subscription = %Subscription{queue_name: queue_name, routing_key: routing_key},
         reason
       ) do
    Logger.info(
      "Retrying - #{reason}",
      message_id: message_uuid(message),
      queue_name: queue_name,
      routing_key: routing_key
    )

    AMQP.Basic.ack(channel, tag)
    Retry.delay(channel, subscription, message, meta)
  end

  defp reject(
         message,
         channel,
         %{delivery_tag: tag},
         %Subscription{queue_name: queue_name, routing_key: routing_key},
         reason
       )
       when is_binary(reason) do
    Logger.info(
      "Rejecting - #{reason}",
      message_id: message_uuid(message),
      queue_name: queue_name,
      routing_key: routing_key
    )

    AMQP.Basic.reject(channel, tag, requeue: false)
  end

  defp reject(message, channel, meta, subscription = %Subscription{}, error) do
    reason = Exception.message(error)
    reject(message, channel, meta, subscription, reason)
  end

  defp use_atom_keys? do
    Application.get_env(:itk_queue, :use_atom_keys, true)
  end

  defp error_handler do
    Application.get_env(:itk_queue, :error_handler, &DefaultErrorHandler.handle/4)
  end

  defp max_retries do
    Application.get_env(:itk_queue, :max_retries, -1)
  end

  def terminate(reason, %{
        channel: channel,
        connection_monitor: connection_monitor,
        consumer_tag: consumer_tag
      }) do
    Logger.info("Terminating consumer (#{reason})")

    Process.demonitor(connection_monitor)
    AMQP.Basic.cancel(channel, consumer_tag)
    Channel.close(channel)

    :normal
  end
end
