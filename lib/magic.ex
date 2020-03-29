defmodule Marshale.ModelMagic do
  @doc false
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc since: "0.1.0"
  defmacro defmodel(do: {:__block__, [], lines}) do
    # turn the lines into something more digestable (yes, we're working with the AST here.)
    # this isn't the best approach as the AST is subject to change more than luckily...
    # got any ideas? just raise an issue or whatever... I'm new to Elixir, I might be
    # missing some miraculous thing that would make this a breeze to do.
    simple_ast = Enum.map(lines, fn line -> manipulate_line(line) end)

    # get a list of variables
    variables =
      simple_ast
      |> Enum.filter(fn line -> elem(line, 1) == :set end)
      |> Enum.map(fn line -> elem(line, 2) end)

    # get a bunch of ast lines for typing's sake
    variable_types =
      simple_ast
      |> Enum.filter(&(elem(&1, 1) == :set))
      |> Enum.flat_map(&document_type(&1, simple_ast))
      # remove nil lines.
      |> Enum.filter(&(&1 != nil))

    # now we have to create a `__from_map__` function.
    # we do this by creating a bunch of pipelines in the
    # ast, letting us end with something like the following:
    # please note that the pipes will be `Macro.expand_once`-edm
    # so they will disappear (as they themselves are macros o.o)
    #
    #    def __from_map__(map) when is_map(map) do
    #      intermediate =
    #        map
    #        |> Map.update!(:foo, &Foo.__from_map__(&1))
    #        |> ...
    #
    #      struct(__MODULE__, intermediate)
    #    end
    #

    # get a list of {:field_to_update, function},
    # then turn it into Map.update!(:field_to_update, function)
    with_pipes =
      simple_ast
      |> Enum.filter(&(elem(&1, 1) == :set))
      |> Enum.map(&{elem(&1, 2), elem(&1, 3)})
      # keep only marshale-compatible modules (moderate optimization)
      |> Enum.filter(&is_marshale_module?(elem(&1, 1)))
      |> Enum.map(&{elem(&1, 0), convert_function(elem(&1, 1))})
      # now we have {:field_to_update, function}
      |> Enum.map(&map_update_function(&1))
      # now we finally have Map.update!(:field_to_update, function)
      |> (fn lines -> [{:map, [], nil} | lines] end).()
      |> pipe

    # now we need to place `with_pipes` with `intermediate`,
    # and also add `struct(__MODULE__, intermediate)`...
    # actually, we can reduce this, as this doesn't need to
    # be very understandable ;)
    function_internals = {:struct, [], [{:__MODULE__, [], nil}, with_pipes]}

    function =
      {:def, [],
       [
         {:when, [], [{:__from_map__, [], [{:map, [], nil}]}, {:is_map, [], [{:map, [], nil}]}]},
         [do: function_internals]
       ]}

    quote do
      defstruct unquote(variables)

      unquote(variable_types)

      @doc false
      unquote(function)
    end
  end

  defp manipulate_line(
         {:=, [line: line_number],
          [{variable, [line: _], nil}, {:__aliases__, [line: _], [type]}]}
       ) do
    {line_number, :set, variable, namespace_type(type)}
  end

  defp manipulate_line(
         {:=, [line: line_number],
          [{variable, [line: _], nil}, [{:__aliases__, [line: _], [type]}]]}
       ) do
    {line_number, :set, variable, [namespace_type(type)]}
  end

  defp manipulate_line({:@, [line: line_number], [{:typedoc, [line: _], [documentation]}]}) do
    {line_number, :document, handle_sigil_s(documentation)}
  end

  # allow for `is` instead of `=`

  defp manipulate_line(
         {variable, [line: line_number], [{:is, [line: _], [{:__aliases__, [line: _], [type]}]}]}
       ) do
    {line_number, :set, variable, namespace_type(type)}
  end

  defp manipulate_line(
         {variable, [line: line_number],
          [{:is, [line: _], [[{:__aliases__, [line: _], [type]}]]}]}
       ) do
    {line_number, :set, variable, [namespace_type(type)]}
  end

  defp namespace_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> (fn string -> "Elixir." <> string end).()
    |> String.to_atom()
  end

  defp document_type({line_number, :set, variable, [type]}, simple_ast) do
    [
      document_line(line_number, simple_ast),
      {:@, [],
       [
         {:type, [],
          [{:"::", [], [{variable, [], nil}, [{:__aliases__, [alias: false], [type]}]]}]}
       ]}
    ]
  end

  defp document_type({line_number, :set, variable, type}, simple_ast) do
    [
      document_line(line_number, simple_ast),
      {:@, [],
       [
         {:type, [], [{:"::", [], [{variable, [], nil}, {:__aliases__, [alias: false], [type]}]}]}
       ]}
    ]
  end

  defp document_line(line_number, simple_ast) do
    documentation = get_typedoc(line_number, simple_ast)

    if documentation != nil do
      {:@, [], [{:typedoc, [], [documentation]}]}
    else
      nil
    end
  end

  defp handle_sigil_s({:sigil_S, [line: _], [{:<<>>, [line: _], [content]}, []]}) do
    content
  end

  defp handle_sigil_s({:sigil_s, [line: _], [{:<<>>, [line: _], [content]}, []]}) do
    content
  end

  defp handle_sigil_s(content) do
    content
  end

  defp get_typedoc(line_number, simple_ast) do
    lines = Enum.filter(simple_ast, fn line -> elem(line, 0) < line_number end)

    # the only line to concern us is the last line in this region
    case tail(lines) do
      {_, :document, docs} -> docs
      {:err, _} -> nil
      _ -> nil
    end
  end

  defp tail([]) do
    {:err, "Can't take the tail of an empty list"}
  end

  defp tail(list) when is_list(list) do
    list |> Enum.reverse() |> hd()
  end

  defp pop_tail(list) when is_list(list) do
    # taken from StackOverflow
    list |> Enum.reverse() |> tl() |> Enum.reverse()
  end

  @doc ~S"""
  Construct a pipeline from a list.

  For example, something like
  ```Elixir
  pipe([100, div(2), div(5)])
  ```

  will turn into this:
  ```Elixir
  100 |> div(2) |> div(5)
  ```
  """
  @doc since: "0.1.0"
  def pipe(list)

  def pipe([item]) do
    item
  end

  def pipe(list) when is_list(list) do
    {:|>, [], [pipe(pop_tail(list)), tail(list)]}
  end

  defp convert_function(type) do
    {:&, [],
     [
       {{:., [], [{:__aliases__, [alias: false], [:Marshale, :ModelUtil]}, :convert]}, [],
        [{:&, [], [1]}, type]}
     ]}
  end

  defp map_update_function({field, function}) do
    {{:., [], [{:__aliases__, [alias: false], [:Map]}, :update]}, [], [field, nil, function]}
  end

  defp is_marshale_module?([module]) do
    is_marshale_module?(module)
  end

  defp is_marshale_module?(module) when is_atom(module) do
    function_exported?(module, :__from_map__, 1)
  end

  defp is_marshale_module?(_default) do
    false
  end
end
