defmodule RisitiApp.HttpTest do
  use ExUnit.Case, async: true

  alias RisitiApp.Http

  # A one-request server on a free port: it hands what it received to the
  # test and answers with `response`.
  defp serve(response) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test = self()

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      send(test, {:received, read_request(socket, "")})
      :ok = :gen_tcp.send(socket, response)
      :gen_tcp.close(socket)
    end)

    "http://127.0.0.1:#{port}"
  end

  # Reads until the body is as long as content-length says.
  defp read_request(socket, acc) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    acc = acc <> data

    with [head, body] <- String.split(acc, "\r\n\r\n", parts: 2),
         [_, length] <- Regex.run(~r/content-length: (\d+)/i, head),
         true <- byte_size(body) >= String.to_integer(length) do
      acc
    else
      _ -> read_request(socket, acc)
    end
  end

  defp json_response(body),
    do:
      "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
        body

  test "sends JSON and decodes the JSON answer" do
    url = serve(json_response(~s({"sent":true})))

    assert {:ok, 200, %{"sent" => true}} =
             Http.request(:post, url <> "/api/auth/code",
               headers: [{"accept", "application/json"}],
               body: {:json, %{phone: "+254712345678"}}
             )

    assert_received {:received, request}
    assert request =~ "POST /api/auth/code"
    assert request =~ ~r/content-type: application\/json/i
    assert request =~ ~s({"phone":"+254712345678"})
  end

  @tag :tmp_dir
  test "sends fields and files as multipart", %{tmp_dir: dir} do
    photo = Path.join(dir, "receipt.jpg")
    File.write!(photo, "not really a jpeg")
    url = serve(json_response("{}"))

    assert {:ok, 200, %{}} =
             Http.request(:put, url <> "/api/transactions/abc",
               body:
                 {:multipart,
                  [{"vendor", "Naivas"}, {"photo", {:file, photo, "receipt.jpg", "image/jpeg"}}]}
             )

    assert_received {:received, request}
    [_, boundary] = Regex.run(~r/boundary=(\S+)/, request)
    assert request =~ ~s(Content-Disposition: form-data; name="vendor"\r\n\r\nNaivas\r\n)
    assert request =~ ~s(name="photo"; filename="receipt.jpg"\r\nContent-Type: image/jpeg)
    assert request =~ "not really a jpeg"
    assert String.ends_with?(request, "--" <> boundary <> "--\r\n")
  end

  test "a file that isn't there fails before anything is sent" do
    assert {:error, :enoent} =
             Http.request(:put, "http://127.0.0.1:9/x",
               body: {:multipart, [{"photo", {:file, "/no/such/file.jpg", "x.jpg", "image/jpeg"}}]}
             )
  end
end
