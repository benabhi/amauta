defmodule Amauta.Repo.TenantMigrations.RichTextPathwayDescription do
  use Ecto.Migration

  # La descripción del trayecto pasa a contenido enriquecido (RF-CON-003,
  # ERS 8.13): el documento del editor en jsonb. El texto que ya había se
  # convierte en un párrafo.
  def up do
    execute("""
    ALTER TABLE #{prefix()}.pathways
    ALTER COLUMN description TYPE jsonb
    USING CASE
      WHEN description IS NULL OR btrim(description) = '' THEN NULL
      ELSE jsonb_build_object(
        'type', 'doc',
        'content', jsonb_build_array(jsonb_build_object(
          'type', 'paragraph',
          'content', jsonb_build_array(jsonb_build_object('type', 'text', 'text', description))
        ))
      )
    END
    """)
  end

  def down do
    execute("""
    ALTER TABLE #{prefix()}.pathways
    ALTER COLUMN description TYPE text
    USING jsonb_path_query_first(description, '$.**.text') #>> '{}'
    """)
  end
end
