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

ActiveRecord::Schema.define(version: 2018_08_19_181111) do

  create_table "addresses", force: :cascade do |t|
    t.string "street"
    t.string "city"
    t.string "state"
    t.string "zip"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "child_models", force: :cascade do |t|
    t.string "child_attribute"
    t.integer "test_model_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "todo_id"
    t.integer "author_id"
    t.integer "user_id"
    t.integer "todo_item_id"
  end

  create_table "hyperstack_connections", force: :cascade do |t|
    t.string "channel"
    t.string "session"
    t.datetime "created_at"
    t.datetime "expires_at"
    t.datetime "refresh_at"
    t.index ["expires_at"], name: "index_hyperstack_connections_on_expires_at"
  end

  create_table "hyperstack_queued_messages", force: :cascade do |t|
    t.integer "connection_id"
    t.text "data"
    t.index ["connection_id"], name: "index_hyperstack_queued_messages_on_connection_id"
  end

  create_table "test_models", force: :cascade do |t|
    t.string "test_attribute"
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "todo_items", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.boolean "complete"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "user_id"
    t.integer "comment_id"
  end

  create_table "todos", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "completed", default: false, null: false
    t.integer "created_by_id"
    t.integer "owner_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "role"
    t.integer "manager_id"
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "address_street"
    t.string "address_city"
    t.string "address_state"
    t.string "address_zip"
    t.integer "address_id"
    t.string "address2_street"
    t.string "address2_city"
    t.string "address2_state"
    t.string "address2_zip"
    t.string "data_string"
    t.integer "data_times"
    t.integer "test_enum"
  end

end
