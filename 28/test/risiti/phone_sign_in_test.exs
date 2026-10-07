defmodule Risiti.PhoneSignInTest do
  use Risiti.DataCase, async: false
  use Oban.Testing, repo: Risiti.Repo

  alias Risiti.Accounts.{PhoneSignIn, User}

  # The code from the SMS the Log adapter "sent" to this process.
  defp code_for(phone) do
    # The SMS is a job now: run it here, and the Log adapter "sends" to us.
    Oban.drain_queue(queue: :sms)
    assert_received {:sms, ^phone, text}
    [code] = Regex.run(~r/\d{6}/, text)
    code
  end

  test "a new number gets a sign-up token once its code is right" do
    assert :ok = PhoneSignIn.request_code("0712 345 678")
    code = code_for("+254712345678")

    assert {:ok, :new, signup_token} = PhoneSignIn.verify("0712345678", code)
    assert is_binary(signup_token)
  end

  test "a known number signs straight in" do
    user = Ash.Seed.seed!(User, %{phone: "+254712345678", name: "Wanjiku"})

    :ok = PhoneSignIn.request_code("+254712345678")
    code = code_for("+254712345678")

    assert {:ok, %User{id: id}, token} = PhoneSignIn.verify("0712345678", code)
    assert id == user.id

    assert {:ok, %{"sub" => "user?id=" <> ^id}, User} =
             AshAuthentication.Jwt.verify(token, :risiti)
  end

  test "a code works once" do
    :ok = PhoneSignIn.request_code("0712345678")
    code = code_for("+254712345678")

    assert {:ok, :new, _} = PhoneSignIn.verify("0712345678", code)
    assert {:error, :invalid_code} = PhoneSignIn.verify("0712345678", code)
  end

  test "five wrong guesses use the code up" do
    :ok = PhoneSignIn.request_code("0712345678")
    code = code_for("+254712345678")
    wrong = if code == "111111", do: "222222", else: "111111"

    for _ <- 1..5, do: assert({:error, :invalid_code} = PhoneSignIn.verify("0712345678", wrong))
    assert {:error, :invalid_code} = PhoneSignIn.verify("0712345678", code)
  end

  test "five codes an hour to one number" do
    for _ <- 1..5, do: assert(:ok = PhoneSignIn.request_code("0712345678"))
    assert {:error, :too_many_requests} = PhoneSignIn.request_code("0712345678")
  end

  test "ten codes an hour from one address" do
    for n <- 1..10 do
      assert :ok =
               PhoneSignIn.request_code(
                 "07123456#{String.pad_leading("#{n}", 2, "0")}",
                 "10.0.0.1"
               )
    end

    assert {:error, :too_many_requests} = PhoneSignIn.request_code("0722000000", "10.0.0.1")
    assert :ok = PhoneSignIn.request_code("0722000000", "10.0.0.2")
  end

  test "a number that isn't a Kenyan mobile is refused before anything is sent" do
    assert {:error, :invalid_phone} = PhoneSignIn.request_code("12345")
    refute_enqueued worker: Risiti.SMSWorker
  end

  defmodule FailingSMS do
    @behaviour Risiti.SMS
    def deliver(_phone, _text, _config), do: {:error, :gateway_down}
  end

  test "the SMS goes out in the background, and is tried again if the gateway fails" do
    assert :ok = PhoneSignIn.request_code("0712345678")
    assert_enqueued worker: Risiti.SMSWorker, args: %{"phone" => "+254712345678"}, queue: :sms

    Application.put_env(:risiti, Risiti.SMS, adapter: FailingSMS)
    on_exit(fn -> Application.delete_env(:risiti, Risiti.SMS) end)

    # A failed attempt is an error, so Oban retries it later.
    assert %{failure: 1} = Oban.drain_queue(queue: :sms)
    assert Ash.count!(Risiti.Accounts.PhoneCode, authorize?: false) == 1
  end
end
