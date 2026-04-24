defmodule Premailex.HTTPAdapter.ReqTest do
  use ExUnit.Case

  alias Premailex.HTTPAdapter.{HTTPResponse, Req}

  setup do
    start_supervised!({Finch, name: Req.Finch})
    TestServer.start()
    :ok
  end

  describe "request/5 GET" do
    test "returns ok with status, headers, and body on success" do
      TestServer.add("/get", to: fn conn -> Plug.Conn.send_resp(conn, 200, "hello") end)

      assert {:ok, %HTTPResponse{status: 200, body: "hello"}} =
               Req.request(:get, TestServer.url() <> "/get", nil, [])
    end

    test "returns headers as downcased strings" do
      TestServer.add("/headers",
        to: fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-custom", "value")
          |> Plug.Conn.send_resp(200, "")
        end
      )

      assert {:ok, %HTTPResponse{headers: headers}} =
               Req.request(:get, TestServer.url() <> "/headers", nil, [])

      assert List.keyfind(headers, "x-custom", 0) == {"x-custom", "value"}
    end

    test "sends User-Agent header" do
      test_pid = self()

      TestServer.add("/ua",
        to: fn conn ->
          send(test_pid, {:user_agent, Plug.Conn.get_req_header(conn, "user-agent")})
          Plug.Conn.send_resp(conn, 200, "")
        end
      )

      Req.request(:get, TestServer.url() <> "/ua", nil, [])

      assert_receive {:user_agent, [user_agent]}
      assert user_agent =~ "Premailex-"
    end

    test "returns non-200 statuses without error" do
      TestServer.add("/not-found", to: fn conn -> Plug.Conn.send_resp(conn, 404, "Not Found") end)

      assert {:ok, %HTTPResponse{status: 404, body: "Not Found"}} =
               Req.request(:get, TestServer.url() <> "/not-found", nil, [])
    end
  end

  describe "request/5 POST" do
    test "sends body and returns response" do
      test_pid = self()

      TestServer.add("/post",
        to: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:body, body})
          Plug.Conn.send_resp(conn, 201, "created")
        end
      )

      assert {:ok, %HTTPResponse{status: 201, body: "created"}} =
               Req.request(:post, TestServer.url() <> "/post", "payload", [
                 {"content-type", "text/plain"}
               ])

      assert_receive {:body, "payload"}
    end

    test "sends content-type header" do
      test_pid = self()

      TestServer.add("/post-ct",
        to: fn conn ->
          send(test_pid, {:content_type, Plug.Conn.get_req_header(conn, "content-type")})
          Plug.Conn.send_resp(conn, 200, "")
        end
      )

      Req.request(:post, TestServer.url() <> "/post-ct", "data", [
        {"content-type", "application/json"}
      ])

      assert_receive {:content_type, ["application/json"]}
    end
  end

  describe "request/5 error handling" do
    test "returns error when connection is refused" do
      assert {:error, _} = Req.request(:get, "http://localhost:0/no-server", nil, [])
    end
  end

  describe "request/5 opts" do
    test "passes additional opts to Req" do
      TestServer.add("/opts", to: fn conn -> Plug.Conn.send_resp(conn, 200, "ok") end)

      assert {:ok, %HTTPResponse{status: 200}} =
               Req.request(:get, TestServer.url() <> "/opts", nil, [], retry: false)
    end
  end
end
