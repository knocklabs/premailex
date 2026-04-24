defmodule Premailex.HTTPAdapter.Req do
  @moduledoc """
  HTTP adapter module for making http requests with Req.

  Requires the `:req` library to be added to your project dependencies:

      {:req, ">= 0.0.0", optional: true}
  """
  alias Premailex.{HTTPAdapter, HTTPAdapter.HTTPResponse}

  @behaviour HTTPAdapter

  @impl HTTPAdapter
  def request(method, url, body, headers, opts \\ []) do
    headers = headers ++ [HTTPAdapter.user_agent_header()]

    [method: method, url: url, headers: headers]
    |> maybe_put_body(body)
    |> Keyword.merge(opts)
    |> Req.request()
    |> format_response()
  end

  defp maybe_put_body(opts, nil), do: opts
  defp maybe_put_body(opts, body), do: Keyword.put(opts, :body, body)

  defp format_response({:ok, %Req.Response{status: status, headers: headers, body: body}}) do
    headers =
      Enum.map(headers, fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value)}
      end)

    {:ok, %HTTPResponse{status: status, headers: headers, body: body}}
  end

  defp format_response({:error, error}), do: {:error, error}
end
