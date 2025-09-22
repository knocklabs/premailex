defmodule Premailex.HTMLInlineStyles do
  @moduledoc """
  Module that processes inline styling in HMTL.
  """
  require Logger

  alias Premailex.{CSSParser, HTMLParser, Util}

  @doc """
  Processes an HTML string adding inline styles.

  Options:
    * `:css_selector` - the style tags to be processed for inline styling, defaults to `style,link[rel="stylesheet"][href]`
    * `:optimize` - list or atom option for optimizing the output. The following values can be used:
      * `:none` - no optimization (default)
      * `:all` - apply all optimization steps
      * `:remove_style_tags` - Remove style tags (can be combined in a list)
  """
  @spec process(
          String.t() | HTMLParser.html_tree(),
          [CSSParser.rule_set()] | nil,
          Keyword.t() | nil
        ) :: String.t()
  def process(html_or_html_tree, css_rule_sets_or_options \\ nil, options \\ nil)

  def process(html, css_rule_sets_or_options, options) when is_binary(html) do
    html
    |> HTMLParser.parse()
    |> process(css_rule_sets_or_options, options)
  end

  def process(html_tree, css_rule_sets_or_options, nil) do
    case Keyword.keyword?(css_rule_sets_or_options) do
      true -> process(html_tree, nil, css_rule_sets_or_options)
      false -> process(html_tree, css_rule_sets_or_options, [])
    end
  end

  def process(html_tree, nil, options) do
    css_selector = Keyword.get(options, :css_selector, "style,link[rel=\"stylesheet\"][href]")
    css_rule_sets = load_styles(html_tree, css_selector)
    options = Keyword.put_new(options, :css_selector, css_selector)

    process(html_tree, css_rule_sets, options)
  end

  def process(html_tree, css_rules_sets, options) do
    optimize_steps = Keyword.get(options, :optimize, :none)
    optimize_options = Keyword.take(options, [:css_selector])

    css_rules_sets
    |> apply_styles(html_tree)
    |> normalize_styles()
    |> optimize(optimize_steps, optimize_options)
    |> remove_empty_comments()
    |> HTMLParser.to_string()
  end

  defp load_styles(tree, css_selector) do
    tree
    |> HTMLParser.all(css_selector)
    |> Enum.map(&load_css(&1))
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.reduce([], &Enum.concat(&1, &2))
  end

  defp apply_styles(styles, html_tree) do
    hidden_elements =
      html_tree
      |> HTMLParser.all("head")
      |> Enum.reduce([], fn element, acc ->
        index = to_string(length(acc))

        acc ++ [{index, element, {"premailex", [{"data-index", index}], []}}]
      end)

    visible_html_tree =
      Enum.reduce(hidden_elements, html_tree, fn {_index, hidden_element, placeholder},
                                                 html_tree ->
        Util.traverse_until_first(html_tree, hidden_element, fn _element -> placeholder end)
      end)

    styles
    |> Enum.reduce(visible_html_tree, &add_rule_set_to_html(&1, &2))
    |> Util.traverse("premailex", fn {"premailex", attrs, _children} ->
      {"data-index", index} = Enum.find(attrs, &(elem(&1, 0) == "data-index"))

      {_index, hidden_element, _replacement} = Enum.find(hidden_elements, &(elem(&1, 0) == index))

      hidden_element
    end)
  end

  defp load_css({"style", _, content}) do
    content
    |> Enum.join("\n")
    |> CSSParser.parse()
  end

  defp load_css({"link", attrs, _}), do: load_css({"link", List.keyfind(attrs, "href", 0)})

  defp load_css({"link", {"href", url}}) do
    {http_adapter, opts} = http_adapter()

    :get
    |> http_adapter.request(url, nil, [], opts)
    |> parse_body(http_adapter, url)
  end

  defp parse_body({:ok, %{status: status, body: body}}, _http_adapter, _url)
       when status in 200..399 do
    CSSParser.parse(body)
  end

  defp parse_body({:ok, %{status: status}}, _http_adapter, url) do
    Logger.debug("Ignoring #{url} styles because received unexpected HTTP status: #{status}")

    nil
  end

  defp parse_body({:error, error}, http_adapter, url) do
    Logger.debug(
      "Ignoring #{url} styles because of unexpected error from #{inspect(http_adapter)}:\n\n#{inspect(error)}"
    )

    nil
  end

  defp add_rule_set_to_html(%{selector: selector, rules: rules, specificity: specificity}, html) do
    html
    |> HTMLParser.all(selector)
    |> Enum.reduce(html, &update_style_for_html(&2, &1, rules, specificity))
  end

  defp update_style_for_html(html, needle, rules, specificity) do
    Util.traverse_until_first(html, needle, &update_style_for_element(&1, rules, specificity))
  end

  defp update_style_for_element({name, attrs, children}, rules, specificity) do
    style =
      attrs
      |> Enum.into(%{})
      |> Map.get("style", nil)
      |> set_inline_style_specificity()
      |> add_styles_with_specificity(rules, specificity)

    attrs =
      attrs
      |> Enum.filter(fn {name, _} -> name != "style" end)
      |> Enum.concat([{"style", style}])

    {name, attrs, children}
  end

  defp set_inline_style_specificity(nil), do: ""
  defp set_inline_style_specificity("[SPEC=" <> _rest = style), do: style
  defp set_inline_style_specificity(style), do: "[SPEC=1000[#{style}]]"

  defp add_styles_with_specificity(style, rules, specificity) do
    "#{style}[SPEC=#{specificity}[#{CSSParser.to_string(rules)}]]"
  end

  defp normalize_styles(html) do
    html
    |> HTMLParser.all("[style]")
    |> Enum.reduce(html, &merge_styles(&2, &1))
  end

  defp merge_styles(html, needle) do
    Util.traverse_until_first(html, needle, &merge_style/1)
  end

  defp merge_style({name, attrs, children}) do
    current_style =
      attrs
      |> Enum.into(%{})
      |> Map.get("style")

    style =
      ~r/\[SPEC\=([\d]+)\[(.[^\]\]]*)\]\]/
      |> Regex.scan(current_style)
      |> Enum.map(fn [_, specificity, rule] ->
        %{specificity: specificity, rules: CSSParser.parse_rules(rule)}
      end)
      |> CSSParser.merge()
      |> CSSParser.to_string()
      |> case do
        "" -> current_style
        style -> style
      end

    attrs =
      attrs
      |> Enum.filter(fn {name, _} -> name != "style" end)
      |> Enum.concat([{"style", style}])

    {name, attrs, children}
  end

  defp optimize(tree, steps, options) when is_atom(steps), do: optimize(tree, [steps], options)
  defp optimize(tree, [:none], _options), do: tree
  defp optimize(tree, [:all], options), do: optimize(tree, [:remove_style_tags], options)

  defp optimize(tree, steps, options) do
    maybe_remove_style_tags(tree, steps, Keyword.get(options, :css_selector))
  end

  defp maybe_remove_style_tags(tree, _steps, nil), do: tree

  defp maybe_remove_style_tags(tree, steps, css_selector) do
    case Enum.member?(steps, :remove_style_tags) do
      true -> HTMLParser.filter(tree, css_selector)
      false -> tree
    end
  end

  defp remove_empty_comments(tree) do
    Util.traverse(tree, :comment, fn
      {:comment, "[if " <> _rest} = element -> element
      {:comment, "<![endif]" <> _rest} = element -> element
      {:comment, _comment} -> ""
    end)
  end

  defp http_adapter do
    case Application.get_env(:premailex, :http_adapter, Premailex.HTTPAdapter.Httpc) do
      {adapter, opts} -> {adapter, opts}
      adapter -> {adapter, nil}
    end
  end
end
