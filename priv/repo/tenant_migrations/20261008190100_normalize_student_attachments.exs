defmodule Amauta.Repo.TenantMigrations.NormalizeStudentAttachments do
  use Ecto.Migration

  # Cursos creados con un build que todavía no conocía el ajuste
  # `student_attachments` lo guardaron en `null`: vale el valor por defecto.
  def up do
    execute("""
    UPDATE #{prefix()}.courses
    SET settings = jsonb_set(settings::jsonb, '{student_attachments}', 'true')
    WHERE settings::jsonb -> 'student_attachments' IS NULL
       OR settings::jsonb -> 'student_attachments' = 'null'::jsonb
    """)
  end

  def down, do: :ok
end
