defmodule ITKQueue.Publisher do
  @moduledoc false

  use GenServer

  alias ITKQueue.{Connection, Channel, Fallback, SyslogLogger}

  @name :itk_queue_publisher
  @exchange Application.get_env(:itk_queue, :amqp_exchange)

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: @name])
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_cast({:publish, routing_key, message, headers, stacktrace}, state) do
    connection = Connection.connect()
    channel = Channel.open(connection)
    message = set_message_metadata(message, routing_key, stacktrace)
    {:ok, payload} = Poison.encode(message)

    case AMQP.Basic.publish(channel, @exchange, routing_key, payload, persistent: true, headers: headers) do
      :ok -> SyslogLogger.info(routing_key, "Publishing #{payload}")
      _ -> Fallback.publish(routing_key, message)
    end

    Channel.close(channel)
    {:noreply, state}
  end

  @doc """
  Publishes a message to the given routing key.
  """
  @spec publish(routing_key :: String.t, message :: Map.t, headers :: Keyword.t) :: no_return
  def publish(routing_key, message, headers \\ []) do
    stacktrace = Process.info(self(), :current_stacktrace)
    publish(routing_key, message, headers, elem(stacktrace, 1))
  end

  def publish(routing_key, message, headers, stacktrace) do
    GenServer.cast(@name, {:publish, routing_key, message, headers, stacktrace})
  end

  defp set_message_metadata(message = %{"metadata" => metadata}, routing_key, stacktrace) do
    metadata =
      metadata
      |> Map.put("app", app_name(message))
      |> Map.put("routing_key", routing_key)
      |> Map.put("uuid", message_uuid(message))
      |> Map.put("source", message_source(message, stacktrace))
      |> Map.put("hostname", hostname(message))
    Map.put(message, "metadata", metadata)
  end

  defp set_message_metadata(message, routing_key, stacktrace) do
    metadata =
      message
      |> Map.get(:metadata, %{})
      |> Map.put(:app, app_name(message))
      |> Map.put(:routing_key, routing_key)
      |> Map.put(:uuid, message_uuid(message))
      |> Map.put(:source, message_source(message, stacktrace))
      |> Map.put(:hostname, hostname(message))
    Map.put(message, :metadata, metadata)
  end

  defp app_name(%{"metadata" => %{"app" => app}}), do: app

  defp app_name(%{metadata: %{app: app}}), do: app

  defp app_name(_message) do
    Mix.Project.get.project[:app]
  end

  defp message_uuid(%{"metadata" => %{"uuid" => uuid}}), do: uuid

  defp message_uuid(%{metadata: %{uuid: uuid}}), do: uuid

  defp message_uuid(_), do: UUID.uuid4()

  defp message_source(%{"metadata" => %{"source" => source}}, _stacktrace), do: source

  defp message_source(%{metadata: %{source: source}}, _stacktrace), do: source

  defp message_source(_message, stacktrace) do
    stacktrace
    |> Exception.format_stacktrace
    |> String.split("\n")
    |> Enum.reject(fn(m) -> Regex.match?(~r/^\s+\((elixir|stdlib|itk_queue|phoenix|plug|cowboy)\)/, m) end)
    |> List.first
    |> String.trim
  end

  defp hostname(%{"metadata" => %{"hostname" => hostname}}), do: hostname

  defp hostname(%{metadata: %{hostname: hostname}}), do: hostname

  defp hostname(_message) do
    {:ok, hostname} = :inet.gethostname
    hostname
  end
end
