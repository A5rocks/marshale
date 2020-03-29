# Marshale

**Make making models easier on yourself.**

## Installation

Just do this to your `mix.exs`:
```elixir
def deps do
  [
    {:marshale, git: "git://github.com/A5rocks/marshale.git"},
    ...
  ]
end
```

And now, you can define models in a subset of Elixir, like so:
```elixir
defmodule ExampleInteger do
  @doc false
  def __from_map__(object)

  def __from_map__(string) when is_binary(string) do
    String.to_integer(string)
  end

  def __from_map__(item) do
    item
  end
end

defmodule Foo do
  use Marshale.ModelMagic

  defmodel do
    bar = ExampleInteger

    @typedoc ~S"`baz` is a list of `ExampleInteger`s"
    baz = [ExampleInteger]

    id = Integer
  end
end
```

This allows `typedoc`s to propagate properly and allows for the following:
```elixir
iex> Foo.__from_map__(%{bar: "5", baz: ["1", "2", "7", "3"], id: "42"})
%Foo{bar: 5, baz: [1, 2, 7, 3], id: "42"}
```
