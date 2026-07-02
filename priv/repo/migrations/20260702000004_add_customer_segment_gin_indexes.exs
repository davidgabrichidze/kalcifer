defmodule Kalcifer.Repo.Migrations.AddCustomerSegmentGinIndexes do
  use Ecto.Migration

  @moduledoc """
  GIN indexes for dynamic-segment evaluation (SegmentQuery), which filters
  customers by tag membership and JSONB property containment/existence.

  - tags (text[]) → GIN serves `tags @> ARRAY[...]` (the "contains" rule).
  - properties (jsonb) → default GIN opclass serves both `@>` containment
    ("eq"/"neq"/"in") and the `?`/jsonb_exists operator ("exists").

  Without these, member listing and counting for a segment fell back to a
  sequential scan of every customer in the tenant.
  """

  def change do
    create index(:customers, [:tags], using: :gin, name: :customers_tags_gin)

    create index(:customers, [:properties], using: :gin, name: :customers_properties_gin)
  end
end
