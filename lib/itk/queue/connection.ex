require Logger

defmodule ITKQueue.Connection do
  @moduledoc """
  Manages a connection to AMQP.
  """

  defstruct params: [],
            connection: nil,
            ref: nil,
            reconnect: false

  use GenServer

  @type t :: %__MODULE__{
          params: Keyword.t(),
          connection: %AMQP.Connection{pid: pid()},
          ref: reference(),
          reconnect: boolean()
        }

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
    state = connect(params)
    {:ok, %__MODULE__{state | reconnect: opts[:reconnect]}}
  end

  @doc false
  def handle_call(:connection, _from, state) do
    {:reply, state.connection, state}
  end

  @doc """
  Handles DOWN message from monitored AMQP connection pid.
  """
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.info("AMQP connection went down: #{inspect(reason)}")

    if state.reconnect do
      Process.send_after(self(), :reconnect, 1000)
      {:noreply, state}
    else
      {:stop, :connection_lost, state}
    end
  end

  @doc false
  def handle_info(:reconnect, %{params: params, reconnect: reconnect}) do
    state = connect(params)
    {:noreply, %__MODULE__{state | reconnect: reconnect}}
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

  # This will block the GenServer until connection is opened successfully.
  defp connect(params) do
    AMQP.Connection.open(params)
    |> handle_connection_result(params)
  end

  defp handle_connection_result({:ok, connection}, params) do
    ref = Process.monitor(connection.pid)
    %__MODULE__{params: params, connection: connection, ref: ref}
  end

  defp handle_connection_result({:error, _}, params) do
    Logger.info("AMQP connection failed, retrying")
    Process.sleep(1000)
    connect(params)
  end

  @doc """
  Handles termination of this GenServer.
  """
  def terminate(reason, _state) do
    Logger.info("Terminating AMQP connection manager: #{inspect(reason)}")
    :reason
  end
end
