defmodule ITKQueue.RetryPublisher.Test do
  use ExUnit.Case
  alias ITKQueue.RetryPublisher

  test "handles retry message" do
    {:ok, pid} = RetryPublisher.start_link([])

    s = :sys.get_state(pid)
    assert s.last_seq == 0

    this = self()
    ITKQueue.subscribe("retry-queue-test", "retry.queue", fn _message -> send(this, :ok) end)

    GenServer.call(pid, {:retry, [{"test", "retry.queue", "foo", "{}", []}]})
    s = :sys.get_state(pid)
    assert s.pending != %{}
    assert_receive :ok, 5_000

    send(pid, {:basic_ack, s.last_seq, false})
    s2 = :sys.get_state(pid)
    assert s2.pending == %{}

    # simulate nack and republish
    GenServer.call(pid, {:replace_state, s})
    send(pid, {:basic_nack, s.last_seq, false})
    s = :sys.get_state(pid)
    assert s.pending == %{}
    assert_receive :ok, 5_000
  end
end
