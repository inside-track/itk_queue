defmodule ITKQueue.Consumer do
  @moduledoc """
  Monitors a queue for new messages and passes them to the subscribed handler.

  See `ITKQueue.ConsumerSupervisor.start_consumer/1`.
  """

  use GenServer

  alias ITKQueue.{Connection, Channel, Subscription, Retry, SyslogLogger}

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
    SyslogLogger.info(queue_name, routing_key, "Subscribing to #{queue_name} (#{routing_key})")
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
    message = payload |> parse_payload |> set_message_uuid
    retry_count = ITKQueue.Headers.get(headers, "retry_count")

    if retry_count do
      SyslogLogger.info(queue_name, routing_key, "#{message_uuid(message)}: Starting retry ##{retry_count} on #{payload}")
    else
      SyslogLogger.info(queue_name, routing_key, "#{message_uuid(message)}: Starting on #{payload}")
    end

    try do
      consume_message(message, channel, meta, subscription)
    rescue
      e ->
        SyslogLogger.error(queue_name, routing_key, "#{message_uuid(message)}: Queue error #{Exception.format(:error, e, System.stacktrace)}")
        @error_handler.(queue_name, routing_key, payload, e)
        Retry.delay(channel, subscription, message, meta)
        AMQP.Basic.ack(channel, tag)
    end
  end

  defp parse_payload(payload) do
    case @use_atom_keys do
      true -> Poison.Parser.parse!(payload, keys: :atoms)
      _ -> Poison.Parser.parse!(payload)
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

  defp consume_message(message, channel, meta = %{delivery_tag: tag, headers: headers}, subscription = %Subscription{queue_name: queue_name, routing_key: routing_key, handler: handler}) do
    res = handler.(message, headers)
    AMQP.Basic.ack(channel, tag)

    case res do
      {:retry, reason} ->
        SyslogLogger.info(queue_name, routing_key, "#{message_uuid(message)}: Retrying - #{reason}")
        Retry.delay(channel, subscription, message, meta)
      _ ->
        SyslogLogger.info(queue_name, routing_key, "#{message_uuid(message)}: Completed")
    end
  end
end
