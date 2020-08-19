defmodule ITKQueue.PubChannel.Test do
  use ExUnit.Case
  alias ITKQueue.PubChannel

  test "handles published message with publish result" do
    {:ok, pid} = PubChannel.start_link([])

    s = :sys.get_state(pid)
    assert s.last_seq == 0

    msg = {"test", "pub.queue", "foo", "{}", []}

    GenServer.call(pid, {:publish, {1, :ok, msg}})
    s = :sys.get_state(pid)
    assert s.pending != %{}

    send(pid, {:basic_ack, 1, false})
    s = :sys.get_state(pid)
    assert s.pending == %{}

    this = self()
    ITKQueue.subscribe("pub-queue-test", "pub.queue", fn _message -> send(this, :ok) end)

    GenServer.call(pid, {:publish, {2, {:error, :closed}, msg}})
    s = :sys.get_state(pid)
    assert s.pending == %{}

    assert_receive :ok, 5_000
  end
end
