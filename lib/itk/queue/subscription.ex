defmodule ITKQueue.Subscription do
  @moduledoc false

  defmodule DefaultHandler do
    def handle(_, _), do: nil
  end

  defstruct queue_name: "", routing_key: "", handler: &DefaultHandler.handle/2
end
