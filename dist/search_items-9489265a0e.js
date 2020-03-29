searchNodes=[{"doc":"","ref":"Marshale.ModelMagic.html","title":"Marshale.ModelMagic","type":"module"},{"doc":"","ref":"Marshale.ModelMagic.html#defmodel/1","title":"Marshale.ModelMagic.defmodel/1","type":"macro"},{"doc":"Construct a pipeline from a list. For example, something like pipe([100, div(2), div(5)]) will turn into this: 100 |&gt; div(2) |&gt; div(5)","ref":"Marshale.ModelMagic.html#pipe/1","title":"Marshale.ModelMagic.pipe/1","type":"function"},{"doc":"","ref":"Marshale.ModelUtil.html","title":"Marshale.ModelUtil","type":"module"},{"doc":"","ref":"Marshale.ModelUtil.html#convert/2","title":"Marshale.ModelUtil.convert/2","type":"function"},{"doc":"Marshale Make making models easier on yourself.","ref":"readme.html","title":"Marshale","type":"extras"},{"doc":"Just do this to your mix.exs: def deps do [ {:marshale, git: &quot;git://github.com/A5rocks/marshale.git&quot;}, ... ] end And now, you can define models in a subset of Elixir, like so: defmodule ExampleInteger do @doc false def __from_map__(object) def __from_map__(string) when is_binary(string) do String.to_integer(string) end def __from_map__(item) do item end end defmodule Foo do use Marshale.ModelMagic defmodel do bar = ExampleInteger @typedoc ~S&quot;`baz` is a list of `ExampleInteger`s&quot; baz = [ExampleInteger] id = Integer end end This allows typedocs to propagate properly and allows for the following: iex&gt; Foo.__from_map__(%{bar: &quot;5&quot;, baz: [&quot;1&quot;, &quot;2&quot;, &quot;7&quot;, &quot;3&quot;], id: &quot;42&quot;}) %Foo{bar: 5, baz: [1, 2, 7, 3], id: &quot;42&quot;}","ref":"readme.html#installation","title":"Marshale - Installation","type":"extras"}]