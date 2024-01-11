defmodule Ots.ExpirationChecker do
  use GenServer
  require Logger
  alias Ots.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(state) do
    Logger.info("Starting expiry checker...", state)
    interval = get_interval(state)
    # Schedule work to be performed at some point
    schedule_work(interval)
    {:ok, state}
  end

  def handle_info(:work, state) do
    Logger.info("Starting expiry check...")

    Repo.all()
    |> Enum.each(fn {_id, secret} ->
      case secret do
        {id, _, expire, _cipher} ->
          now = DateTime.now!("Etc/UTC") |> DateTime.to_unix()

          if now > expire do
            Logger.info("Secret #{id} expired. Deleting..")
            Repo.delete(id)
          end

          :ok

        nil ->
          :ok
      end
    end)

    Logger.info("Expiry check finished")

    # Reschedule once more
    schedule_work(get_interval(state))
    {:noreply, state}
  end

  defp schedule_work(interval) do
    # In 3 minutes
    Process.send_after(self(), :work, interval)
  end

  defp get_interval(state) do
    Keyword.get(state, :interval, 180_000)
  end
end
