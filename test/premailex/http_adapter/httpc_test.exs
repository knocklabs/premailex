defmodule Premailex.HTTPAdapter.HttpcTest do
  use ExUnit.Case

  alias Premailex.HTTPAdapter.Httpc

  test "request/5 rejects certificates not in the OS certificate store by default" do
    TestServer.start(scheme: :https)

    assert {:error, {:failed_connect, _}} = Httpc.request(:get, TestServer.url() <> "/", nil, [])
  end
end
