defmodule TaskKeeper do
  @moduledoc """
  Keeps the desired number of tasks with a capability to callback the new task requester when there is room for his task to be spawned.
  """

  use GenServer

  defstruct [:supervisor, :max_tasks, :callback_messge, :callback_queue, :running_tasks, :max_queue]

  # API (interface)

  def start_link(supervisor, max_tasks, max_queue, options \\ []) do
    GenServer.start_link(__MODULE__, {supervisor, max_tasks, max_queue}, options)
  end

  def spawn_task(task_keeper, task_spec) do
    task_keeper |> GenServer.call({:spawn_task, task_spec})
  end

  # Implementation (backend)

  @impl true
  def init({supervisor, max_tasks, max_queue}) do
    {:ok, %__MODULE__{supervisor: supervisor, max_tasks: max_tasks, max_queue: max_queue}}
  end

  @impl true
  def handle_call({:spawn_task, task_spec}, from, %__MODULE__{supervisor: supervisor, max_tasks: max_tasks, callback_queue: callback_queue, max_queue: max_queue, running_tasks: running_tasks} = state) do
    result =
      if supervisor |> get_active_tasks_count < max_tasks do
        supervisor |> start_child_task(task_spec) |> process_start_result
      else
        :try_enqueue
      end
    {reply, new_state} =
      case result do
        {:started, pid} ->
          reference = pid |> Process.monitor
          {result, %{state|running_tasks: (running_tasks || %{}) |> Map.put(reference, pid)}}
        :try_enqueue ->
          case (callback_queue || :queue.new) |> try_enqueue(task_spec, max_queue) do
            :max_queue ->
              {:out_of_room, state}
            new_queue ->
              {:enqueued, %{state|callback_queue: new_queue}}
          end
      end
    {:reply, reply, new_state}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, _object, _reason}, %__MODULE__{running_tasks: running_tasks, callback_queue: callback_queue, supervisor: supervisor} = state) do
    upd_state =
      case running_tasks |> Map.fetch(reference) do
        {:ok, _pid} ->
          IO.puts "Task finished!"
          {task_spec, upd_queue} = (callback_queue || :queue.new) |> dequeue
          case supervisor |> start_child_task(task_spec) |> process_start_result do
            :try_enqueue ->
              %{state|running_tasks: running_tasks |> Map.delete(reference)}
            :nothing ->
              %{state|running_tasks: running_tasks |> Map.delete(reference)}
            {:started, pid} ->
              new_reference = pid |> Process.monitor
              IO.puts "Started new process instead of the old one"
              %{state|running_tasks: running_tasks |> Map.delete(reference) |> Map.put(new_reference, pid), callback_queue: upd_queue}
          end
        :error -> state
      end
    {:noreply, upd_state}
  end

  defp get_active_tasks_count(supervisor) do
    %{active: active} = supervisor |> Supervisor.count_children
    active
  end

  defp dequeue(queue), do: queue |> :queue.out

  defp enqueue(queue, item), do: item |> :queue.in(queue)

  defp get_length(queue), do: queue |> :queue.len

  defp start_child_task(_supervisor, :empty), do: :nothing

  defp start_child_task(supervisor, {:value, task_spec}), do: start_child_task supervisor, task_spec

  defp start_child_task(supervisor, task_spec) when task_spec |> is_function do
    supervisor |> Task.Supervisor.start_child(task_spec)
  end

  defp start_child_task(supervisor, {module, function, args} = _task_spec) when module |> is_atom and function |> is_atom and args |> is_list do
    supervisor |> Task.Supervisor.start_child(module, function, args)
  end

  defp process_start_result(supervisor_start_result)

  defp process_start_result(:nothing), do: :nothing
  defp process_start_result({:ok, pid} = _start_result) when pid |> is_pid(), do: {:started, pid}
  defp process_start_result({:error, reason} = start_result), do: :try_enqueue

  defp try_enqueue(queue, value, max_queue) do
    if queue |> get_length < max_queue do
      queue |> enqueue(value)
    else
      :max_queue
    end
  end

end
