load 'setup/undefine.rb'

require 'delayed_job_active_record'

ActiveRecord::Schema.define(:version => 1) do
  create_table :articles do |t|
    t.string :title
    t.integer :num_read, :default => 0
    t.datetime :created_at, :default => 'NOW()'
  end

  create_table :delayed_jobs, :force => true do |table|
    table.integer  :priority, :default => 0
    table.integer  :attempts, :default => 0
    table.text     :handler
    table.text     :last_error
    table.datetime :run_at
    table.datetime :locked_at
    table.datetime :failed_at
    table.string   :locked_by
    table.string   :queue
    table.timestamps
  end
end

Delayed::Worker.delay_jobs = false

class ::Article < ActiveRecord::Base
end

Article.delete_all

::Article.create! title: 'Test', num_read: 1
::Article.create! title: 'Testing Coding'
::Article.create! title: 'Coding'
