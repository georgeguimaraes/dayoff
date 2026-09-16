defmodule Mix.Tasks.Dayoff.Sync do
  @shortdoc "Syncs the holiday data and reference fixtures from upstream date-holidays"

  @moduledoc """
  Rebuilds `priv/data` and `test/fixtures/reference` from the upstream
  repositories `commenthol/date-holidays` (the data) and
  `commenthol/date-holidays-parser` (the Hijri and Hebrew tables). Needs
  Node 20 or newer and network access. The heavy lifting is in
  `scripts/sync/*.mjs`, this task only drives them.

      mix dayoff.sync            # rebuild everything from upstream master
      mix dayoff.sync --check    # only compare upstream with priv/data/VERSION.json
      mix dayoff.sync --fixtures DIR [--full]
                                 # write fixtures into DIR, --full for the wide year range

  The sync tracks the latest commit on master that touched the data folders,
  not releases, and records it in `priv/data/VERSION.json`. With
  `GITHUB_OUTPUT` set (GitHub Actions) `--check` writes `changed=true|false`.
  """

  use Mix.Task

  @sync_dir Path.expand("../../../scripts/sync", __DIR__)

  @impl Mix.Task
  def run(args) do
    ensure_node!()
    ensure_node_modules!()

    env = [{"TZ", "UTC"}]

    case System.cmd("node", ["sync.mjs" | args],
           cd: @sync_dir,
           env: env,
           into: IO.stream(),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("sync.mjs exited with status #{status}")
    end
  end

  defp ensure_node! do
    unless System.find_executable("node") do
      Mix.raise("mix dayoff.sync needs Node 20 or newer on the PATH")
    end
  end

  defp ensure_node_modules! do
    unless File.dir?(Path.join(@sync_dir, "node_modules")) do
      Mix.shell().info("installing the sync scripts' npm dependencies")

      case System.cmd("npm", ["install", "--no-audit", "--no-fund"],
             cd: @sync_dir,
             into: IO.stream()
           ) do
        {_, 0} -> :ok
        {_, status} -> Mix.raise("npm install exited with status #{status}")
      end
    end
  end
end
