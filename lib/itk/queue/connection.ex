require Logger

defmodule ITKQueue.Connection do
  @moduledoc """
  Manages a connection to AMQP.
  """

  @doc false
  def start_link(opts, name) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(opts) do
    Logger.info("Establishing AMQP connection")
    Process.flag(:trap_exit, true)
    params = build_params(URI.parse(Keyword.get(opts, :amqp_url)), Keyword.get(opts, :heartbeat))
    connection = connect(params)
    {:ok, connection}
  end

  @doc false
  def handle_call(:connection, _from, connection) do
    {:reply, connection, connection}
  end

  @doc false
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.info("AMQP connection status exit: #{inspect(reason)} #{inspect(state)}")
    {:stop, :normal, state}
  end

  @doc """
    handles stopping GenServer. Will be restarted by Supervisor.
  """
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    Logger.info("AMQP connection status down: #{inspect(reason)}")
    {:stop, {:connection_lost, reason}, nil}
  end

  defp build_params(%{host: host, port: nil, userinfo: nil}, heartbeat) do
    [host: host, heartbeat: heartbeat]
  end

  defp build_params(%{host: host, port: port, userinfo: nil}, heartbeat) do
    [host: host, port: port, heartbeat: heartbeat]
  end

  defp build_params(%{host: host, port: nil, userinfo: userinfo}, heartbeat) do
    [username, password] = String.split(userinfo, ":")
    [host: host, username: username, password: password, heartbeat: heartbeat]
  end

  defp build_params(%{host: host, port: port, userinfo: userinfo}, heartbeat) do
    [username, password] = String.split(userinfo, ":")
    [host: host, port: port, username: username, password: password, heartbeat: heartbeat]
  end

  defp connect(params) do
    AMQP.Connection.open(params)
    |> handle_connection_result(params)
  end

  defp handle_connection_result({:ok, connection}, _params) do
    Process.link(connection.pid)
    connection
  end

  defp handle_connection_result({:error, _}, params) do
    Logger.info("AMQP connection failed, retrying")
    Process.sleep(1000)
    connect(params)
  end

  @doc """
    handles server down
  """
  def terminate(reason, connection) do
    Logger.info("Terminating AMQP connection: #{inspect(reason)}")

    if Process.alive?(connection.pid) do
      Logger.info("Closing AMQP connection")
      AMQP.Connection.close(connection)
    end

    :reason
  end
end
