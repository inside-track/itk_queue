defmodule ITKQueue.PubChannel do
  @moduledoc """
  Worker for pooled publishers to AMQP message queue.
  """

  defstruct chan: nil,
            status: :disconnected,
            pending: %{},
            last_seq: 0

  use GenServer
  require Logger

  alias ITKQueue.{Channel, ConnectionPool}

  @reconnect_interval 1000

  @type t :: %__MODULE__{
          chan: AMQP.Channel.t(),
          status: atom(),
          pending: map(),
          last_seq: integer()
        }

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{}}
  end

  def handle_call(:channel, _from, status = %{chan: chan}) do
    {:reply, chan, status}
  end

  def handle_call(
        {:publish, {seq, publish_result, published_message}},
        _,
        state = %{pending: pending}
      ) do
    case publish_result do
      {:error, _} ->
        retry_publish([published_message])
        {:reply, {:ok, seq}, state}

      _ ->
        pending = Map.put(pending, seq, published_message)
        {:reply, {:ok, seq}, %{state | pending: pending}}
    end
  end

  def handle_info(:connect, state = %{status: :disconnected}) do
    ConnectionPool.with_connection(fn conn ->
      chan = Channel.open_for_publish(conn, self())
      Process.send_after(self(), :confirm, 100)
      Process.monitor(chan.pid)
      Logger.info("Publisher channel #{inspect(self())} opened on conn #{inspect(conn)}")
      {:noreply, %{state | chan: chan, status: :connected}}
    end)
  catch
    _, _ ->
      Process.send_after(self(), :connect, @reconnect_interval)
      {:noreply, state}
  end

  def handle_info(:confirm, state = %{status: :connected, chan: chan, pending: pending}) do
    len = pending |> Map.keys() |> length

    if len > 1000 do
      Logger.info("Publisher waiting to confirm #{len} publishes")
    end

    pid = self()
    spawn(fn -> Channel.wait_for_confirms(pid, chan) end)
    {:noreply, state}
  end

  def handle_info({:basic_ack, seqno, _}, state = %{last_seq: last_seq, pending: pending}) do
    keys = Enum.to_list(last_seq..seqno)
    pending = Map.drop(pending, keys)
    {:noreply, %{state | pending: pending, last_seq: seqno}}
  end

  def handle_info({:basic_nack, seqno, _}, state = %{last_seq: last_seq, pending: pending}) do
    keys = Enum.to_list(last_seq..seqno)
    retries = Map.take(pending, keys) |> Map.values()
    Logger.warn("Publisher nack for #{length(keys)} messages")
    # wait for some time before republishing
    Process.send_after(self(), {:retry, retries}, 100)
    pending = Map.drop(pending, keys)
    {:noreply, %{state | pending: pending, last_seq: seqno}}
  end

  def handle_info({:retry, retries}, state) do
    retry_publish(retries)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Channel closed, because #{inspect(reason)}")
    Process.send_after(self(), :connect, @reconnect_interval)
    {:noreply, %{state | status: :disconnected, pending: %{}, last_seq: 0}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def terminate(reason, %{chan: chan, status: :connected}) do
    Logger.info("#{inspect(self())} Closing channel, because #{inspect(reason)}")
    Channel.close(chan)

    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp retry_publish(retries) do
    GenServer.call(ITKQueue.RetryPublisher, {:retry, retries})
  end
end
