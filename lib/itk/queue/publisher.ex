require Logger

defmodule ITKQueue.Publisher do
  @moduledoc """
  Provides methods for publishing messages.
  """

  alias ITKQueue.{Fallback, Headers, PublisherPool}

  @log_time_threshold 10_000

  @doc """
  Publishes one or multiple messages to the given routing key.
  """
  @spec publish(routing_key :: String.t(), messages :: map | list(map), options :: Keyword.t()) ::
          :ok
  def publish(routing_key, messages, options) when is_bitstring(routing_key) do
    publish(routing_key, messages, [], options)
  end

  @spec publish(
          routing_key :: String.t(),
          messages :: map | list(map),
          headers :: Headers.t(),
          options :: Keyword.t()
        ) :: :ok
  def publish(routing_key, messages, headers, options)
      when is_bitstring(routing_key) do
    if testing?() do
      fake_publish(routing_key, messages)
    else
      try do
        {wait_time, {ref, channel}} = :timer.tc(fn -> PublisherPool.checkout() end)

        try do
          {pub_time, _} =
            :timer.tc(fn ->
              messages
              |> List.wrap()
              |> Enum.each(fn message ->
                basic_pub(channel, routing_key, message, headers, options)
              end)
            end)

          maybe_log_publish(pub_time, wait_time, routing_key)
        after
          PublisherPool.checkin(ref)
        end
      catch
        :exit, _reason ->
          Logger.info(
            "Failed to publish - sending to fallback.",
            routing_key: routing_key
          )

          Fallback.publish(routing_key, messages)
      end

      :ok
    end
  end

  @spec basic_pub(
          AMQP.Channel.t(),
          routing_key :: String.t(),
          messages :: map,
          headers :: Headers.t(),
          options :: Keyword.t()
        ) :: :ok
  defp basic_pub(
         channel = %AMQP.Channel{},
         routing_key,
         message,
         headers,
         options
       ) do
    publish_options =
      options
      |> Keyword.delete(:source)
      |> Keyword.delete(:stacktrace)
      |> Keyword.put(:headers, headers)
      |> Keyword.put_new(:persistent, true)

    exchange = Keyword.get(options, :exchange, default_exchange())
    message = set_message_metadata(message, routing_key, options)
    payload = Jason.encode!(message)

    case AMQP.Basic.publish(
           channel,
           exchange,
           routing_key,
           payload,
           publish_options
         ) do
      :ok ->
        Logger.info("Publishing #{payload}",
          routing_key: routing_key,
          message_id: message_uuid(message)
        )

      _ ->
        Logger.info(
          "Failed to publish #{payload} - sending to fallback.",
          routing_key: routing_key
        )

        Fallback.publish(routing_key, message)
    end
  end

  defp set_message_metadata(message = %{"metadata" => metadata}, routing_key, options) do
    metadata =
      metadata
      |> Map.put("app", app_name(message))
      |> Map.put("routing_key", routing_key)
      |> Map.put("uuid", message_uuid(message))
      |> Map.put("source", message_source(message, options))
      |> Map.put("hostname", hostname(message))

    Map.put(message, "metadata", metadata)
  end

  defp set_message_metadata(message, routing_key, options) do
    metadata =
      message
      |> Map.get(:metadata, %{})
      |> Map.put(:app, app_name(message))
      |> Map.put(:routing_key, routing_key)
      |> Map.put(:uuid, message_uuid(message))
      |> Map.put(:source, message_source(message, options))
      |> Map.put(:hostname, hostname(message))

    Map.put(message, :metadata, metadata)
  end

  defp app_name(%{"metadata" => %{"app" => app}}), do: app

  defp app_name(%{metadata: %{app: app}}), do: app

  defp app_name(_message) do
    Mix.Project.get().project[:app]
  end

  defp message_uuid(%{"metadata" => %{"uuid" => uuid}}), do: uuid

  defp message_uuid(%{metadata: %{uuid: uuid}}), do: uuid

  defp message_uuid(_), do: UUID.uuid4()

  defp message_source(%{"metadata" => %{"source" => source}}, _options), do: source

  defp message_source(%{metadata: %{source: source}}, _options), do: source

  defp message_source(_message, options) do
    case Keyword.get(options, :source) do
      nil ->
        options |> Keyword.get(:stacktrace) |> message_source_from_stacktrace()

      source ->
        source
    end
  end

  defp message_source_from_stacktrace(nil) do
    self() |> Process.info(:current_stacktrace) |> elem(1) |> message_source_from_stacktrace()
  end

  defp message_source_from_stacktrace(stacktrace) do
    stacktrace
    |> Exception.format_stacktrace()
    |> String.split("\n")
    |> Enum.reject(fn m ->
      Regex.match?(~r/^\s+\((elixir|stdlib|itk_queue|phoenix|plug|cowboy)\)/, m)
    end)
    |> List.first()
    |> String.trim()
  end

  defp hostname(%{"metadata" => %{"hostname" => hostname}}), do: hostname

  defp hostname(%{metadata: %{hostname: hostname}}), do: hostname

  defp hostname(_message) do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  @spec default_exchange() :: String.t()
  defp default_exchange do
    Application.get_env(:itk_queue, :amqp_exchange)
  end

  defp format_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string(), "ms"]
  defp format_diff(diff), do: [Integer.to_string(diff), "µs"]

  defp maybe_log_publish(pub_time, wait_time, routing_key) do
    if pub_time > @log_time_threshold do
      Logger.info(
        "Published `#{routing_key}` in #{format_diff(pub_time)} (waited #{format_diff(wait_time)})",
        routing_key: routing_key
      )
    end
  end

  @spec testing?() :: boolean
  defp testing? do
    Application.get_env(:itk_queue, :env) == :test &&
      !Application.get_env(:itk_queue, :running_library_tests, false)
  end

  defp fake_publish(routing_key, messages) do
    messages
    |> List.wrap()
    |> Enum.each(fn message ->
      send(self(), [:publish, routing_key, message])
    end)

    :ok
  end
end
