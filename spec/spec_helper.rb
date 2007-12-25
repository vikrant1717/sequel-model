require 'rubygems'
require File.join(File.dirname(__FILE__), "../lib/sequel_model") 

class MockDataset < Sequel::Dataset
  def insert(*args)
    @db.execute insert_sql(*args)
  end
  
  def update(*args)
    @db.execute update_sql(*args)
  end
  
  def fetch_rows(sql)
    @db.execute(sql)
    yield({:id => 1, :x => 1})
  end
end

class MockDatabase < Sequel::Database
  attr_reader :sqls
  
  def execute(sql)
    @sqls ||= []
    @sqls << sql
  end

  def reset
    @sqls = []
  end

  def transaction; yield; end
  
  def dataset; MockDataset.new(self); end
end

Sequel::Model.db = MODEL_DB = MockDatabase.new