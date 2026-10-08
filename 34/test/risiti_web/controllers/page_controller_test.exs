defmodule RisitiWeb.PageControllerTest do
  use RisitiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Sign in with your phone number"
  end
end
