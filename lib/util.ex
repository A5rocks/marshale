defmodule Marshale.ModelUtil do
  def convert(item, type)
  def convert(nil, _), do: nil

  def convert(items, [type]) when is_list(items) do
    Enum.map(items, fn item -> convert(item, type) end)
  end

  # handle structs made by us / others / atoms
  def convert(items, type) when is_atom(type) do
    if function_exported?(type, :__from_map__, 1) do
      # a bit of a misnomer as it could be a non-map
      type.__from_map__(items)
    else
      items
    end
  end

  # a noop default!
  def convert(item, _) do
    item
  end
end
