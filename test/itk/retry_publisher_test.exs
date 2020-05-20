defmodule ITKQueue.RetryPublisher.Test do
  use ExUnit.Case
  alias ITKQueue.RetryPublisher

  test "handles retry message" do
    {:ok, pid} = ITKQueue.RetryPublisher.start_link([])

    s = :sys.get_state(pid)
    assert s.last_seq == 0

    GenServer.call(pid, {:retry, [{"test", "my.queue", "foo", "{}", []}]})
    s = :sys.get_state(pid)
    assert s.pending != %{}

    send(pid, {:basic_ack, s.last_seq, false})
    s = :sys.get_state(pid)
    assert s.pending == %{}
  end
end
