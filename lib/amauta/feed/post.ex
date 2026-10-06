defmodule Amauta.Feed.Post do
  @moduledoc "Publicación del tablón de un curso."
  use Ash.Resource,
    otp_app: :amauta,
    domain: Amauta.Feed,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshJsonApi.Resource]

  alias Amauta.Authorization.Checks.{CoursePermissionFilter, HasCoursePermission}
  alias Amauta.Catalog.RequireCourse

  json_api do
    type "post"
    includes [:author]
    default_fields [:body, :course_id, :author_id, :inserted_at]
  end

  postgres do
    table "posts"
    repo Amauta.Repo

    references do
      reference :course, on_delete: :delete
      reference :author, on_delete: :nothing
    end

    custom_indexes do
      index [:course_id, :inserted_at]
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "Lista las publicaciones del tablón de un curso."
      argument :course_id, :uuid, allow_nil?: false
      filter expr(course_id == ^arg(:course_id))
      prepare build(sort: [inserted_at: :desc], load: [:author])
      prepare RequireCourse.Preparation
      pagination keyset?: true, required?: false
    end

    create :create do
      description "Publica en el tablón de un curso."
      primary? true
      accept [:body]
      argument :course_id, :uuid, allow_nil?: false

      change set_attribute(:course_id, arg(:course_id))
      change RequireCourse.Change

      change fn
        changeset, %{actor: %Amauta.Scope{user: %{id: user_id}}} ->
          Ash.Changeset.force_change_attribute(changeset, :author_id, user_id)

        changeset, _context ->
          changeset
      end

      change Amauta.Audit.Record
      change load(:author)
    end
  end

  policies do
    policy action(:read) do
      authorize_if {CoursePermissionFilter, permission: "course.view"}
    end

    policy action(:list) do
      # Estricto: sin permiso es 403, no una lista vacía.
      access_type :strict
      authorize_if {HasCoursePermission, permission: "course.view"}
    end

    policy action(:create) do
      authorize_if {HasCoursePermission, permission: "course.feed.post"}
    end
  end

  pub_sub do
    module Amauta.PubSub.Ash
    prefix "feed"
    publish :create, [:_tenant, :course_id]
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints max_length: 10_000, trim?: true, allow_empty?: false
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :course, Amauta.Catalog.Course, allow_nil?: false, public?: true
    belongs_to :author, Amauta.Accounts.User, allow_nil?: false, public?: true
  end
end
