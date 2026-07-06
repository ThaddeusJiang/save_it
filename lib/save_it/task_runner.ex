defmodule SaveIt.TaskRunner do
  @moduledoc """
  Runs lightweight background calls with a supervised `Task`.

  This is a small fire-and-forget helper for work that does not need durable
  queue semantics.
  """

  @supervisor __MODULE__.Supervisor

  @type option :: {:supervisor, Supervisor.supervisor()} | Task.Supervisor.option()

  @spec supervisor() :: module()
  def supervisor, do: @supervisor

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, @supervisor)

    Task.Supervisor.child_spec(name: name)
  end

  @spec run(module(), atom(), [term()], [option()]) :: DynamicSupervisor.on_start_child()
  def run(module, function, args, opts \\ [])
      when is_atom(module) and is_atom(function) and is_list(args) do
    {supervisor, task_opts} = Keyword.pop(opts, :supervisor, @supervisor)

    Task.Supervisor.start_child(supervisor, module, function, args, task_opts)
  end
end
