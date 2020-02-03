defmodule TaskKeeperTest do
  use ExUnit.Case
  doctest TaskKeeper

  test "greets the world" do
    assert TaskKeeper.hello() == :world
  end
end
