import Config

config :chord_sim,
  ecto_repos: [ChordSim.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :chord_sim, ChordSimWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ChordSimWeb.ErrorHTML, json: ChordSimWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ChordSim.PubSub,
  live_view: [signing_salt: "EDr8Y+Xz"]

config :chord_sim, ChordSim.Mailer, adapter: Swoosh.Adapters.Local


config :esbuild,
  version: "0.25.4",
  chord_sim: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# tailwind
config :tailwind,
  version: "4.1.12",
  chord_sim: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]


config :phoenix, :json_library, Jason


hosts =
  System.get_env("CHORD_NODES", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_atom/1)

config :libcluster,
  topologies: [
    chord_epmd: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: hosts]
    ],
    chord_gossip: [
      strategy: Cluster.Strategy.Gossip
    ]
  ]


import_config "#{config_env()}.exs"
