# This migration comes from petra (originally 20151123171754)
class CreatePetraTransactions < ActiveRecord::Migration
  def change
    create_table :petra_transactions do |t|
      t.string :identifier, :null => false
      t.timestamps null: false
    end

    # Ensure that a transaction identifier is unique
    add_index :petra_transactions, :identifier, :unique => true
  end
end
