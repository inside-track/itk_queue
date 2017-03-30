defmodule ITK.QueueTest do
  use ExUnit.Case

  test "publishing and subscribing with a function hander" do
    pid = self()
    ITK.Queue.subscribe("my-test-queue-1", "test.queue1", fn(_) -> send pid, :ok end)
    ITK.Queue.publish("test.queue1", %{test: "me"})
    assert_receive :ok, 5_000
  end
end
