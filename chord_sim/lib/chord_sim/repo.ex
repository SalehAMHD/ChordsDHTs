defmodule ChordSim.Repo do
  use Ecto.Repo,
    otp_app: :chord_sim,
    adapter: Ecto.Adapters.Postgres
end
