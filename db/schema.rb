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

ActiveRecord::Schema[8.0].define(version: 2026_02_09_084418) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.text "content"
    t.string "image_url"
    t.jsonb "ai_analysis_log"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_activities_on_character_id"
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
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["character_id"], name: "index_tasks_on_character_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.bigint "organization_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "activities", "characters"
  add_foreign_key "characters", "users"
  add_foreign_key "tasks", "characters"
  add_foreign_key "users", "organizations"
end
