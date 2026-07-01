defmodule KalciferWeb.ParamsTest do
  use ExUnit.Case, async: true

  alias KalciferWeb.Params

  @schema [
    customer_id: [type: {:custom, Params, :non_empty_string, []}, required: true],
    dry_run: [type: :boolean, default: false],
    context: [type: {:custom, Params, :json_map, []}, default: %{}]
  ]

  test "validates and returns atom-keyed map with defaults" do
    assert {:ok, %{customer_id: "c1", dry_run: false, context: %{}}} =
             Params.validate(%{"customer_id" => "c1", "ignored" => "x"}, @schema)
  end

  test "missing required key fails" do
    assert {:error, {:invalid_params, message}} = Params.validate(%{}, @schema)
    assert message =~ "customer_id"
  end

  test "empty string fails non_empty_string" do
    assert {:error, {:invalid_params, message}} =
             Params.validate(%{"customer_id" => ""}, @schema)

    assert message =~ "non-empty"
  end

  test "wrong types fail" do
    assert {:error, {:invalid_params, _}} =
             Params.validate(%{"customer_id" => "c1", "dry_run" => "yes"}, @schema)

    assert {:error, {:invalid_params, _}} =
             Params.validate(%{"customer_id" => "c1", "context" => "not-a-map"}, @schema)
  end

  describe "pagination_schema/0" do
    test "applies defaults" do
      assert {:ok, %{limit: 50, offset: 0}} = Params.validate(%{}, Params.pagination_schema())
    end

    test "parses numeric strings from query params" do
      assert {:ok, %{limit: 10, offset: 20}} =
               Params.validate(%{"limit" => "10", "offset" => "20"}, Params.pagination_schema())
    end

    test "enforces bounds" do
      assert {:error, {:invalid_params, _}} =
               Params.validate(%{"limit" => "0"}, Params.pagination_schema())

      assert {:error, {:invalid_params, _}} =
               Params.validate(%{"limit" => "1000"}, Params.pagination_schema())

      assert {:error, {:invalid_params, _}} =
               Params.validate(%{"offset" => "-5"}, Params.pagination_schema())
    end

    test "rejects non-numeric values" do
      assert {:error, {:invalid_params, _}} =
               Params.validate(%{"limit" => "abc"}, Params.pagination_schema())
    end
  end
end
