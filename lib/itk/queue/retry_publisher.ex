defmodule ITKQueue.RetryPublisher do
  @moduledoc """
  Worker to republish nacked message.
  """

  defstruct chan: nil,
            status: :disconnected,
            pending: %{},
            last_seq: 0

  use GenServer
  require Logger

  alias ITKQueue.{Channel, ConnectionPool, Fallback}

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

  def start_link(opts, name) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(_) do
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{}}
  end

  def handle_info(:connect, state = %{status: :disconnected}) do
    ConnectionPool.with_connection(fn conn ->
      chan = Channel.open_for_publish(conn, self())
      Process.send_after(self(), :confirm, 100)
      Process.monitor(chan.pid)
      Logger.info("RetryPublisher channel #{inspect(self())} opened on conn #{inspect(conn)}")
      {:noreply, %{state | chan: chan, status: :connected}}
    end)
  catch
    _, e ->
      Logger.warn("RetryPublisher connect error: #{inspect(e)}")
      Process.send_after(self(), :connect, @reconnect_interval)
      {:noreply, state}
  end

  def handle_info(:confirm, state = %{status: :connected, chan: chan}) do
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

  def handle_info({:retry, retries}, state = %{status: :connected}) do
    new_state = retry_publish(retries, state)
    {:noreply, new_state}
  end

  def handle_info({:retry, retries}, state) do
    Process.send_after(self(), {:retry, retries}, @reconnect_interval)
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

  @doc """
  For PubChannel to call and retry publishing messages.
  """
  def handle_call({:retry, retries}, _, state) do
    send(self(), {:retry, retries})
    {:reply, :ok, state}
  end

  def handle_call({:replace_state, state}, _, _) do
    {:reply, :ok, state}
  end

  def terminate(reason, %{chan: chan, status: :connected}) do
    Logger.info("#{inspect(self())} Closing channel, because #{inspect(reason)}")
    Channel.close(chan)

    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp retry_publish([], state), do: state

  defp retry_publish(retries, state = %{chan: chan, pending: pending}) do
    Logger.info("Retry publish #{length(retries)} messages")

    {seq, merge} =
      Enum.reduce(retries, {0, %{}}, fn t, {_, acc} ->
        case do_publish(chan, t) do
          {:ok, seq} -> {seq, Map.put(acc, seq, t)}
          {:error, seq} -> {seq, acc}
        end
      end)

    pending = Map.merge(pending, merge)

    %{state | last_seq: seq, pending: pending}
  end

  @spec do_publish(channel :: AMQP.Channel.t(), tuple :: tuple()) :: {atom(), non_neg_integer()}
  defp do_publish(channel, {exchange, routing_key, message_id, payload, opts}) do
    Logger.info("Republishing #{payload}",
      routing_key: routing_key,
      message_id: message_id
    )

    seq = AMQP.Confirm.next_publish_seqno(channel)

    publish_result =
      AMQP.Basic.publish(
        channel,
        exchange,
        routing_key,
        payload,
        opts
      )

    case publish_result do
      :ok ->
        {:ok, seq}

      {:error, _} ->
        Logger.info(
          "Failed to publish - sending to fallback.",
          routing_key: routing_key
        )

        Fallback.publish(routing_key, Jason.decode!(payload))
        {:error, seq}
    end
  end
end
