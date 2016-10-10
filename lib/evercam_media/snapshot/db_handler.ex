defmodule EvercamMedia.Snapshot.DBHandler do
  @moduledoc """
  This module should ideally delegate all the updates to be made to the database
  on various events to another module.

  Right now, this is a extracted and slightly modified from the previous version of
  worker.

  These are the list of tasks for the db handler
    * Create an entry in the snapshots table for each retrived snapshots
    * Update the CameraActivity table whenever there is a change in the camera status
    * Update the status and last_polled_at values of Camera table
    * Update the thumbnail_url of the Camera table - This was done in the previous
    version and not now. This update can be avoided if thumbnails can be dynamically
    served.
  """
  use GenEvent
  require Logger
  alias EvercamMedia.Repo
  alias EvercamMedia.SnapshotRepo
  alias EvercamMedia.Util
  alias EvercamMedia.Snapshot.Error
  alias EvercamMedia.Snapshot.WorkerSupervisor

  def handle_event({:got_snapshot, data}, state) do
    {camera_exid, timestamp, _image} = data
    Logger.debug "[#{camera_exid}] [snapshot_success]"
    spawn fn -> update_camera_status("#{camera_exid}", timestamp, true) end
    {:ok, state}
  end

  def handle_event({:snapshot_error, data}, state) do
    {camera_exid, timestamp, error} = data
    Error.parse(error) |> Error.handle(camera_exid, timestamp, error)
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def update_camera_status(camera_exid, timestamp, status, error_code \\ "generic", error_weight \\ 0)

  def update_camera_status("", _timestamp, _status, _error_code, _error_weight), do: :noop
  def update_camera_status(camera_exid, timestamp, status, error_code, error_weight) do
    camera = Camera.get_full(camera_exid)
    old_error_total = ConCache.dirty_get_or_store(:snapshot_error, camera.exid, fn() -> 0 end)
    error_total = old_error_total + error_weight
    cond do
      status == true && camera.is_online != status ->
        change_camera_status(camera, timestamp, true)
        ConCache.dirty_put(:snapshot_error, camera.exid, 0)
        Logger.debug "[#{camera_exid}] [update_status] [online]"
      status == true ->
        ConCache.dirty_put(:snapshot_error, camera.exid, 0)
      status == false && camera.is_online != status && error_total >= 100 ->
        change_camera_status(camera, timestamp, false, error_code)
        Logger.info "[#{camera_exid}] [update_status] [offline] [#{error_code}]"
      status == false && camera.is_online != status ->
        ConCache.dirty_put(:snapshot_error, camera.exid, error_total)
        Logger.info "[#{camera_exid}] [update_status] [error] [#{error_code}] [#{error_total}]"
        pause_camera_requests(camera, error_code, rem(error_total, 5))
      status == false ->
        ConCache.dirty_put(:snapshot_error, camera.exid, error_total)
      true -> :noop
    end
    Camera.get_full(camera_exid)
  end

  defp pause_camera_requests(camera, "econnrefused", 0), do: do_pause_camera(camera)
  defp pause_camera_requests(camera, "device_error", 0), do: do_pause_camera(camera)
  defp pause_camera_requests(_camera, _error_code, _reminder), do: :noop

  defp do_pause_camera(camera) do
    Logger.debug("Pause camera requests for #{camera.exid}")
    camera.exid
    |> String.to_atom
    |> Process.whereis
    |> WorkerSupervisor.pause_worker(camera, true)
  end

  def change_camera_status(camera, timestamp, status, error_code \\ nil) do
    try do
      task = Task.async(fn() ->
        datetime =
          timestamp
          |> Calendar.DateTime.Parse.unix!
          |> Calendar.DateTime.to_erl
          |> Ecto.DateTime.cast!
        params = construct_camera(datetime, status, camera.is_online == status)
        changeset = Camera.changeset(camera, params)
        Repo.update!(changeset)
        Camera.invalidate_camera(camera)
        broadcast_change_to_users(camera)
        log_camera_status(camera, status, datetime, error_code)
      end)
      Task.await(task, :timer.seconds(1))
    catch _type, error ->
      Util.error_handler(error)
    end
  end

  def broadcast_change_to_users(camera) do
    User.with_access_to(camera)
    |> Enum.each(fn(user) -> Util.broadcast_camera_status(camera.exid, camera.is_online, user.username) end)
  end

  def log_camera_status(camera, true, datetime, nil), do: do_log_camera_status(camera, "online", datetime)
  def log_camera_status(camera, false, datetime, error_code), do: do_log_camera_status(camera, "offline", datetime, %{reason: error_code})

  defp do_log_camera_status(camera, status, datetime, extra \\ nil) do
    parameters = %{camera_id: camera.id, camera_exid: camera.exid, action: status, done_at: datetime, extra: extra}
    changeset = CameraActivity.changeset(%CameraActivity{}, parameters)
    SnapshotRepo.insert(changeset)
    if camera.is_online_email_owner_notification do
      EvercamMedia.UserMailer.camera_status(status, camera.owner, camera)
    end
  end

  defp construct_camera(datetime, online_status, online_status_unchanged)
  defp construct_camera(datetime, false, false) do
    %{last_polled_at: datetime, is_online: false, last_online_at: datetime}
  end
  defp construct_camera(datetime, status, _) do
    %{last_polled_at: datetime, is_online: status}
  end
end
