defmodule Kalcifer.Customers.SegmentsTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Customers

  describe "segment CRUD" do
    test "create_segment with valid attrs" do
      tenant = insert(:tenant)

      assert {:ok, segment} =
               Customers.create_segment(%{
                 name: "VIP customers",
                 tenant_id: tenant.id,
                 rules: [%{"field" => "tags", "operator" => "contains", "value" => "vip"}]
               })

      assert segment.type == "dynamic"
      assert Customers.get_segment(segment.id).name == "VIP customers"
    end

    test "create_segment requires name and tenant" do
      assert {:error, changeset} = Customers.create_segment(%{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:tenant_id]
    end

    test "create_segment rejects invalid type" do
      tenant = insert(:tenant)

      assert {:error, changeset} =
               Customers.create_segment(%{name: "X", tenant_id: tenant.id, type: "weird"})

      assert errors_on(changeset)[:type]
    end

    test "list_segments returns only the tenant's segments ordered by name" do
      tenant = insert(:tenant)
      insert(:segment, tenant: tenant, name: "B segment")
      insert(:segment, tenant: tenant, name: "A segment")
      insert(:segment)

      names = tenant.id |> Customers.list_segments() |> Enum.map(& &1.name)
      assert names == ["A segment", "B segment"]
    end

    test "update_segment changes rules" do
      segment = insert(:segment)
      rules = [%{"field" => "plan", "operator" => "eq", "value" => "pro"}]

      assert {:ok, updated} = Customers.update_segment(segment, %{rules: rules})
      assert updated.rules == rules
    end

    test "delete_segment removes the record" do
      segment = insert(:segment)
      assert {:ok, _} = Customers.delete_segment(segment)
      assert Customers.get_segment(segment.id) == nil
    end
  end

  describe "customer_segment_ids/1" do
    test "returns ids of matching segments only" do
      tenant = insert(:tenant)

      vip =
        insert(:segment,
          tenant: tenant,
          rules: [%{"field" => "tags", "operator" => "contains", "value" => "vip"}]
        )

      _pro =
        insert(:segment,
          tenant: tenant,
          rules: [%{"field" => "plan", "operator" => "eq", "value" => "pro"}]
        )

      customer = insert(:customer, tenant: tenant, tags: ["vip"], properties: %{})

      assert Customers.customer_segment_ids(customer) == [vip.id]
    end

    test "ignores segments of other tenants" do
      tenant = insert(:tenant)
      insert(:segment, rules: [])

      customer = insert(:customer, tenant: tenant)
      assert Customers.customer_segment_ids(customer) == []
    end
  end
end
