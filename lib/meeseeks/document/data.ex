defmodule Meeseeks.Document.Data do
  @moduledoc false

  use Meeseeks.Document.Node

  alias Meeseeks.Document.{Data, Helpers}

  @enforce_keys [:id]
  defstruct parent: nil, id: nil, type: nil, content: ""

  def data(node, _document) do
    Helpers.collapse_whitespace(node.content)
  end

  def html(%Data{type: :cdata, content: content}, _document) do
    "<![CDATA[#{content}]]>"
  end

  def html(node, _document) do
    node.content
  end

  def tree(node, _document) do
    node.content
  end
end
