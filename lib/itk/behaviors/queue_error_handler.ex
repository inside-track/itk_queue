defmodule ITKQueue.Behaviors.QueueErrorHandler do
  @moduledoc false
  @callback handle(String.t(), String.t(), String.t(), Exception.t()) :: no_return
end
