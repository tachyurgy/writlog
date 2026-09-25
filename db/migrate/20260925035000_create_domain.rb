class CreateDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :matters do |t|
      t.string  :reference, null: false
      t.string  :client_name, null: false
      t.string  :debtor_name, null: false
      t.string  :debtor_address
      t.string  :guarantor_name
      t.string  :county, null: false, default: "Nassau"
      t.string  :index_number
      t.bigint  :principal_cents, null: false, default: 0
      t.bigint  :paid_cents, null: false, default: 0
      t.bigint  :judgment_cents
      # Projection of the event log. Never written except by Workflow.
      t.string  :state, null: false, default: "intake"
      t.integer :events_count, null: false, default: 0
      t.date    :last_event_on
      t.string  :service_method
      t.date    :served_on
      t.date    :answer_due_on
      t.date    :default_judgment_deadline_on
      t.date    :judgment_entered_on
      t.date    :restraint_expires_on
      t.date    :next_deadline_on
      t.string  :next_deadline_label
      t.timestamps
    end
    add_index :matters, :reference, unique: true
    add_index :matters, :next_deadline_on

    create_table :matter_events do |t|
      t.references :matter, null: false, foreign_key: true
      t.integer :seq, null: false
      t.string  :kind, null: false
      t.date    :effective_on, null: false
      t.jsonb   :payload, null: false, default: {}
      t.string  :from_state, null: false
      t.string  :to_state, null: false
      t.string  :actor, null: false, default: "system"
      t.datetime :created_at, null: false
    end
    # Gap-free, per-matter ordering. The Workflow takes a row lock on the matter
    # before computing seq; this index is the backstop.
    add_index :matter_events, [:matter_id, :seq], unique: true
    # A generated document is recorded on the log exactly once.
    add_index :matter_events, "matter_id, ((payload->>'document_id'))", unique: true,
              where: "kind = 'document_generated'", name: "index_matter_events_one_per_document"

    reversible do |dir|
      dir.up do
        # Append-only at the database level, not just in the model.
        execute <<~SQL
          CREATE FUNCTION matter_events_append_only() RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'matter_events is append-only (% rejected)', TG_OP;
          END;
          $$ LANGUAGE plpgsql;
          CREATE TRIGGER matter_events_no_update_delete
            BEFORE UPDATE OR DELETE ON matter_events
            FOR EACH ROW EXECUTE FUNCTION matter_events_append_only();
        SQL
      end
      dir.down do
        execute "DROP TRIGGER IF EXISTS matter_events_no_update_delete ON matter_events"
        execute "DROP FUNCTION IF EXISTS matter_events_append_only()"
      end
    end

    create_table :document_templates do |t|
      t.string  :key, null: false
      t.integer :version, null: false
      t.string  :name, null: false
      t.string  :description
      t.text    :body, null: false
      t.timestamps
    end
    add_index :document_templates, [:key, :version], unique: true

    create_table :generated_documents do |t|
      t.references :matter, null: false, foreign_key: true
      t.references :document_template, null: false, foreign_key: true
      t.string  :template_key, null: false
      t.integer :template_version, null: false
      t.integer :version, null: false
      t.string  :inputs_digest, null: false
      t.jsonb   :inputs, null: false, default: {}
      t.string  :status, null: false, default: "pending"
      t.text    :rendered_html
      t.text    :error
      t.integer :attempts, null: false, default: 0
      t.datetime :generated_at
      t.timestamps
    end
    # THE idempotency guarantee: one document per matter + template version + inputs.
    add_index :generated_documents, [:matter_id, :document_template_id, :inputs_digest],
              unique: true, name: "index_generated_documents_idempotency"
    add_index :generated_documents, [:matter_id, :template_key, :version], unique: true,
              name: "index_generated_documents_version"

    create_table :communications do |t|
      t.references :matter, null: false, foreign_key: true
      t.references :generated_document, foreign_key: true
      t.string :channel, null: false
      t.string :direction, null: false
      t.string :counterparty, null: false
      t.string :subject, null: false
      t.text   :body
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :communications, [:matter_id, :occurred_at]
  end
end
