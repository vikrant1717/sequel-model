require 'uri'

require File.join(File.dirname(__FILE__), 'schema')
require File.join(File.dirname(__FILE__), 'dataset')
require File.join(File.dirname(__FILE__), 'model')

module Sequel
  # A Database object represents a virtual connection to a database.
  # The Database class is meant to be subclassed by database adapters in order
  # to provide the functionality needed for executing queries.
  class Database
    attr_reader :opts, :pool, :logger
    
    # Constructs a new instance of a database connection with the specified
    # options hash.
    #
    # Sequel::Database is an abstract class that is not useful by itself.
    def initialize(opts = {}, &block)
      Model.database_opened(self)
      @opts = opts
      @pool = ConnectionPool.new(@opts[:max_connections] || 4, &block)
      @logger = opts[:logger]
      @pool.connection_proc = block || proc {connect}
    end
    
    def connect
      true # we can't return nil or false, because then pool will block forever
    end
    
    def uri
      uri = URI::Generic.new(
        self.class.adapter_scheme.to_s,
        nil,
        @opts[:host],
        @opts[:port],
        nil,
        "/#{@opts[:database]}",
        nil,
        nil,
        nil
      )
      uri.user = @opts[:user]
      uri.password = @opts[:password]
      uri.to_s
    end
    alias url uri # Because I don't care much for the semantic difference.
    
    # Returns a blank dataset
    def dataset
      Dataset.new(self)
    end

    # Returns a new dataset with the from method invoked.
    def from(*args); dataset.from(*args); end
    
    # Returns a new dataset with the select method invoked.
    def select(*args); dataset.select(*args); end
    
    alias_method :[], :from

    def execute(sql)
      raise NotImplementedError
    end
    
    # Executes the supplied SQL. The SQL can be supplied as a string or as an
    # array of strings. Comments and excessive white space are removed. See
    # also Array#to_sql.
    def <<(sql); execute(sql.to_sql); end
    
    # Acquires a database connection, yielding it to the passed block.
    def synchronize(&block)
      @pool.hold(&block)
    end

    # Returns true if there is a database connection
    def test_connection
      @pool.hold {|conn|}
      true
    end
    
    # Creates a table. The easiest way to use this method is to provide a
    # block:
    #   DB.create_table :posts do
    #     primary_key :id, :serial
    #     column :title, :text
    #     column :content, :text
    #     index :title
    #   end
    def create_table(name, &block)
      schema = Schema.new
      schema.create_table(name, &block)
      schema.create(self)
    end
    
    # Drops a table.
    def drop_table(*names)
      transaction do
        execute(names.map {|n| Schema.drop_table_sql(n)}.join)
      end
    end
    
    # Performs a brute-force check for the existance of a table. This method is
    # usually overriden in descendants.
    def table_exists?(name)
      if respond_to?(:tables)
        tables.include?(name.to_sym)
      else
        from(name).first && true
      end
    rescue
      false
    end
    
    SQL_BEGIN = 'BEGIN'.freeze
    SQL_COMMIT = 'COMMIT'.freeze
    SQL_ROLLBACK = 'ROLLBACK'.freeze

    # A simple implementation of SQL transactions. Nested transactions are not 
    # supported - calling #transaction within a transaction will reuse the 
    # current transaction. May be overridden for databases that support nested 
    # transactions.
    def transaction
      @pool.hold do |conn|
        @transactions ||= []
        if @transactions.include? Thread.current
          return yield(conn)
        end
        conn.execute(SQL_BEGIN)
        begin
          @transactions << Thread.current
          result = yield(conn)
          conn.execute(SQL_COMMIT)
          result
        rescue => e
          conn.execute(SQL_ROLLBACK)
          raise e
        ensure
          @transactions.delete(Thread.current)
        end
      end
    end
    
    @@adapters = Hash.new
    
    # Sets the adapter scheme for the Database class. Call this method in
    # descendnants of Database to allow connection using a URL. For example the
    # following:
    #   class DB2::Database < Sequel::Database
    #     set_adapter_scheme :db2
    #     ...
    #   end
    # would allow connection using:
    #   Sequel.open('db2://user:password@dbserver/mydb')
    def self.set_adapter_scheme(scheme)
      @scheme = scheme
      @@adapters[scheme.to_sym] = self
    end
    
    # Returns the scheme for the Database class.
    def self.adapter_scheme
      @scheme
    end
    
    # Converts a uri to an options hash. These options are then passed
    # to a newly created database object.
    def self.uri_to_options(uri)
      {
        :user => uri.user,
        :password => uri.password,
        :host => uri.host,
        :port => uri.port,
        :database => (uri.path =~ /\/(.*)/) && ($1)
      }
    end
    
    # call-seq:
    #   Sequel::Database.connect(conn_string)
    #   Sequel.connect(conn_string)
    #   Sequel.open(conn_string)
    #
    # Creates a new database object based on the supplied connection string.
    # The specified scheme determines the database class used, and the rest
    # of the string specifies the connection options. For example:
    #   DB = Sequel.open 'sqlite:///blog.db'
    def self.connect(conn_string, more_opts = nil)
      uri = URI.parse(conn_string)
      c = @@adapters[uri.scheme.to_sym]
      raise SequelError, "Invalid database scheme" unless c
      c.new(c.uri_to_options(uri).merge(more_opts || {}))
    end
  end
end

