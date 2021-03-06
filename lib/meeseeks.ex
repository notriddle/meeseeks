defmodule Meeseeks do

  alias Meeseeks.{Context, Document, Parser, Result, Select, Selector, TupleTree}

  @moduledoc """
  Meeseeks is an Elixir library for extracting data from HTML.

  ```elixir
  import Meeseeks.CSS

  html = Tesla.get("https://news.ycombinator.com/").body

  for story <- Meeseeks.all(html, css("tr.athing")) do
    title = Meeseeks.one(story, css(".title a"))
    %{title: Meeseeks.text(title),
      url: Meeseeks.attr(title, "href")}
  end
  #=> [%{title: "...", url: "..."}, %{title: "...", url: "..."}, ...]
  ```

  ## Dependencies

  Meeseeks depends on [html5ever](https://github.com/servo/html5ever) via
  [meeseeks_html5ever](https://github.com/mischov/meeseeks_html5ever).

  Because html5ever is a Rust library, you will need to have the Rust
  compiler [installed](https://www.rust-lang.org/en-US/install.html).

  This dependency is necessary because there are no HTML5 spec compliant
  parsers written in Elixir/Erlang.

  ## Getting Started

  ### Parse

  Start by parsing a source (HTML/XML string or `Meeseeks.TupleTree`) into
  a `Meeseeks.Document` so that it can be queried.

  `Meeseeks.parse/1` parses the source as HTML, but `Meeseeks.parse/2`
  accepts a second argument of either `:html` or `:xml` that specifies how
  the source is parsed.

  ```elixir
  document = Meeseeks.parse("<div id=main><p>1</p><p>2</p><p>3</p></div>")
  #=> Meeseeks.Document<{...}>
  ```

  The selection functions accept an unparsed source, parsing it as HTML, but
  parsing is expensive so parse ahead of time when running multiple
  selections on the same document.

  ### Select

  Next, use one of Meeseeks's two main selection functions, `all` or `one`,
  to search for nodes. Both functions accept a queryable (a source, a
  document, or a `Meeseeks.Result`), one or more `Meeseeks.Selector`s, and
  optionally an initial context.

  `all` returns a list of results representing every node matching one of
  the provided selectors, while `one` returns a result representing the
  first node to match a selector (depth-first).

  Use the `css` macro provided by `Meeseeks.CSS` or the `xpath` macro
  provided by `Meeseeks.XPath` to generate selectors.

  ```elixir
  import Meeseeks.CSS
  result = Meeseeks.one(document, css("#main p"))
  #=> #Meeseeks.Result<{ <p>1</p> }>

  import Meeseeks.XPath
  result = Meeseeks.one(document, xpath("//*[@id='main']//p"))
  #=> #Meeseeks.Result<{ <p>1</p> }>
  ```

  ### Extract

  Retrieve information from the result with an extraction function.

  The `Meeseeks.Result` extraction functions are `attr`, `attrs`, `data`,
  `dataset`, `html`, `own_text`, `tag`, `text`, `tree`.

  ```elixir
  Meeseeks.tag(result)
  #=> "p"
  Meeseeks.text(result)
  #=> "1"
  Meeseeks.tree(result)
  #=> {"p", [], ["1"]}
  ```

  ## Custom Selectors

  Meeseeks is designed to have extremely extensible selectors, and creating
  a custom selector is as easy as defining a struct that implements the
  `Meeseeks.Selector` behaviour.

  ```elixir
  defmodule CommentContainsSelector do
    use Meeseeks.Selector

    alias Meeseeks.Document

    defstruct value: ""

    def match(selector, %Document.Comment{} = node, _document, _context) do
      String.contains?(node.content, selector.value)
    end

    def match(_selector, _node, _document, _context) do
      false
    end
  end

  selector = %CommentContainsSelector{value: "TODO"}

  Meeseeks.one("<!-- TODO: Close vuln! -->", selector)
  #=> #Meeseeks.Result<{ <!-- TODO: Close vuln! --> }>
  ```

  To learn more, check the documentation for `Meeseeks.Selector` and
  `Meeseeks.Selector.Combinator`
  """

  @type queryable :: Parser.source | Document.t | Result.t
  @type selectors :: Selector.t | [Selector.t]

  # Parse

  @doc """
  Parses a string or `Meeseeks.TupleTree` into a `Meeseeks.Document`.

  `parse/1` parses as HTML, while `parse/2` accepts a second argument of
  either `:html` or `:xml` that specifies how the source is parsed.

  ## Examples

      iex> Meeseeks.parse("<div id=main><p>Hello, Meeseeks!</p></div>")
      #Meeseeks.Document<{...}>

      iex> Meeseeks.parse({"div", [{"id", "main"}], [{"p", [], ["Hello, Meeseeks!"]}]})
      #Meeseeks.Document<{...}>

      iex> Meeseeks.parse("<book><author>GGK</author></book>", :xml)
      #Meeseeks.Document<{...}>
  """
  @spec parse(Parser.source) :: Document.t | Parser.error
  def parse(source) do
    Parser.parse(source)
  end

  @spec parse(Parser.source, Parser.type) :: Document.t | Parser.error
  def parse(source, parser) do
    Parser.parse(source, parser)
  end

  # Select

  @doc """
  Returns a `Result` for each node in the queryable matching a selector.

  Optionally accepts a `Meeseeks.Context` map.

  Parses the source if it is not a `Meeseeks.Document` or `Meeseeks.Result`.
  If multiple selections are being ran on the same unparsed source, parse
  first to avoid unnecessary computation.

  ## Examples

      iex> import Meeseeks.CSS
      iex> Meeseeks.all("<div id=main><p>1</p><p>2</p><p>3</p></div>", css("#main p")) |> List.first()
      #Meeseeks.Result<{ <p>1</p> }>
  """
  @spec all(queryable, selectors) :: [Result.t] | Parser.error
  def all(queryable, selectors) do
    all(queryable, selectors, %{})
  end

  @spec all(queryable, selectors, Context.t) :: [Result.t] | Parser.error
  def all(%Document{} = queryable, selectors, context) do
    Select.all(queryable, selectors, context)
  end

  def all(%Result{} = queryable, selectors, context) do
    Select.all(queryable, selectors, context)
  end

  def all(source, selectors, context) do
    case parse(source) do
      {:error, reason} -> {:error, reason}
      document -> Select.all(document, selectors, context)
    end
  end

  @doc """
  Returns a `Result` for the first node in the queryable (depth-first)
  matching a selector.

  Optionally accepts a `Meeseeks.Context` map.

  Parses the source if it is not a `Meeseeks.Document` or `Meeseeks.Result`.
  If multiple selections are being ran on the same unparsed source, parse
  first to avoid unnecessary computation.

  ## Examples

      iex> import Meeseeks.CSS
      iex> Meeseeks.one("<div id=main><p>1</p><p>2</p><p>3</p></div>", css("#main p"))
      #Meeseeks.Result<{ <p>1</p> }>
  """
  @spec one(queryable, selectors) :: Result.t | Parser.error
  def one(queryable, selectors) do
    one(queryable, selectors, %{})
  end

  @spec one(queryable, selectors, Context.t) :: Result.t | Parser.error
  def one(%Document{} = queryable, selectors, context) do
    Select.one(queryable, selectors, context)
  end

  def one(%Result{} = queryable, selectors, context) do
    Select.one(queryable, selectors, context)
  end

  def one(source, selectors, context) do
    case parse(source) do
      {:error, reason} -> {:error, reason}
      document -> Select.one(document, selectors, context)
    end
  end

  @doc """
  Returns the accumulated result of walking the queryable, accumulating nodes
  that match a selector. Prefer `all` or `one`- `select` should only be used
  when a custom accumulator is required.

  Requires that a `Meeseeks.Accumulator` has been added to the context via
  `Meeseeks.Context.add_accumulator/2`, and will raise an error if it hasn't.

  Parses the source if it is not a `Meeseeks.Document` or `Meeseeks.Result`.
  If multiple selections are being ran on the same unparsed source, parse
  first to avoid unnecessary computation.

  ## Examples

      iex> import Meeseeks.CSS
      iex> accumulator = %Meeseeks.Accumulator.One{}
      iex> context = Meeseeks.Context.add_accumulator(%{}, accumulator)
      iex> Meeseeks.select("<div id=main><p>1</p><p>2</p><p>3</p></div>", css("#main p"), context)
      #Meeseeks.Result<{ <p>1</p> }>
  """
  @spec select(queryable, selectors, Context.t) :: any | Parser.error
  def select(%Document{} = queryable, selectors, context) do
    Select.select(queryable, selectors, context)
  end

  def select(%Result{} = queryable, selectors, context) do
    Select.select(queryable, selectors, context)
  end

  def select(source, selectors, context) do
    case parse(source) do
      {:error, reason} -> {:error, reason}
      document -> Select.select(document, selectors, context)
    end
  end

  # Extract

  @doc """
  Returns the value for attribute in result, or nil if there isn't one.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div id=example>Hi</div>", css("#example"))
      #Meeseeks.Result<{ <div id="example">Hi</div> }>
      iex> Meeseeks.attr(result, "id")
      "example"
  """
  @spec attr(Result.t, String.t) :: String.t | nil
  def attr(result, attribute) do
    Result.attr(result, attribute)
  end

  @doc """
  Returns the result's attributes list, which may be empty, or nil if
  result represents a node without attributes.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div id=example>Hi</div>", css("#example"))
      #Meeseeks.Result<{ <div id="example">Hi</div> }>
      iex> Meeseeks.attrs(result)
      [{"id", "example"}]
  """
  @spec attrs(Result.t) :: [{String.t, String.t}] | nil
  def attrs(result) do
    Result.attrs(result)
  end

  @doc """
  Returns the combined data of result or result's children, which may be an
  empty string.

  Data is the content of `<script>` or `<style>` tags, or the content of
  comments starting with "[CDATA[" and ending with "]]". The latter behavior
  is to support the extraction of CDATA from HTML, since HTML5 parsers parse
  CDATA as comments.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result1 = Meeseeks.one("<div id=example>Hi</div>", css("#example"))
      #Meeseeks.Result<{ <div id="example">Hi</div> }>
      iex> Meeseeks.data(result1)
      ""
      iex> result2 = Meeseeks.one("<script id=example>Hi</script>", css("#example"))
      #Meeseeks.Result<{ <script id="example">Hi</script> }>
      iex> Meeseeks.data(result2)
      "Hi"
  """
  @spec data(Result.t) :: String.t
  def data(result) do
    Result.data(result)
  end

  @doc """
  Returns a map of result's data attributes, or nil if result represents a
  node without attributes.

  Behaves like HTMLElement.dataset; only valid data attributes are included,
  and attribute names have "data-" removed and are converted to camelCase.

  See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/dataset

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div id=example data-x-val=1 data-y-val=2></div>", css("#example"))
      #Meeseeks.Result<{ <div id="example" data-x-val="1" data-y-val="2"></div> }>
      iex> Meeseeks.dataset(result)
      %{"xVal" => "1", "yVal" => "2"}
  """
  @spec dataset(Result.t) :: %{optional(String.t) => String.t} | nil
  def dataset(result) do
    Result.dataset(result)
  end

  @doc """
  Returns the combined HTML of result and its descendants.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div id=example>Hi</div>", css("#example"))
      #Meeseeks.Result<{ <div id="example">Hi</div> }>
      iex> Meeseeks.html(result)
      "<div id=\\"example\\">Hi</div>"
  """
  @spec html(Result.t) :: String.t
  def html(result) do
    Result.html(result)
  end

  @doc """
  Returns the combined text of result or result's children, which may be an
  empty string.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div>Hello, <b>World!</b></div>", css("div"))
      #Meeseeks.Result<{ <div>Hello, <b>World!</b></div> }>
      iex> Meeseeks.own_text(result)
      "Hello,"
  """
  @spec own_text(Result.t) :: String.t
  def own_text(result) do
    Result.own_text(result)
  end

  @doc """
  Returns result's tag, or nil if result represents a node without a tag.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div id=example>Hi</div>", css("#example"))
      #Meeseeks.Result<{ <div id="example">Hi</div> }>
      iex> Meeseeks.tag(result)
      "div"
  """
  @spec tag(Result.t) :: String.t | nil
  def tag(result) do
    Result.tag(result)
  end

  @doc """
  Returns the combined text of result or result's descendants, which may be
  an empty string.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div>Hello, <b>World!</b></div>", css("div"))
      #Meeseeks.Result<{ <div>Hello, <b>World!</b></div> }>
      iex> Meeseeks.text(result)
      "Hello, World!"
  """
  @spec text(Result.t) :: String.t
  def text(result) do
    Result.text(result)
  end

  @doc """
  Returns a `Meeseeks.TupleTree` of result and its descendants.

  ## Examples

      iex> import Meeseeks.CSS
      iex> result = Meeseeks.one("<div id=example>Hi</div>", css("#example"))
      #Meeseeks.Result<{ <div id="example">Hi</div> }>
      iex> Meeseeks.tree(result)
      {"div", [{"id", "example"}], ["Hi"]}
  """
  @spec tree(Result.t) :: TupleTree.node_t
  def tree(result) do
    Result.tree(result)
  end
end
