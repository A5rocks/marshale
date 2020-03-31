defmodule Marshale.ModelUtil do
  @doc ~S"""
  Converts an item(s) to a type.

  To be specific, this only converts if the type is a "marshale type". This is
  determined by `Marshale.ModelMagic.is_marshale_module?/1`.

  ## Examples

      iex> Marshale.ModelUtil.convert(nil, Integer)
      nil

      iex> Marshale.ModelUtil.convert("7", [Integer])
      "7"

      iex> Marshale.ModelUtil.convert(["7"], [Integer])
      ["7"]
  """
  @doc since: "0.1.0"
  def convert(item, type)
  def convert(nil, _), do: nil

  def convert(items, [type]) when is_list(items) do
    Enum.map(items, fn item -> convert(item, type) end)
  end

  # handle structs made by us / others / atoms
  def convert(items, type) when is_atom(type) do
    if Marshale.ModelMagic.is_marshale_module?(type) do
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
