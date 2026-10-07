defmodule RisitiWeb.Api.TransactionsTest do
  use RisitiWeb.ConnCase, async: false

  import Risiti.Fixtures

  setup do
    business_team()
  end

  defp api(person),
    do: build_conn() |> put_req_header("authorization", "Bearer " <> token(person))

  defp token(person), do: Risiti.Accounts.SignUp.api_token(person)

  defp upload(name, type) do
    %Plug.Upload{
      path: Path.expand("../../support/fixtures/#{name}", __DIR__),
      filename: name,
      content_type: type
    }
  end

  defp send_transaction(person, attrs) do
    {client_id, attrs} = Map.pop(attrs, "client_id")
    api(person) |> put(~p"/api/transactions/#{client_id}", attrs)
  end

  describe "PUT /api/transactions/:client_id" do
    test "creates, then updates the same one", %{member: otieno} do
      attrs = phone_transaction()

      assert %{"transaction" => %{"id" => id, "status" => "pending", "amount_cents" => 345_050}} =
               otieno |> send_transaction(attrs) |> json_response(200)

      assert %{"transaction" => %{"id" => ^id, "amount_cents" => 1_00}} =
               otieno
               |> send_transaction(%{attrs | "amount_cents" => "100"})
               |> json_response(200)

      assert %{"transactions" => [_one]} =
               api(otieno) |> get(~p"/api/transactions") |> json_response(200)
    end

    test "takes the photo and attachments, once", %{member: otieno} do
      attrs =
        phone_transaction(%{
          "type" => "payment_request",
          "method" => "till",
          "till_number" => "832909",
          "photo" => upload("receipt.jpg", "image/jpeg"),
          "attachments" => [upload("quotation.pdf", "application/pdf")]
        })

      assert %{"transaction" => %{"id" => id, "has_photo" => true, "attachments" => [pdf]}} =
               otieno |> send_transaction(attrs) |> json_response(200)

      assert %{"name" => "quotation.pdf", "content_type" => "application/pdf", "size" => 142} =
               pdf

      # Sent again after a dropped connection: still one attachment.
      assert %{"transaction" => %{"attachments" => [_]}} =
               otieno |> send_transaction(attrs) |> json_response(200)

      assert response(api(otieno) |> get(~p"/api/transactions/#{id}/photo"), 200) ==
               File.read!("test/support/fixtures/receipt.jpg")

      assert response(api(otieno) |> get(~p"/api/attachments/#{pdf["id"]}"), 200) =~ "%PDF"
    end

    test "refuses files that aren't images or PDFs", %{member: otieno} do
      attrs = phone_transaction(%{"photo" => upload("receipt.jpg", "text/plain")})

      assert %{"errors" => %{"photo" => "only images and PDFs"}} =
               otieno |> send_transaction(attrs) |> json_response(422)
    end

    test "answers what's wrong, field by field", %{member: otieno} do
      attrs =
        phone_transaction(%{"method" => "till", "till_number" => "12", "amount_cents" => "0"})

      assert %{"errors" => errors} = otieno |> send_transaction(attrs) |> json_response(422)
      # Short enough for the phone to put after the field's name.
      assert errors == %{
               "till_number" => "must be 5 to 7 digits",
               "amount_cents" => "must be greater than or equal to 1"
             }
    end

    test "can't touch a decided figure without sending it back", %{
      member: otieno,
      approver: achieng
    } do
      attrs = phone_transaction()
      %{"transaction" => %{"id" => id}} = otieno |> send_transaction(attrs) |> json_response(200)
      api(achieng) |> post(~p"/api/approvals/#{id}/approve", %{note: "OK"})

      assert %{"transaction" => %{"status" => "pending", "decision_note" => nil}} =
               otieno
               |> send_transaction(%{attrs | "amount_cents" => "1"})
               |> json_response(200)
    end
  end

  describe "DELETE /api/transactions/:client_id" do
    test "withdraws a pending one, and a missing one is already gone", %{member: otieno} do
      attrs = phone_transaction()
      otieno |> send_transaction(attrs)

      assert api(otieno) |> delete(~p"/api/transactions/#{attrs["client_id"]}") |> response(204)
      assert api(otieno) |> delete(~p"/api/transactions/#{attrs["client_id"]}") |> response(204)

      assert %{"transactions" => []} =
               api(otieno) |> get(~p"/api/transactions") |> json_response(200)
    end

    test "keeps a decided one", %{member: otieno, approver: achieng} do
      attrs = phone_transaction()
      %{"transaction" => %{"id" => id}} = otieno |> send_transaction(attrs) |> json_response(200)
      api(achieng) |> post(~p"/api/approvals/#{id}/approve", %{})

      assert %{"errors" => %{"status" => _}} =
               api(otieno)
               |> delete(~p"/api/transactions/#{attrs["client_id"]}")
               |> json_response(422)
    end
  end

  describe "approvals" do
    test "an approver sees what waits, and decides", %{member: otieno, approver: achieng} do
      %{"transaction" => %{"id" => id}} =
        otieno
        |> send_transaction(phone_transaction(type: "refund", method: "cash"))
        |> json_response(200)

      assert %{"transactions" => [%{"id" => ^id, "submitted_by" => %{"name" => "Otieno"}}]} =
               api(achieng) |> get(~p"/api/approvals") |> json_response(200)

      assert %{"transaction" => %{"status" => "approved"}} =
               api(achieng)
               |> post(~p"/api/approvals/#{id}/approve", %{note: ""})
               |> json_response(200)

      assert %{"transaction" => %{"status" => "paid", "paid_at" => paid_at}} =
               api(achieng) |> post(~p"/api/approvals/#{id}/pay") |> json_response(200)

      assert paid_at

      assert %{"transactions" => []} =
               api(achieng) |> get(~p"/api/approvals") |> json_response(200)
    end

    test "a rejection needs a note", %{member: otieno, approver: achieng} do
      %{"transaction" => %{"id" => id}} =
        otieno |> send_transaction(phone_transaction()) |> json_response(200)

      assert %{"errors" => %{"note" => _}} =
               api(achieng)
               |> post(~p"/api/approvals/#{id}/reject", %{note: " "})
               |> json_response(422)
    end

    test "others get 403, and can't decide", %{member: otieno, accountant: kamau} do
      %{"transaction" => %{"id" => id}} =
        otieno |> send_transaction(phone_transaction()) |> json_response(200)

      assert api(otieno) |> get(~p"/api/approvals") |> json_response(403)
      assert api(kamau) |> post(~p"/api/approvals/#{id}/approve") |> json_response(403)
    end

    test "what you can't see is not found", %{approver: achieng} do
      %{owner: njeri} = personal_book()

      %{"transaction" => %{"id" => id}} =
        njeri |> send_transaction(phone_transaction()) |> json_response(200)

      assert %{"error" => "Not found"} =
               api(achieng) |> post(~p"/api/approvals/#{id}/approve") |> json_response(404)

      assert api(achieng) |> get(~p"/api/transactions/#{id}/photo") |> json_response(404)
    end

    test "an unknown decision is a 422", %{member: otieno, approver: achieng} do
      %{"transaction" => %{"id" => id}} =
        otieno |> send_transaction(phone_transaction()) |> json_response(200)

      assert %{"error" => _} =
               api(achieng) |> post(~p"/api/approvals/#{id}/maybe") |> json_response(422)
    end
  end

  test "the catalog has the types, methods and the team's categories", %{member: otieno} do
    assert %{"types" => types, "methods" => methods, "categories" => categories} =
             api(otieno) |> get(~p"/api/catalog") |> json_response(200)

    assert %{"code" => "refund", "payable" => true} = Enum.find(types, &(&1["code"] == "refund"))

    assert %{"required_fields" => ["paybill_number", "account_number"]} =
             Enum.find(methods, &(&1["code"] == "paybill"))

    assert "Fuel" in categories
  end

  test "a personal book's transactions come back approved" do
    %{owner: njeri} = personal_book()

    assert %{"transaction" => %{"status" => "approved"}} =
             njeri |> send_transaction(phone_transaction()) |> json_response(200)
  end

  test "everything needs a token" do
    for {method, path} <- [
          get: "/api/transactions",
          put: "/api/transactions/x",
          get: "/api/approvals"
        ] do
      assert %{"error" => "Sign in again"} =
               build_conn() |> dispatch(@endpoint, method, path) |> json_response(401)
    end
  end
end
