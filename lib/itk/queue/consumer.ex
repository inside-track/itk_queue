require Logger

defmodule ITKQueue.Consumer do
  @moduledoc """
  Monitors a queue for new messages and passes them to the subscribed handler.

  See `ITKQueue.ConsumerSupervisor.start_consumer/1`.
  """

  defstruct channel: nil,
            subscription: nil

  use GenServer

  alias ITKQueue.{Channel, DefaultErrorHandler, Headers, Retry, Subscription}

  @type t :: %__MODULE__{
          channel: AMQP.Channel.t(),
          subscription: Subscription.t()
        }

  @reconnect_interval 1000

  @doc false
  def start_link(subscription = %Subscription{}) do
    GenServer.start_link(__MODULE__, subscription, name: {:global, subscription.queue_name})
  end

  @doc false
  def init(subscription = %Subscription{}) do
    Process.flag(:trap_exit, true)
    state = subscribe(subscription)
    {:ok, state}
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
  def handle_info(
        {:basic_deliver, payload, meta},
        state = %{channel: channel, subscription: subscription}
      ) do
    consume_async(channel, meta, payload, subscription)
    {:noreply, state}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state = %{subscription: sub}) do
    Logger.error(
      "Channel subscribed to #{sub.queue_name} (#{sub.routing_key}) went down: #{inspect(reason)}"
    )

    Process.send_after(self(), :subscribe, @reconnect_interval)
    {:noreply, state}
  end

  @doc false
  def handle_info(:subscribe, %__MODULE__{subscription: subscription}) do
    state = subscribe(subscription)
    {:noreply, state}
  end

  @doc false
  def handle_info(_, state) do
    {:noreply, state}
  end

  @doc false
  def handle_call(:connection, _from, state) do
    {:reply, connection(), state}
  end

  defp connection do
    case GenServer.call(ITKQueue.ConsumerConnection, :connection) do
      nil -> {:error, :connection_lost}
      connection -> {:ok, connection}
    end
  catch
    _ ->
      {:error, :connection_lost}
  end

  defp subscribe(subscription = %Subscription{queue_name: queue_name, routing_key: routing_key}) do
    Logger.info(
      "Subscribing to #{queue_name} (#{routing_key})",
      queue_name: queue_name,
      routing_key: routing_key
    )

    case connection() do
      {:ok, connection} ->
        channel =
          connection
          |> Channel.open()
          |> Channel.bind(queue_name, routing_key)

        Process.monitor(channel.pid)

        {:ok, _} = AMQP.Basic.consume(channel, queue_name, self())
        %__MODULE__{channel: channel, subscription: subscription}

      _ ->
        Logger.error(
          "Subscribe error: cannot get connection",
          queue_name: queue_name,
          routing_key: routing_key
        )

        Process.send_after(self(), :subscribe, @reconnect_interval)
        %__MODULE__{subscription: subscription}
    end
  end

  defp consume_async(channel, meta, payload, subscription) do
    spawn(fn ->
      consume(channel, meta, payload, subscription)
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

    try do
      if retry_count do
        retry_message(message, channel, meta, subscription)
      else
        Logger.info(
          "Starting on #{inspect(message)}",
          message_id: message_uuid(message),
          queue_name: queue_name,
          routing_key: routing_key
        )

        consume_message(message, channel, meta, subscription)
      end
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
      true -> Jason.decode!(payload, keys: :atoms)
      _ -> Jason.decode!(payload)
    end
  end

  defp set_message_uuid(message = %{metadata: %{uuid: _}}), do: message

  defp set_message_uuid(message = %{"metadata" => %{"uuid" => _}}), do: message

  defp set_message_uuid(message = %{"metadata" => metadata}) do
    metadata = Map.put(metadata, "uuid", UUID.uuid4())
    Map.put(message, "metadata", metadata)
  end

  defp set_message_uuid(message = %{metadata: metadata}) do
    metadata = Map.put(metadata, :uuid, UUID.uuid4())
    Map.put(message, :metadata, metadata)
  end

  defp set_message_uuid(message) do
    if use_atom_keys?() do
      metadata = %{uuid: UUID.uuid4()}
      Map.put(message, :metadata, metadata)
    else
      metadata = %{"uuid" => UUID.uuid4()}
      Map.put(message, "metadata", metadata)
    end
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

  defp retry_message(
         message,
         channel,
         meta = %{delivery_tag: tag, headers: headers},
         subscription = %Subscription{
           queue_name: queue_name,
           routing_key: routing_key
         }
       ) do
    retry_count = Headers.get(headers, "retry_count")
    original_queue = Headers.get(headers, "original_queue")

    if original_queue == queue_name do
      Logger.info(
        "Starting retry ##{retry_count} on #{inspect(message)}",
        message_id: message_uuid(message),
        queue_name: queue_name,
        routing_key: routing_key
      )

      consume_message(message, channel, meta, subscription)
    else
      # This consumer has already consumed this message, don't consume it again.
      AMQP.Basic.ack(channel, tag)
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
      error_handler().handle(queue_name, routing_key, Jason.encode!(message), error)
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
    Application.get_env(:itk_queue, :error_handler, DefaultErrorHandler)
  end

  defp max_retries do
    Application.get_env(:itk_queue, :max_retries, -1)
  end
end
