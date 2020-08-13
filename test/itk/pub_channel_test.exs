defmodule ITKQueue.PubChannel.Test do
  use ExUnit.Case
  alias ITKQueue.PubChannel

  test "handles published message with publish result" do
    {:ok, pid} = ITKQueue.PubChannel.start_link([])

    s = :sys.get_state(pid)
    assert s.last_seq == 0

    GenServer.call(pid, {:publish, {1, :ok, {"test", "my.queue", "foo", "{}", []}}})
    s = :sys.get_state(pid)
    assert s.pending != %{}

    send(pid, {:basic_ack, 1, false})
    s = :sys.get_state(pid)
    assert s.pending == %{}

    GenServer.call(
      pid,
      {:publish, {2, {:error, :closed}, {"test", "my.queue", "foo", "{}", []}}}
    )

    s = :sys.get_state(pid)
    assert s.pending == %{}
  end
end
