defmodule Kalcifer.CustomersTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Customers

  describe "CRUD" do
    test "create_customer with valid attrs" do
      tenant = insert(:tenant)

      {:ok, customer} =
        Customers.create_customer(%{
          external_id: "ext_001",
          email: "alice@example.com",
          tenant_id: tenant.id
        })

      assert customer.external_id == "ext_001"
      assert customer.email == "alice@example.com"
      assert customer.tenant_id == tenant.id
    end

    test "create_customer enforces unique external_id per tenant" do
      tenant = insert(:tenant)
      Customers.create_customer(%{external_id: "dup", tenant_id: tenant.id})
      {:error, changeset} = Customers.create_customer(%{external_id: "dup", tenant_id: tenant.id})

      assert %{external_id: _} = errors_on(changeset)
    end

    test "get_customer_by_external_id finds customer" do
      customer = insert(:customer)
      found = Customers.get_customer_by_external_id(customer.tenant_id, customer.external_id)
      assert found.id == customer.id
    end

    test "list_customers returns tenant's customers" do
      tenant = insert(:tenant)
      insert(:customer, tenant: tenant)
      insert(:customer, tenant: tenant)

      customers = Customers.list_customers(tenant.id)
      assert length(customers) == 2
    end

    test "update_customer updates fields" do
      customer = insert(:customer)
      {:ok, updated} = Customers.update_customer(customer, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end

  describe "upsert" do
    test "upsert_customer creates when not found" do
      tenant = insert(:tenant)

      {:ok, customer} =
        Customers.upsert_customer(tenant.id, "new_ext", %{email: "new@example.com"})

      assert customer.external_id == "new_ext"
      assert customer.email == "new@example.com"
    end

    test "upsert_customer updates when found" do
      customer = insert(:customer, email: "old@example.com")

      {:ok, updated} =
        Customers.upsert_customer(customer.tenant_id, customer.external_id, %{
          email: "new@example.com"
        })

      assert updated.id == customer.id
      assert updated.email == "new@example.com"
    end
  end

  describe "tags" do
    test "add_tag adds to tags list" do
      customer = insert(:customer, tags: ["existing"])
      {:ok, updated} = Customers.add_tag(customer, "vip")
      assert "vip" in updated.tags
      assert "existing" in updated.tags
    end

    test "add_tag is idempotent" do
      customer = insert(:customer, tags: ["vip"])
      {:ok, updated} = Customers.add_tag(customer, "vip")
      assert updated.tags == ["vip"]
    end

    test "remove_tag removes from tags list" do
      customer = insert(:customer, tags: ["vip", "active"])
      {:ok, updated} = Customers.remove_tag(customer, "vip")
      assert updated.tags == ["active"]
    end

    test "add_tags adds multiple tags in one update" do
      customer = insert(:customer, tags: ["existing"])
      {:ok, updated} = Customers.add_tags(customer, ["vip", "beta", "existing"])
      assert updated.tags == ["existing", "vip", "beta"]
    end

    test "remove_tags removes multiple tags in one update" do
      customer = insert(:customer, tags: ["vip", "beta", "active"])
      {:ok, updated} = Customers.remove_tags(customer, ["vip", "beta", "missing"])
      assert updated.tags == ["active"]
    end
  end

  describe "properties validation" do
    test "accepts valid nested JSON properties" do
      attrs = %{
        "plan" => "pro",
        "score" => 42,
        "active" => true,
        "address" => %{"city" => "Tbilisi", "geo" => %{"lat" => 41.7, "lng" => 44.8}},
        "devices" => ["ios", "web"]
      }

      customer = insert(:customer)
      assert {:ok, updated} = Customers.update_customer(customer, %{properties: attrs})
      assert updated.properties["address"]["geo"]["lat"] == 41.7
    end

    test "rejects more than 100 top-level keys" do
      properties = Map.new(1..101, fn i -> {"key_#{i}", i} end)
      customer = insert(:customer)

      assert {:error, changeset} = Customers.update_customer(customer, %{properties: properties})
      assert %{properties: [message]} = errors_on(changeset)
      assert message =~ "at most 100"
    end

    test "rejects non-string keys" do
      customer = insert(:customer)

      assert {:error, changeset} =
               Customers.update_customer(customer, %{properties: %{123 => "x"}})

      assert %{properties: [message]} = errors_on(changeset)
      assert message =~ "keys must be strings"
    end

    test "rejects nesting deeper than 3 levels" do
      properties = %{"l1" => %{"l2" => %{"l3" => %{"l4" => 1}}}}
      customer = insert(:customer)

      assert {:error, changeset} = Customers.update_customer(customer, %{properties: properties})
      assert %{properties: [message]} = errors_on(changeset)
      assert message =~ "nested at most 3 levels"
    end

    test "rejects non-JSON values" do
      customer = insert(:customer)

      assert {:error, changeset} =
               Customers.update_customer(customer, %{
                 properties: %{"when" => ~U[2026-01-01 00:00:00Z]}
               })

      assert %{properties: [_message]} = errors_on(changeset)
    end

    test "rejects oversized payloads" do
      properties = %{"blob" => String.duplicate("x", 70_000)}
      customer = insert(:customer)

      assert {:error, changeset} = Customers.update_customer(customer, %{properties: properties})
      assert %{properties: [message]} = errors_on(changeset)
      assert message =~ "encoded size"
    end

    test "create_changeset also validates properties" do
      assert {:error, changeset} =
               Customers.create_customer(%{
                 external_id: "ext-1",
                 tenant_id: Ecto.UUID.generate(),
                 properties: %{123 => "x"}
               })

      assert %{properties: [_message]} = errors_on(changeset)
    end
  end

  describe "delete" do
    test "delete_customer removes the record" do
      customer = insert(:customer)
      assert {:ok, _} = Customers.delete_customer(customer)
      assert Customers.get_customer(customer.id) == nil
    end
  end

  describe "field_coverage/2" do
    test "returns 100% coverage for fields all customers have" do
      tenant = insert(:tenant)
      insert(:customer, tenant: tenant, email: "a@test.com")
      insert(:customer, tenant: tenant, email: "b@test.com")

      result = Customers.field_coverage(tenant.id, ["email"])
      assert result["email"] == 100.0
    end

    test "returns 0% coverage when no customers exist" do
      tenant = insert(:tenant)

      result = Customers.field_coverage(tenant.id, ["email"])
      assert result["email"] == 0.0
    end

    test "returns correct percentage for partially populated fields" do
      tenant = insert(:tenant)
      insert(:customer, tenant: tenant, email: "a@test.com", phone: "+1234")
      insert(:customer, tenant: tenant, email: "b@test.com", phone: nil)

      result = Customers.field_coverage(tenant.id, ["phone"])
      assert result["phone"] == 50.0
    end

    test "checks properties JSONB column for non-schema fields" do
      tenant = insert(:tenant)
      insert(:customer, tenant: tenant, properties: %{"plan" => "pro"})
      insert(:customer, tenant: tenant, properties: %{"plan" => "free"})
      insert(:customer, tenant: tenant, properties: %{})

      result = Customers.field_coverage(tenant.id, ["plan"])
      assert_in_delta result["plan"], 66.7, 0.1
    end

    test "handles multiple fields at once" do
      tenant = insert(:tenant)
      insert(:customer, tenant: tenant, email: "a@test.com", properties: %{"city" => "NYC"})
      insert(:customer, tenant: tenant, email: nil, properties: %{})

      result = Customers.field_coverage(tenant.id, ["email", "city"])
      assert result["email"] == 50.0
      assert result["city"] == 50.0
    end
  end

  describe "preferences" do
    test "update_preferences merges with existing" do
      customer = insert(:customer, preferences: %{"email" => true, "sms" => false})
      {:ok, updated} = Customers.update_preferences(customer, %{"sms" => true, "push" => false})
      assert updated.preferences == %{"email" => true, "sms" => true, "push" => false}
    end
  end
end
