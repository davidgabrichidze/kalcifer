defmodule Kalcifer.Customers.SegmentQueryTest do
  use Kalcifer.DataCase, async: true

  import Kalcifer.Factory

  alias Kalcifer.Customers

  setup do
    tenant = insert(:tenant)

    anna =
      insert(:customer,
        tenant: tenant,
        email: "anna@acme.com",
        name: "Anna",
        tags: ["vip", "beta"],
        properties: %{"plan" => "pro", "score" => 80, "city" => "Tbilisi"}
      )

    beka =
      insert(:customer,
        tenant: tenant,
        email: "beka@other.io",
        name: "Beka",
        tags: ["beta"],
        properties: %{"plan" => "free", "score" => 10}
      )

    nino =
      insert(:customer,
        tenant: tenant,
        email: nil,
        name: "Nino",
        tags: [],
        properties: %{}
      )

    {:ok, tenant: tenant, anna: anna, beka: beka, nino: nino}
  end

  defp member_ids(tenant, rules) do
    segment = insert(:segment, tenant: tenant, rules: rules)

    segment
    |> Customers.list_segment_members()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  test "eq on top-level column", %{tenant: tenant, anna: anna} do
    rules = [%{"field" => "email", "operator" => "eq", "value" => "anna@acme.com"}]
    assert member_ids(tenant, rules) == [anna.id]
  end

  test "neq on top-level column includes customers with NULL", ctx do
    rules = [%{"field" => "email", "operator" => "neq", "value" => "anna@acme.com"}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.beka.id, ctx.nino.id])
  end

  test "contains on top-level column", %{tenant: tenant, anna: anna} do
    rules = [%{"field" => "email", "operator" => "contains", "value" => "acme"}]
    assert member_ids(tenant, rules) == [anna.id]
  end

  test "in / not_in on top-level column", ctx do
    rules = [%{"field" => "name", "operator" => "in", "value" => ["Anna", "Nino"]}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.anna.id, ctx.nino.id])

    rules = [%{"field" => "name", "operator" => "not_in", "value" => ["Anna"]}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.beka.id, ctx.nino.id])
  end

  test "exists / not_exists on top-level column", ctx do
    rules = [%{"field" => "email", "operator" => "exists"}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.anna.id, ctx.beka.id])

    rules = [%{"field" => "email", "operator" => "not_exists"}]
    assert member_ids(ctx.tenant, rules) == [ctx.nino.id]
  end

  test "tags contains", %{tenant: tenant, anna: anna} do
    rules = [%{"field" => "tags", "operator" => "contains", "value" => "vip"}]
    assert member_ids(tenant, rules) == [anna.id]
  end

  test "eq on properties string and number", ctx do
    rules = [%{"field" => "plan", "operator" => "eq", "value" => "pro"}]
    assert member_ids(ctx.tenant, rules) == [ctx.anna.id]

    rules = [%{"field" => "score", "operator" => "eq", "value" => 10}]
    assert member_ids(ctx.tenant, rules) == [ctx.beka.id]
  end

  test "neq on properties includes customers missing the field", ctx do
    rules = [%{"field" => "plan", "operator" => "neq", "value" => "pro"}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.beka.id, ctx.nino.id])
  end

  test "gt / lt on numeric properties", ctx do
    rules = [%{"field" => "score", "operator" => "gt", "value" => 50}]
    assert member_ids(ctx.tenant, rules) == [ctx.anna.id]

    rules = [%{"field" => "score", "operator" => "lt", "value" => 50}]
    assert member_ids(ctx.tenant, rules) == [ctx.beka.id]
  end

  test "contains on properties string", ctx do
    rules = [%{"field" => "city", "operator" => "contains", "value" => "bili"}]
    assert member_ids(ctx.tenant, rules) == [ctx.anna.id]
  end

  test "in / not_in on properties", ctx do
    rules = [%{"field" => "plan", "operator" => "in", "value" => ["pro", "enterprise"]}]
    assert member_ids(ctx.tenant, rules) == [ctx.anna.id]

    rules = [%{"field" => "plan", "operator" => "not_in", "value" => ["pro"]}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.beka.id, ctx.nino.id])
  end

  test "exists / not_exists on properties", ctx do
    rules = [%{"field" => "city", "operator" => "exists"}]
    assert member_ids(ctx.tenant, rules) == [ctx.anna.id]

    rules = [%{"field" => "city", "operator" => "not_exists"}]
    assert member_ids(ctx.tenant, rules) == Enum.sort([ctx.beka.id, ctx.nino.id])
  end

  test "multiple rules are ANDed", ctx do
    rules = [
      %{"field" => "tags", "operator" => "contains", "value" => "beta"},
      %{"field" => "score", "operator" => "gt", "value" => 50}
    ]

    assert member_ids(ctx.tenant, rules) == [ctx.anna.id]
  end

  test "empty rules match all tenant customers, scoped by tenant", ctx do
    insert(:customer)

    assert member_ids(ctx.tenant, []) ==
             Enum.sort([ctx.anna.id, ctx.beka.id, ctx.nino.id])
  end

  test "malformed or unknown-operator rules match nothing", ctx do
    assert member_ids(ctx.tenant, [%{"bogus" => true}]) == []

    assert member_ids(ctx.tenant, [%{"field" => "plan", "operator" => "regex", "value" => "x"}]) ==
             []
  end

  test "count_segment_members counts at the database level", ctx do
    segment =
      insert(:segment,
        tenant: ctx.tenant,
        rules: [%{"field" => "tags", "operator" => "contains", "value" => "beta"}]
      )

    assert Customers.count_segment_members(segment) == 2
  end

  test "SQL wildcard characters in contains are escaped", ctx do
    rules = [%{"field" => "email", "operator" => "contains", "value" => "%"}]
    assert member_ids(ctx.tenant, rules) == []
  end
end
