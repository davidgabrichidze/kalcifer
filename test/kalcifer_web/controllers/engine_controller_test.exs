defmodule KalciferWeb.EngineControllerTest do
  use KalciferWeb.ConnCase, async: true

  describe "GET /api/v1/engine" do
    test "returns engine data with all sections", %{conn: conn} do
      conn = get(conn, "/api/v1/engine")
      assert json = json_response(conn, 200)

      # Node registry
      assert %{"total" => total, "nodes" => nodes, "categories" => categories} =
               json["node_registry"]

      assert is_integer(total)
      assert total >= 23
      assert is_list(nodes)
      assert is_map(categories)

      # Each node has required fields
      if nodes != [] do
        node = hd(nodes)
        assert Map.has_key?(node, "type")
        assert Map.has_key?(node, "module")
        assert Map.has_key?(node, "category")
      end

      # Oban
      assert %{"queues" => queues, "total_concurrency" => tc} = json["oban"]
      assert is_list(queues)
      assert is_integer(tc)

      if queues != [] do
        q = hd(queues)
        assert Map.has_key?(q, "name")
        assert Map.has_key?(q, "concurrency")
        assert Map.has_key?(q, "executing")
        assert Map.has_key?(q, "completed_24h")
      end

      # VM
      assert %{
               "memory_total_mb" => _,
               "process_count" => pc,
               "schedulers" => _,
               "uptime_seconds" => _,
               "otp_release" => _,
               "elixir_version" => _
             } = json["vm"]

      assert is_integer(pc)

      # DB
      assert %{"pool_size" => _, "latency_ms" => lat, "adapter" => "PostgreSQL"} = json["db"]
      assert is_number(lat)

      # Instances
      assert %{"running" => _, "waiting" => _, "total_active" => _} = json["instances"]
    end

    test "node registry categories are valid", %{conn: conn} do
      conn = get(conn, "/api/v1/engine")
      json = json_response(conn, 200)

      valid_categories = ~w(trigger condition wait action end unknown)

      for node <- json["node_registry"]["nodes"] do
        assert node["category"] in valid_categories,
               "Node #{node["type"]} has invalid category: #{node["category"]}"
      end
    end

    test "node registry includes built-in nodes", %{conn: conn} do
      conn = get(conn, "/api/v1/engine")
      json = json_response(conn, 200)

      types = Enum.map(json["node_registry"]["nodes"], & &1["type"])

      # Spot-check some built-in nodes
      assert "send_email" in types
      assert "condition" in types
      assert "wait" in types
      assert "event_entry" in types
      assert "exit" in types
    end

    test "oban queues match config", %{conn: conn} do
      conn = get(conn, "/api/v1/engine")
      json = json_response(conn, 200)

      queue_names = Enum.map(json["oban"]["queues"], & &1["name"])
      assert "flow_triggers" in queue_names
      assert "delayed_resume" in queue_names
      assert "maintenance" in queue_names
    end

    test "VM uptime is positive", %{conn: conn} do
      conn = get(conn, "/api/v1/engine")
      json = json_response(conn, 200)

      assert json["vm"]["uptime_seconds"] >= 0
      assert json["vm"]["process_count"] > 0
    end
  end
end
