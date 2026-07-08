defmodule Kalcifer.AI.SystemPrompt do
  @moduledoc """
  Composes the chat system prompt: base personality prompt + operator memory
  + current linked-flow snapshot. Always returns a binary, so callers never
  need nil-handling (previously the prompt was dropped entirely when the
  operator had no memories).
  """

  alias Kalcifer.AI.{Client, Context, FlowSnapshot}

  @spec build(String.t(), String.t() | nil) :: String.t()
  def build(tenant_id, conversation_id) do
    [
      Client.default_system_prompt(),
      memory_block(tenant_id),
      FlowSnapshot.for_conversation(tenant_id, conversation_id)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp memory_block(tenant_id) do
    memories = Context.recall_all(tenant_id)

    if Enum.empty?(memories) do
      nil
    else
      lines = Enum.map_join(memories, "\n", fn m -> "- #{m.key}: #{m.value}" end)

      """

      ## რაც მახსოვს ამ მომხმარებლის შესახებ:
      #{lines}

      გამოიყენე ეს ინფორმაცია საუბარში ბუნებრივად — ნუ ჩამოთვლი რა გახსოვს,
      უბრალოდ იცოდე და გაითვალისწინე.
      """
    end
  end
end
