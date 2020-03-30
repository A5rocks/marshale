defmodule Marshale.ModelMagic do
  @moduledoc ~S"""
  A collection of helper functions for `Marshale.ModelMagic.defmodel/1`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc ~S"""
  Creates a model in the current module.

  This does the following:

    * `typedoc`s accordingly
    * `type`s accordingly
    * creates a `__from_map__/1` which converts to the types you specify
      * this only `Marshale.ModelUtil.convert/2`s to types where
      `Marshale.ModelMagic.is_marshale_module?/1` returns `true`.
    * creates a struct in the current module with the given fields

  """
  @doc since: "0.1.0"
  defmacro defmodel(do_block)

  defmacro defmodel(do: {:__block__, [], lines}) do
    # turn the lines into something more digestable (yes, we're working with the AST here.)
    # this isn't the best approach as the AST is subject to change more than likely...
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
    # we do this by creating a bunch of pipes in the
    # AST, letting us end with something like the following:
    # please note that the pipes will be `Macro.expand_once`-ed
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

  @doc ~S"""
  Turns AST to a SimpleAST™️ representation.

  This helps out with processing it, as it turns the AST which has tons of
  encapsulation into 2 possible different flat lines. They are:

    * `{line_number, :set, variable_name, type}`
    * `{line_number, :document, documentation}`

  Just do `quote do: a = :b` and look at the mess that is for processing
  easily. That's exactly why this method exists.

  ## Examples

      iex> Marshale.ModelMagic.manipulate_line(
      ...>   {:=, [line: 1], [
      ...>     {:foo, [line: 1], nil},
      ...>     {:__aliases__, [line: 1], [:bar]}
      ...>   ]}
      ...> )
      {1, :set, :foo, :"Elixir.bar"}

      iex> Marshale.ModelMagic.manipulate_line(
      ...>   {:@, [line: 1], [{:typedoc, [line: 1], ["Aloha!"]}]}
      ...> )
      {1, :document, "Aloha!"}
  """
  @doc since: "0.1.0"
  def manipulate_line(ast)

  def manipulate_line(
         {:=, [line: line_number],
          [{variable, [line: _], nil}, {:__aliases__, [line: _], types}]}
       ) when is_list(types) do
    {line_number, :set, variable, namespace_types(types)}
  end

  def manipulate_line(
         {:=, [line: line_number],
          [{variable, [line: _], nil}, [{:__aliases__, [line: _], types}]]}
       ) when is_list(types) do
    {line_number, :set, variable, [namespace_types(types)]}
  end

  def manipulate_line({:@, [line: line_number], [{:typedoc, [line: _], [documentation]}]}) do
    {line_number, :document, handle_sigil_s(documentation)}
  end

  # allow for `is` instead of `=`

  def manipulate_line(
         {variable, [line: line_number], [{:is, [line: _], [{:__aliases__, [line: _], types}]}]}
       ) do
    {line_number, :set, variable, namespace_types(types)}
  end

  def manipulate_line(
         {variable, [line: line_number],
          [{:is, [line: _], [[{:__aliases__, [line: _], types}]]}]}
       ) do
    {line_number, :set, variable, [namespace_types(types)]}
  end


  @doc ~S"""
  Namespaces an atom.

  This both prepends `:Elixir.` to it, and also combines multiple names to
  allow things such as `:"Marshale.ModelMagic"` instead of just `:ModelMagic` and
  the like.

  ## Examples

      iex> function_exported?(:String, :downcase, 1)
      false
      iex> function_exported?(Marshale.ModelMagic.namespace_types(:String), :downcase, 1)
      true

      iex> Marshale.ModelMagic.namespace_types([:Marshale, :ModelMagic])
      Marshale.ModelMagic

  """
  @doc since: "0.1.0"
  def namespace_types(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> (fn string -> "Elixir." <> string end).()
    |> String.to_atom()
  end

  def namespace_types(types) when is_list(types) do
    namespace_types(
      types
      |> Enum.map(&Atom.to_string(&1))
      |> Enum.join(".")
      |> String.to_atom()
    )
  end

  @doc ~S"""
  Returns a list which when `Enum.flat_map/2`-ed is the AST lines for documenting a variable.

  Takes in the SimpleAST™️ form of a variable and the whole SimpleAST™️ region,
  and outputs said AST lines for documenting the variable.

  ## Examples

      iex> Macro.to_string(Marshale.ModelMagic.document_type(
      ...>   {3, :set, :foo, :bar},
      ...>   [{2, :document, "baz"},
      ...>    {3, :set, :foo, :bar}]
      ...> ))
      "[@typedoc(\"baz\"), @type(foo :: bar)]"

  """
  @doc since: "0.1.0"
  def document_type(simple_ast_variable, simple_ast)

  def document_type({line_number, :set, variable, [type]}, simple_ast) do
    [
      document_line(line_number, simple_ast),
      {:@, [],
       [
         {:type, [],
          [{:"::", [], [{variable, [], nil}, [{:__aliases__, [alias: false], [type]}]]}]}
       ]}
    ]
  end

  def document_type({line_number, :set, variable, type}, simple_ast) do
    [
      document_line(line_number, simple_ast),
      {:@, [],
       [
         {:type, [], [{:"::", [], [{variable, [], nil}, {:__aliases__, [alias: false], [type]}]}]}
       ]}
    ]
  end

  @doc ~S"""
  Returns AST for a `@typedoc` statement from a line number, and the SimpleAST™️.

  This function gets the documentation for a variable using
  `Marshale.ModelMagic.get_typedoc/2`, then creates a `@typedoc [documentation]`,
  which it then returns the AST for (or `nil` if the variable has no
  documentation associated with it).

  ## Examples

      iex> Macro.to_string(Marshale.ModelMagic.document_line(
      ...>   3,
      ...>   [{2, :document, "Onwards and upwards"}]
      ...> ))
      "@typedoc(\"Onwards and upwards\")"

  """
  @doc since: "0.1.0"
  def document_line(line_number, simple_ast) do
    documentation = get_typedoc(line_number, simple_ast)

    if documentation != nil do
      {:@, [], [{:typedoc, [], [documentation]}]}
    else
      nil
    end
  end

  @doc ~S"""
  Takes in a `~s`'s or `~S`'s AST and returns the inner string.

  This may prevent interpolation from `~s` (I have not checked), but is a good
  compromise between simplicity and feature-complete-ness. If the passed in
  argument is not `~s`'s or `~S`'s AST, then this function just returns said
  argument.

  ## Examples

      iex> Marshale.ModelMagic.handle_sigil_s(
      ...>   {:sigil_S, [line: 2], [{:<<>>, [line: 2], ["Aloha!"]}, []]}
      ...> )
      "Aloha!"

      iex> Marshale.ModelMagic.handle_sigil_s("Aloha!")
      "Aloha!"

  """
  @doc since: "0.1.0"
  def handle_sigil_s(content)

  def handle_sigil_s({:sigil_S, [line: _], [{:<<>>, [line: _], [content]}, []]}) do
    content
  end

  def handle_sigil_s({:sigil_s, [line: _], [{:<<>>, [line: _], [content]}, []]}) do
    content
  end

  def handle_sigil_s(content) do
    content
  end

  @doc ~S"""
  Gets the typedoc for a variable (or `nil` is there is none).

  Takes in the line number of the variable, and the SimpleAST™️ of the block.
  It returns a string which is what the variable is typedoc-ed as, or `nil`.

  ## Examples

      iex> Marshale.ModelMagic.get_typedoc(3, [
      ...>    {1, :document, "Hello, world!"},
      ...>    {3, :set, :foo, :Bar}
      ...> ])
      "Hello, world!"

      iex> Marshale.ModelMagic.get_typedoc(3, [{3, :set, :foo, :Bar}])
      nil

  """
  @doc since: "0.1.0"
  def get_typedoc(line_number, simple_ast) do
    # get all the previous lines
    previous_region = Enum.filter(simple_ast, fn line -> elem(line, 0) < line_number end)

    # the only line to concern us is the last line in this region
    case tail(previous_region) do
      {_, :document, docs} -> docs
      _ -> nil
    end
  end

  @doc ~S"""
  Returns the last element of a list.

  The code is basically `Marshale.ModelMagic.pop_tail/1`, but slightly
  modified. It's only here due to the fact Elixir includes no such utility
  to do this, and because both `Marshale.ModelMagic.get_typedoc/2` and
  `Marshale.ModelMagic.pipe/1` need it.

  ## Examples

      iex> Marshale.ModelMagic.tail([])
      {:err, "Can't take the tail of an empty list"}

      iex> Marshale.ModelMagic.tail([1, 2, 7, 3])
      3

  """
  @doc since: "0.1.0"
  def tail(list)

  def tail([]) do
    {:err, "Can't take the tail of an empty list"}
  end

  def tail(list) when is_list(list) do
    list |> Enum.reverse() |> hd()
  end

  @doc ~S"""
  Removes the last element from a list.

  This function is basically taken from StackOverflow, but is here because
  `Marshale.ModelMagic.pipe/1` requires it as a helper function.

  ## Examples

      iex> Marshale.ModelMagic.pop_tail([])
      {:err, "Can't pop the tail of an empty list"}

      iex> Marshale.ModelMagic.pop_tail([1, 2, 7, 3])
      [1, 2, 7]

  """
  @doc since: "0.1.0"
  def pop_tail(list)

  def pop_tail([]) do
    {:err, "Can't pop the tail of an empty list"}
  end

  def pop_tail(list) when is_list(list) do
    # taken from StackOverflow
    list |> Enum.reverse() |> tl() |> Enum.reverse()
  end

  @doc ~S"""
  Constructs a pipeline from a list.

  In more specific, it should be able to a list of anything, but in practice,
  that "anything" is normally atoms. It returns the AST for a pipeline, too.

  ## Examples

      iex> Macro.to_string(Marshale.ModelMagic.pipe([100, :foo, :bar]))
      "100 |> :foo |> :bar"

      iex> piped = Marshale.ModelMagic.pipe([100, (quote do: div(2)), (quote do: div(5))])
      {:|>, [], [{:|>, [], [100, {:div, [], [2]}]}, {:div, [], [5]}]}
      iex> Macro.to_string(Macro.expand_once(piped, __ENV__))
      "div(div(100, 2), 5)"

  """
  @doc since: "0.1.0"
  def pipe(list)

  def pipe([item]) do
    item
  end

  def pipe(list) when is_list(list) do
    {:|>, [], [pipe(pop_tail(list)), tail(list)]}
  end

  @doc ~S"""
  Returns AST for a `Marshale.ModelUtil.convert/2` call based on a passed in type.

  To be more specific, this returns the AST for the anonymous function call,
  which in non-AST terms would look like this:

  ```Elixir
  &Marshale.ModelUtil.convert(&1, <type>)
  ```

  ## Examples

      iex> Macro.to_string(Marshale.ModelMagic.convert_function(String))
      "&(Marshale.ModelUtil.convert(&1, String))"

  """
  @doc since: "0.1.0"
  def convert_function(type) do
    {:&, [],
     [
       {{:., [], [{:__aliases__, [alias: false], [:Marshale, :ModelUtil]}, :convert]}, [],
        [{:&, [], [1]}, type]}
     ]}
  end

  @doc ~S"""
  Returns AST for a `Map.update/4` call based on field name and function.

  The input should be a tuple of field name and function. To be specific, the
  output and the input function are both AST. I highly recommend using
  `Marshale.ModelMagic.convert_function/1` to generate the input function AST.

  ## Examples

      iex> Macro.to_string(Marshale.ModelMagic.map_update_function({
      ...>   :foo,
      ...>   Marshale.ModelMagic.convert_function(String)
      ...> }))
      "Map.update(:foo, nil, &(Marshale.ModelUtil.convert(&1, String)))"

  """
  @doc since: "0.1.0"
  def map_update_function(field_and_function_tuple)

  def map_update_function({field, function}) do
    {{:., [], [{:__aliases__, [alias: false], [:Map]}, :update]}, [], [field, nil, function]}
  end

  @doc ~S"""
  Detects whether a passed in module has `__from_map__/1`.

  This is the only test of whether of something is a `Marshale` module,
  allowing for basic modules to be assembled by hand, allowing for type
  conversions not of the map to struct type.

  ## Examples

      iex> defmodule Snowflake do
      ...>   def __from_map__(string) when is_binary(string) do
      ...>     String.to_integer(string)
      ...>   end
      ...>
      ...>   def __from_map__(default) do
      ...>     default
      ...>   end
      ...> end
      iex> Marshale.ModelMagic.is_marshale_module?(Snowflake)
      true

  """
  @doc since: "0.1.0"
  def is_marshale_module?(module)

  def is_marshale_module?([module]), do: is_marshale_module?(module)

  def is_marshale_module?(module) when is_atom(module) do
    function_exported?(module, :__from_map__, 1)
  end

  def is_marshale_module?(_default), do: false
end
