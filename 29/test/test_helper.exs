# Tests that need a receipt reader the machine doesn't have are skipped.
exclude = for tool <- [:pdftotext, :tesseract], !System.find_executable("#{tool}"), do: tool
ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Risiti.Repo, :manual)
