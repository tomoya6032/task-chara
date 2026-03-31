# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_03_30_234813) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.text "content"
    t.string "image_url"
    t.jsonb "ai_analysis_log"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.integer "mood_level"
    t.integer "fatigue_level"
    t.string "title"
    t.datetime "visit_start_time"
    t.datetime "visit_end_time"
    t.index ["character_id"], name: "index_activities_on_character_id"
  end

  create_table "ai_chats", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.string "conversation_id"
    t.string "role"
    t.text "content"
    t.integer "tokens_used"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_ai_chats_on_character_id"
    t.index ["conversation_id"], name: "index_ai_chats_on_conversation_id"
  end

  create_table "characters", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.integer "shave_level"
    t.integer "body_shape"
    t.integer "inner_peace"
    t.integer "intelligence"
    t.integer "toughness"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_sauna_at"
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "meeting_minutes", force: :cascade do |t|
    t.string "title"
    t.integer "meeting_type"
    t.datetime "meeting_date"
    t.text "content"
    t.text "participants"
    t.string "location"
    t.bigint "character_id", null: false
    t.integer "status"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "prompt_template_id"
    t.index ["character_id"], name: "index_meeting_minutes_on_character_id"
    t.index ["prompt_template_id"], name: "index_meeting_minutes_on_prompt_template_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "prompt_templates", force: :cascade do |t|
    t.string "name", null: false
    t.integer "meeting_type", null: false
    t.integer "prompt_type", null: false
    t.text "system_prompt", null: false
    t.text "user_prompt_template", null: false
    t.boolean "is_active", default: true, null: false
    t.integer "organization_id"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_prompt_templates_on_is_active"
    t.index ["meeting_type", "prompt_type", "is_active"], name: "idx_on_meeting_type_prompt_type_is_active_6c738d814c"
    t.index ["organization_id"], name: "index_prompt_templates_on_organization_id"
  end

  create_table "report_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "format_instructions"
    t.boolean "is_default", default: false
    t.bigint "user_id"
    t.string "pdf_file_name"
    t.integer "pdf_file_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_default"], name: "index_report_templates_on_is_default"
    t.index ["user_id"], name: "index_report_templates_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "support_reports", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.string "title"
    t.date "period_start"
    t.date "period_end"
    t.text "content"
    t.datetime "generated_at"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "report_template_id"
    t.index ["character_id"], name: "index_support_reports_on_character_id"
    t.index ["report_template_id"], name: "index_support_reports_on_report_template_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.string "title"
    t.string "category"
    t.integer "dislike_level"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hidden"
    t.datetime "hidden_at"
    t.datetime "due_date"
    t.index ["character_id"], name: "index_tasks_on_character_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.bigint "organization_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "characters"
  add_foreign_key "ai_chats", "characters"
  add_foreign_key "characters", "users"
  add_foreign_key "meeting_minutes", "characters"
  add_foreign_key "meeting_minutes", "prompt_templates"
  add_foreign_key "report_templates", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "support_reports", "characters"
  add_foreign_key "support_reports", "report_templates"
  add_foreign_key "tasks", "characters"
  add_foreign_key "users", "organizations"
end
