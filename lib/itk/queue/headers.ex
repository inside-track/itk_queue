defmodule ITKQueue.Headers do
  @moduledoc """
  For interacting with headers from queue messages.
  """

  @type t :: list({String.t(), atom(), any()})

  @doc """
  Gets the value from the headers for the given key.
  """
  @spec get(headers :: list() | map(), key :: String.t()) :: any()
  def get(headers, key, default \\ nil) do
    headers
    |> headers_to_map
    |> Map.get(key, default)
  end

  defp headers_to_map(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, fn {name, _type, value}, acc -> Map.put(acc, name, value) end)
  end

  defp headers_to_map(_), do: %{}
end
