defmodule Kalcifer.Engine.Nodes.Condition.FrequencyCapTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Engine.Nodes.Condition.FrequencyCap

  describe "execute/2" do
    test "returns allowed when customer is under the cap" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          customer_id: "cust_1",
          status: "completed"
        )

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:execution_step,
        instance: instance,
        node_type: "send_email",
        status: "completed",
        completed_at: now
      )

      config = %{"max_messages" => 5, "time_window" => "24h", "channel" => "email"}
      context = %{"_customer_id" => "cust_1"}

      assert {:branched, "allowed", %{capped: false, count: 1, max: 5}} =
               FrequencyCap.execute(config, context)
    end

    test "returns capped when customer is at or over max_messages" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          customer_id: "cust_2",
          status: "completed"
        )

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for _ <- 1..3 do
        insert(:execution_step,
          instance: instance,
          node_type: "send_email",
          status: "completed",
          completed_at: now
        )
      end

      config = %{"max_messages" => 3, "time_window" => "24h", "channel" => "email"}
      context = %{"_customer_id" => "cust_2"}

      assert {:branched, "capped", %{capped: true, count: 3, max: 3}} =
               FrequencyCap.execute(config, context)
    end

    test "returns allowed (fail open) when _customer_id is missing" do
      config = %{"max_messages" => 5, "time_window" => "24h", "channel" => "email"}
      context = %{}

      assert {:branched, "allowed", %{capped: false, error: :missing_customer_id}} =
               FrequencyCap.execute(config, context)
    end

    test "returns allowed (fail open) when config is invalid" do
      config = %{"max_messages" => "not_a_number", "time_window" => "???"}
      context = %{"_customer_id" => "cust_1"}

      assert {:branched, "allowed", %{capped: false, error: :invalid_config}} =
               FrequencyCap.execute(config, context)
    end

    test "counts only the configured channel's node types" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          customer_id: "cust_3",
          status: "completed"
        )

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 2 email steps + 1 sms step
      for _ <- 1..2 do
        insert(:execution_step,
          instance: instance,
          node_type: "send_email",
          status: "completed",
          completed_at: now
        )
      end

      insert(:execution_step,
        instance: instance,
        node_type: "send_sms",
        status: "completed",
        completed_at: now
      )

      # Cap on email only: 2 emails should be at cap
      config = %{"max_messages" => 2, "time_window" => "24h", "channel" => "email"}
      context = %{"_customer_id" => "cust_3"}

      assert {:branched, "capped", %{capped: true, count: 2}} =
               FrequencyCap.execute(config, context)

      # Cap on sms only: 1 sms should be under cap
      sms_config = %{"max_messages" => 2, "time_window" => "24h", "channel" => "sms"}

      assert {:branched, "allowed", %{capped: false, count: 1}} =
               FrequencyCap.execute(sms_config, context)
    end

    test "counts only completed steps within the time window" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          customer_id: "cust_4",
          status: "completed"
        )

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old = DateTime.add(now, -48 * 3600, :second)

      # One recent, one old
      insert(:execution_step,
        instance: instance,
        node_type: "send_email",
        status: "completed",
        completed_at: now
      )

      insert(:execution_step,
        instance: instance,
        node_type: "send_email",
        status: "completed",
        completed_at: old
      )

      config = %{"max_messages" => 2, "time_window" => "24h", "channel" => "email"}
      context = %{"_customer_id" => "cust_4"}

      # Only 1 within the last 24h
      assert {:branched, "allowed", %{capped: false, count: 1}} =
               FrequencyCap.execute(config, context)
    end

    test "channel 'all' aggregates all message types" do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)

      instance =
        insert(:flow_instance,
          flow: flow,
          tenant: tenant,
          customer_id: "cust_5",
          status: "completed"
        )

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:execution_step,
        instance: instance,
        node_type: "send_email",
        status: "completed",
        completed_at: now
      )

      insert(:execution_step,
        instance: instance,
        node_type: "send_sms",
        status: "completed",
        completed_at: now
      )

      insert(:execution_step,
        instance: instance,
        node_type: "send_push",
        status: "completed",
        completed_at: now
      )

      config = %{"max_messages" => 3, "time_window" => "24h", "channel" => "all"}
      context = %{"_customer_id" => "cust_5"}

      assert {:branched, "capped", %{capped: true, count: 3}} =
               FrequencyCap.execute(config, context)
    end
  end
end
