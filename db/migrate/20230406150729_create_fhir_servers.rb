class CreateFhirServers < ActiveRecord::Migration[7.0]
  def change
    create_table :fhir_servers do |t|
      t.string :name
      t.string :base_url

      t.timestamps
    end
    add_index :fhir_servers, :base_url, unique: true
  end
end
