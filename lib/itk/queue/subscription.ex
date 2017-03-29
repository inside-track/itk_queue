defmodule ITK.Queue.Subscription do
  @moduledoc false

  defmodule DefaultHandler do
    def handle(_), do: nil
  end

  defstruct queue_name: "", routing_key: "", handler: &DefaultHandler.handle/1
end
