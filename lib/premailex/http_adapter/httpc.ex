defmodule Premailex.HTTPAdapter.Httpc do
  @moduledoc """
  HTTP adapter module for making http requests with httpc.

  By default, SSL requests verify the server certificate against the OS
  certificate store loaded by `:public_key.cacerts_get/0`.
  """
  alias Premailex.{HTTPAdapter, HTTPAdapter.HTTPResponse}

  @behaviour HTTPAdapter

  @impl HTTPAdapter
  def request(method, url, body, headers, httpc_opts \\ nil) do
    headers = headers ++ [HTTPAdapter.user_agent_header()]
    request = httpc_request(url, body, headers)

    method
    |> :httpc.request(request, parse_httpc_opts(httpc_opts), [])
    |> format_response()
  end

  defp httpc_request(url, body, headers) do
    url = to_charlist(url)
    headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    do_httpc_request(url, body, headers)
  end

  defp do_httpc_request(url, nil, headers) do
    {url, headers}
  end

  defp do_httpc_request(url, body, headers) do
    {content_type, headers} = split_content_type_headers(headers)
    body = to_charlist(body)

    {url, headers, content_type, body}
  end

  defp split_content_type_headers(headers) do
    case List.keytake(headers, ~c"content-type", 0) do
      nil -> {~c"text/plain", headers}
      {{_, ct}, headers} -> {ct, headers}
    end
  end

  defp format_response({:ok, {{_, status, _}, headers, body}}) do
    headers =
      Enum.map(headers, fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value)}
      end)

    body = IO.iodata_to_binary(body)

    {:ok, %HTTPResponse{status: status, headers: headers, body: body}}
  end

  defp format_response({:error, error}), do: {:error, error}

  defp parse_httpc_opts(nil), do: [ssl: default_ssl_opts()]
  defp parse_httpc_opts(opts), do: opts

  defp default_ssl_opts do
    [
      verify: :verify_peer,
      depth: 99,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
