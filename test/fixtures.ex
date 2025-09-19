# run `mix fixtures` to clean and re-compile

defmodule ModuleCallsEnumMap do
  @moduledoc false
  def f() do
    Enum.map([1, 2, 3], fn x -> x + 1 end)
  end
end

defmodule ModuleCallsFileRead do
  @moduledoc false
  def f() do
    File.read("nofile.txt")
  end
end

defmodule ModuleSpawnsProcess do
  @moduledoc false
  def f() do
    spawn(ModuleSpawnsProcess, fn x -> x end, [])
  end
end

defmodule ModuleReceivesMessage do
  @moduledoc false
  def f() do
    receive do
      _ ->
        true
    end
  end
end

defmodule ModuleSendsMessage do
  @moduledoc false
  def f() do
    send(self(), :msg)
  end
end

defmodule ModuleCallsToAtom do
  @moduledoc false
  def f() do
    String.to_atom(Enum.random(["no", "nein", "nyet", "non"]))
  end
end
