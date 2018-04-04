defmodule Farmbot.Repo.Worker do
  @moduledoc "Handles syncing and caching of HTTP data."

  use GenServer
  alias Farmbot.System.ConfigStorage
  import ConfigStorage, only: [get_config_value: 3]
  use Farmbot.Logger

  # This allows for the sync to gracefully timeout
  # before terminating the GenServer.
  @gen_server_timeout_grace 1500

  @doc "Sync Farmbot with the Web APP."
  def sync(full \\ false) do
    timeout = sync_timeout()
    GenServer.call(__MODULE__, {:sync, [full, timeout]}, timeout + @gen_server_timeout_grace)
  end

  @doc "Waits for a sync to complete if one is happening."
  def await_sync do
    GenServer.call(__MODULE__, :await_sync, sync_timeout() + @gen_server_timeout_grace)
  end

  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  defmodule State do
    @moduledoc false
    defstruct [
      needs_full_sync?: true,
      waiting: [],
      syncing: false,
      sync_ref: nil,
      sync_timer: nil,
      sync_pid: nil,
    ]
  end

  def init([]) do
    {:ok, struct(State)}
  end

  def terminate(_, _) do
    :ok
  end

  def handle_call(:await_sync, from, %{syncing: true} = state) do
    {:noreply, %{state | waiting: [from | state.waiting]}}
  end

  def handle_call(:await_sync, _from, state) do
    {:reply, :ok, state}
  end

  # If a sync is already happening, just add our ref to the pool of waiting.
  def handle_call({:sync, [_, _]}, from, %{syncing: true} = state) do
    {:noreply, %{state | waiting: [from | state.waiting]}}
  end

  # full sync forced from function call.
  def handle_call({:sync, [true, timeout_ms]}, from, state) do
    pid = spawn(Farmbot.Repo, :full_sync, [])
    ref = Process.monitor(pid)
    timer = refresh_or_start_timeout(state.sync_timer, timeout_ms, ref, self())
    {:noreply, %{state | sync_pid: pid, sync_ref: ref, sync_timer: timer, waiting: [from | state.waiting], syncing: true}}
  end

  # full sync forced from internal state.
  def handle_call({:sync, [_, timeout_ms]}, from, %{needs_full_sync?: true} = state) do
    pid = spawn(Farmbot.Repo, :full_sync, [])
    ref = Process.monitor(pid)
    timer = refresh_or_start_timeout(state.sync_timer, timeout_ms, ref, self())
    {:noreply, %{state | sync_pid: pid, sync_ref: ref, sync_timer: timer, waiting: [from | state.waiting], syncing: true}}
  end

  # not a full sync.
  def handle_call({:sync, [false, timeout_ms]}, from, state) do
    pid = spawn(Farmbot.Repo, :partial_sync, [])
    ref = Process.monitor(pid)
    timer = refresh_or_start_timeout(state.sync_timer, timeout_ms, ref, self())
    {:noreply, %{state | sync_pid: pid, sync_ref: ref, sync_timer: timer, waiting: [from | state.waiting], syncing: true}}
  end

  # The sync process has taken too long.
  def handle_info({:sync_timeout, sync_ref}, %{sync_ref: sync_ref} = state) do
    Logger.error 1, "Sync timed out!"
    reply_waiting(state.waiting, {:error, :sync_timeout})
    {:noreply, %{state | waiting: [], sync_ref: nil, sync_pid: nil, syncing: false, sync_timer: nil}}
  end

  # Ignore timeouts that didn't get canceled for whatever reason.
  def handle_info({:sync_timeout, _old_ref}, state) do
    Logger.warn 1, "Got unexpected sync timeout."
    {:noreply, state}
  end

  # The sync process exited before the timeout.
  def handle_info({:DOWN, ref, :process, pid, reason}, %{sync_ref: ref, sync_pid: pid} = state) do
    reply_waiting(state.waiting, reason)
    maybe_cancel_timer(state.sync_timer)
    {:noreply, %{state | waiting: [], sync_ref: nil, sync_pid: nil, syncing: false, sync_timer: nil}}
  end

  # Happens if the sync completes _after_ a timeout.
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error 1, "Sync completed after timing out: #{inspect reason}"
    {:noreply, %{state | waiting: [], sync_ref: nil, sync_pid: nil, syncing: false, sync_timer: nil}}
  end

  defp sync_timeout do
    get_config_value(:float, "settings", "sync_timeout_ms") |> round()
  end

  defp refresh_or_start_timeout(old_timer, timeout_ms, sync_ref, pid) do
    maybe_cancel_timer(old_timer)
    Process.send_after(pid, {:sync_timeout, sync_ref}, timeout_ms)
  end

  defp maybe_cancel_timer(old_timer) do
    if old_timer && Process.read_timer(old_timer) do
      Process.cancel_timer(old_timer)
    end
  end

  defp reply_waiting(list, msg) do
    for from <- list do
      :ok = GenServer.reply(from, msg)
    end
  end
end
