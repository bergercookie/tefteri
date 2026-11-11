"""stop mirroring the note app: drop the copies that sync made

Revision ID: 0017
Revises: 0016
"""

from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Sync used to copy every note of the note app (kind "custom") and listed the root note and
    # its children as containers. Nothing reads them: tefteri now reads and writes only the notes
    # it needs. A note that a task link or a review points at was named by tefteri (daily or
    # retrospective) and stays.
    op.execute(
        """
        DELETE FROM notes
        WHERE kind = 'custom'
          AND NOT EXISTS (SELECT 1 FROM task_note_links l WHERE l.note_id = notes.id)
          AND NOT EXISTS (SELECT 1 FROM period_reviews r WHERE r.retrospective_note_id = notes.id)
        """
    )
    op.execute(
        """
        DELETE FROM source_containers
        WHERE connection_id IN (SELECT id FROM connections WHERE kind = 'notes')
        """
    )


def downgrade() -> None:
    # The copies were a cache of the note app: the next sync of an older version makes them again.
    pass
