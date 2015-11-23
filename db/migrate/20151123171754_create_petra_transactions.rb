class CreatePetraTransactions < ActiveRecord::Migration
  def change
    create_table :petra_transactions do |t|

      t.timestamps null: false
    end
  end
end
