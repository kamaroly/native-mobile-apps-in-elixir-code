defmodule MobViewerTest do
  use ExUnit.Case, async: true

  # Under mix test the NIF isn't loaded (it's built for the phone), so the
  # plugin answers the way it does on any platform without one.
  test "with no native side, view answers with not_available" do
    assert MobViewer.view(:socket, "/tmp/report.pdf", "application/pdf") == :socket

    assert_received {:viewer, :error, json}
    assert MobViewer.decode(json) == %{"message" => "not_available"}
  end
end
