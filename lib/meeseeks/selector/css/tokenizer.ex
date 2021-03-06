defmodule Meeseeks.Selector.CSS.Tokenizer do
  @moduledoc false

  def tokenize(selector) do
    selector_chars = selector |> String.strip |> String.to_char_list
    {:ok, tokens, _} = :css_selector_tokenizer.string(selector_chars)
    tokens
  end
end
