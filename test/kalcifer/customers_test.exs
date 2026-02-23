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
  end

  describe "preferences" do
    test "update_preferences merges with existing" do
      customer = insert(:customer, preferences: %{"email" => true, "sms" => false})
      {:ok, updated} = Customers.update_preferences(customer, %{"sms" => true, "push" => false})
      assert updated.preferences == %{"email" => true, "sms" => true, "push" => false}
    end
  end
end
