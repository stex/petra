class CreatePetraActiveRecordLocks < ActiveRecord::Migration
  def change
    create_table :petra_active_record_locks, :id => false do |t|
      t.primary_key :name, :string, :limit => 100
      t.timestamps null: false
    end
  end
end
