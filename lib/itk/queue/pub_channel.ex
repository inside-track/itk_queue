defmodule ITKQueue.PubChannel do
  @moduledoc """
  Worker for pooled publishers to AMQP message queue.
  """

  use GenServer
  require Logger

  alias ITKQueue.{Channel, ConnectionPool}

  @reconnect_interval 1000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %{status: :disconnected, chan: nil}}
  end

  def handle_call(:channel, _from, status = %{chan: chan}) do
    {:reply, chan, status}
  end

  def handle_info(:connect, state = %{status: :disconnected}) do
    ConnectionPool.with_connection(fn conn ->
      chan = Channel.open(conn)
      Process.monitor(chan.pid)
      Logger.info("Publisher channel #{inspect(self())} opened on conn #{inspect(conn)}")
      {:noreply, %{state | chan: chan, status: :connected}}
    end)
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Channel closed, because #{inspect(reason)}")
    Process.send_after(self(), :connect, @reconnect_interval)
    {:noreply, %{state | status: :disconnected}}
  end

  def terminate(reason, %{chan: chan, status: :connected}) do
    Logger.info("#{inspect(self())} Closing channel, because #{inspect(reason)}")
    Channel.close(chan)

    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok
end
