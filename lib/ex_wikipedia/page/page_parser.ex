defmodule ExWikipedia.PageParser do
  @moduledoc """
  Parses Wikipedia's JSON response for a page.

  The response returned from the Wikipedia API should be valid JSON but we still need to sanitize
  it before returning to the user. Any HTML tags will get sanitized during this stage.
  """

  @behaviour ExWikipedia.Parser

  @doc """
  Sanitizes the response received from Wikipedia before returning to user.

  ## Options:

    - `:html_parser`: Parser used to parse HTML. Default: `Floki`


  ## Examples

      iex> ExWikipedia.PageParser.parse(%{
        parse: %{
          categories: [
            %{*: "Webarchive_template_wayback_links", hidden: "", sortkey: ""},
          ],
          headhtml: %{*: "headhtml in here"},
          images: ["Semi-protection-shackle.svg", "End_of_Ezekiel.ogg"],
          links: [
            %{*: "Pulp fiction (disambiguation)", exists: "", ns: 0}
          ],
          pageid: 54173,
          redirects: [],
          revid: 1063115250,
          text: %{
            *: "text in here"
          },
          title: "Pulp Fiction"
        }
      })
      {:ok,
       %{
         categories: ["Webarchive template wayback links"],
         content: "",
         external_links: nil,
         images: [],
         is_redirect?: false,
         page_id: 54173,
         revision_id: 1063115250,
         summary: "",
         title: "Pulp Fiction",
         url: ""
       }}

  """
  @impl true
  def parse(json, opts \\ [])

  def parse(%{error: %{info: info}}, _opts), do: {:error, info}

  def parse(json, opts) when is_list(opts) do
    defaults = %{follow_redirects: false, html_parser: Floki}
    do_parse(json, Map.merge(defaults, opts |> Map.new()))
  end

  defp do_parse(%{parse: %{redirects: redirects}}, %{follow_redirect: false})
       when length(redirects) > 0 do
    {:error, "Content is from a redirected page, but `follow_redirect` is set to false"}
  end

  defp do_parse(
         %{
           parse:
             %{
               title: title,
               pageid: page_id,
               revid: revision_id,
               text: text,
               redirects: redirects
             } = json
         },
         opts
       ) do
    {:ok,
     %{}
     |> Map.put(:categories, parse_categories(json))
     |> Map.put(:title, title)
     |> Map.put(:page_id, page_id)
     |> Map.put(:revision_id, revision_id)
     |> Map.put(:external_links, Map.get(json, :externallinks))
     |> Map.put(:url, get_url(json, opts))
     |> Map.put(:content, parse_content(text, opts))
     |> Map.put(:summary, parse_summary(text, opts))
     |> Map.put(:images, parse_images(text, opts))
     |> Map.put(:is_redirect?, is_redirect?(redirects))}
  end

  defp do_parse(_, _opts), do: {:error, "Wikipedia response too ambiguous."}

  defp is_redirect?([]), do: false

  defp is_redirect?(_), do: true

  # Images from `images` key are just relative urls. Grabbing absolute urls from body
  defp parse_images(%{*: text}, %{html_parser: html_parser}) do
    text
    |> html_parser.parse_document()
    |> case do
      {:ok, document} ->
        document
        |> html_parser.find("img")
        |> html_parser.attribute("src")
        |> Enum.map(fn x -> "https:" <> x end)

      {:error, _} ->
        []
    end
  end

  defp parse_summary(%{*: text}, %{html_parser: html_parser}) do
    with {:ok, document} <- html_parser.parse_document(text),
         [{_tag, _attr, ast} | _] <- html_parser.filter_out(document, "table"),
         [_first, _second, toc | _rest] <- html_parser.find(ast, "div") do
      toc_index = Enum.find_index(ast, fn x -> x == toc end)

      case toc_index do
        nil ->
          ast
          |> parse_summary_text(html_parser)

        _ ->
          Enum.slice(ast, 0, toc_index)
          |> parse_summary_text(html_parser)
      end
    else
      _ -> ""
    end
  end

  defp parse_summary_text(ast, html_parser) do
    ast
    |> html_parser.find("p")
    |> html_parser.filter_out("sup")
    |> html_parser.text()
    |> String.trim()
  end

  defp get_url(%{headhtml: %{*: headhtml}}, %{html_parser: html_parser}) do
    with {:ok, head} <- html_parser.parse_document(headhtml),
         link_ast <- html_parser.find(head, "link[rel=\"canonical\"]"),
         [url] <- html_parser.attribute(link_ast, "href") do
      url
    else
      _ -> ""
    end
  end

  defp get_url(_, _), do: ""

  defp parse_content(%{*: text}, %{html_parser: html_parser}) do
    with {:ok, document} <- html_parser.parse_document(text),
         [{_tag, _attr, ast} | _] <- html_parser.filter_out(document, "table") do
      ast
      |> html_parser.find("p")
      |> html_parser.filter_out("sup")
      |> html_parser.text()
      |> String.trim()
    else
      _ -> ""
    end
  end

  # The categories are inside of the "*" key
  defp parse_categories(%{categories: categories}) do
    Enum.map(categories, fn %{*: keys} -> String.replace(keys, "_", " ") end)
  end

  defp parse_categories(_), do: []
end