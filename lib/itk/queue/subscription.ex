defmodule ITKQueue.Subscription do
  @moduledoc false

  @type t :: %__MODULE__{queue_name: String.t(), routing_key: String.t(), handler: fun}

  defmodule DefaultHandler do
    @moduledoc false
    def handle(_, _), do: nil
  end

  defstruct queue_name: "", routing_key: "", handler: &DefaultHandler.handle/2
end
