require Logger

defmodule ITKQueue.Publisher do
  @moduledoc false

  alias ITKQueue.{Channel, ConnectionPool, Fallback, Headers}

  @doc """
  Publishes a message to the given routing key.

  If a connection is provided it will be used. Otherwise a connection
  will be retrieved from the connection pool, used, and returned.

  If you will be publishing several messages in a short period of time
  checking out a single connection to use for all of your publishing will
  be more efficient.
  """
  @spec publish(routing_key :: String.t(), message :: map, options :: Keyword.t()) :: :ok
  def publish(routing_key, message, options) when is_bitstring(routing_key) do
    publish(routing_key, message, [], options)
  end

  @spec publish(
          AMQP.Connection.t() | AMQP.Channel.t(),
          routing_key :: String.t(),
          message :: map,
          options :: Keyword.t()
        ) :: :ok
  def publish(connection = %AMQP.Connection{}, routing_key, message, options)
      when is_bitstring(routing_key) do
    publish(connection, routing_key, message, [], options)
  end

  def publish(channel = %AMQP.Channel{}, routing_key, message, options)
      when is_bitstring(routing_key) do
    publish(channel, routing_key, message, [], options)
  end

  @spec publish(
          routing_key :: String.t(),
          message :: map,
          headers :: Headers.t(),
          options :: Keyword.t()
        ) :: :ok
  def publish(routing_key, message, headers, options)
      when is_bitstring(routing_key) do
    if testing?() do
      fake_publish(routing_key, message)
    else
      try do
        {wait_diff, {ref, connection}} = time(fn -> ConnectionPool.checkout() end)

        try do
          {diff, _} =
            time(fn ->
              publish_message(connection, routing_key, message, headers, options)
            end)

          Logger.info(
            "Published `#{routing_key}` in #{diff} (waited #{wait_diff})",
            routing_key: routing_key
          )
        after
          ConnectionPool.checkin(ref)
        end
      catch
        :exit, _reason ->
          Logger.info(
            "Failed to publish - sending to fallback.",
            routing_key: routing_key
          )

          Fallback.publish(routing_key, message)
      end

      :ok
    end
  end

  @spec publish(
          AMQP.Connection.t() | AMQP.Channel.t(),
          routing_key :: String.t(),
          message :: map,
          headers :: Headers.t(),
          options :: Keyword.t()
        ) :: :ok
  def publish(connection = %AMQP.Connection{}, routing_key, message, headers, options)
      when is_bitstring(routing_key) do
    if testing?() do
      fake_publish(routing_key, message)
    else
      {diff, _} =
        time(fn ->
          publish_message(connection, routing_key, message, headers, options)
        end)

      Logger.info("Published `#{routing_key}` in #{diff}", routing_key: routing_key)
    end

    :ok
  end

  def publish(channel = %AMQP.Channel{}, routing_key, message, headers, options)
      when is_bitstring(routing_key) do
    if testing?() do
      fake_publish(routing_key, message)
    else
      {diff, _} =
        time(fn ->
          publish_message(channel, routing_key, message, headers, options)
        end)

      Logger.info("Published `#{routing_key}` in #{diff}", routing_key: routing_key)
    end

    :ok
  end

  @spec publish_async(
          routing_key :: String.t(),
          message :: map,
          headers :: Headers.t(),
          stacktrace :: any,
          options :: Keyword.t()
        ) :: pid()
  def publish_async(routing_key, message, headers, stacktrace, options)
      when is_bitstring(routing_key) do
    if testing?() do
      fake_publish(routing_key, message)
      :ok
    else
      spawn(fn ->
        {ref, connection} = ConnectionPool.checkout()
        publish(connection, routing_key, message, options)
        ConnectionPool.checkin(ref)
      end)
    end
  end

  @spec publish_message(
          AMQP.Connection.t() | AMQP.Channel.t(),
          routing_key :: String.t(),
          message :: map,
          headers :: Headers.t(),
          options :: Keyword.t()
        ) :: :ok
  defp publish_message(
         connection = %AMQP.Connection{},
         routing_key,
         message,
         headers,
         options
       ) do
    channel = Channel.open(connection)
    publish_message(channel, routing_key, message, headers, options)
    Channel.close(channel)
  end

  defp publish_message(
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
        Logger.info("Publishing #{payload}", routing_key: routing_key)

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
    hostname
  end

  @spec default_exchange() :: String.t()
  defp default_exchange do
    Application.get_env(:itk_queue, :amqp_exchange)
  end

  defp time(action) do
    {time, result} = :timer.tc(action)
    {format_diff(time), result}
  end

  defp format_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string(), "ms"]
  defp format_diff(diff), do: [Integer.to_string(diff), "µs"]

  @spec testing?() :: boolean
  defp testing? do
    Application.get_env(:itk_queue, :env) == :test &&
      !Application.get_env(:itk_queue, :running_library_tests, false)
  end

  defp fake_publish(routing_key, message) do
    send(self(), [:publish, routing_key, message])
    :ok
  end
end
