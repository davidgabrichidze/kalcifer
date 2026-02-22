defmodule Kalcifer.Engine.NodeBehaviour do
  @moduledoc false

  @type config :: map()
  @type context :: map()
  @type result :: map()

  @type execute_result ::
          {:completed, result()}
          | {:branched, branch_key :: String.t(), result()}
          | {:waiting, wait_config :: map()}
          | {:failed, reason :: term()}

  @type resume_result ::
          {:completed, result()}
          | {:branched, branch_key :: String.t(), result()}
          | {:failed, reason :: term()}

  @callback execute(config(), context()) :: execute_result()

  @callback resume(config(), context(), trigger :: term()) :: resume_result()

  @callback validate(config()) :: :ok | {:error, [String.t()]}

  @callback config_schema() :: map()

  @callback category() :: :trigger | :end | :action | :condition | :wait

  @optional_callbacks [resume: 3, validate: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Kalcifer.Engine.NodeBehaviour

      @impl true
      def validate(_config), do: :ok

      @impl true
      def resume(_config, _context, _trigger), do: {:failed, :not_resumable}

      defoverridable validate: 1, resume: 3
    end
  end
end
