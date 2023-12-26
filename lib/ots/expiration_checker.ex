defmodule Ots.ExpirationChecker do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    # Schedule work to be performed at some point
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    IO.puts("Starting expiry check...")

    :ets.foldl(
      fn {id, _, expire, _cipher}, _acc ->
        now = DateTime.now!("Etc/UTC") |> DateTime.to_unix()

        if now > expire do
          IO.puts("Secret #{id} expired. Deleting..")
          :ets.delete(:secrets, id)
        end

        :ok
      end,
      nil,
      :secrets
    )

    IO.puts("Expiry check finished")

    # Reschedule once more
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    # In 3 minutes
    Process.send_after(self(), :work, 3 * 60 * 1000)
  end
end
