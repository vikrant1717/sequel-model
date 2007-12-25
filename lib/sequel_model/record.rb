module Sequel
  class Model
    attr_reader :values
    attr_reader :changed_columns

    # Returns value of attribute.
    def [](column)
      @values[column]
    end
    # Sets value of attribute and marks the column as changed.
    def []=(column, value)
      @values[column] = value
      @changed_columns << column unless @changed_columns.include?(column)
    end

    # Enumerates through all attributes.
    #
    # === Example:
    #   Ticket.find(7).each { |k, v| puts "#{k} => #{v}" }
    def each(&block)
      @values.each(&block)
    end
    # Returns attribute names.
    def keys
      @values.keys
    end

    # Returns value for <tt>:id</tt> attribute.
    def id
      @values[:id]
    end

    # Compares model instances by values.
    def ==(obj)
      (obj.class == model) && (obj.values == @values)
    end

    # Compares model instances by pkey.
    def ===(obj)
      (obj.class == model) && (obj.pk == pk)
    end

    # Returns key for primary key.
    def self.primary_key
      :id
    end
    
    # Returns primary key attribute hash.
    def self.primary_key_hash(value)
      {:id => value}
    end
    
    # Sets primary key, regular and composite are possible.
    #
    # == Example:
    #   class Tagging < Sequel::Model(:taggins)
    #     # composite key
    #     set_primary_key :taggable_id, :tag_id
    #   end
    #
    #   class Person < Sequel::Model(:person)
    #     # regular key
    #     set_primary_key :person_id
    #   end
    #
    # <i>You can even set it to nil!</i>
    def self.set_primary_key(*key)
      # if k is nil, we go to no_primary_key
      if key.empty? || (key.size == 1 && key.first == nil)
        return no_primary_key
      end
      
      # backwards compat
      key = (key.length == 1) ? key[0] : key.flatten

      # redefine primary_key
      meta_def(:primary_key) {key}
      
      unless key.is_a? Array # regular primary key
        class_def(:this) do
          @this ||= dataset.filter(key => @values[key]).limit(1).naked
        end
        class_def(:pk) do
          @pk ||= @values[key]
        end
        class_def(:pk_hash) do
          @pk ||= {key => @values[key]}
        end
        class_def(:cache_key) do
          pk = @values[key] || (raise Error, 'no primary key for this record')
          @cache_key ||= "#{self.class}:#{pk}"
        end
        meta_def(:primary_key_hash) do |v|
          {key => v}
        end
      else # composite key
        exp_list = key.map {|k| "#{k.inspect} => @values[#{k.inspect}]"}
        block = eval("proc {@this ||= self.class.dataset.filter(#{exp_list.join(',')}).limit(1).naked}")
        class_def(:this, &block)
        
        exp_list = key.map {|k| "@values[#{k.inspect}]"}
        block = eval("proc {@pk ||= [#{exp_list.join(',')}]}")
        class_def(:pk, &block)
        
        exp_list = key.map {|k| "#{k.inspect} => @values[#{k.inspect}]"}
        block = eval("proc {@this ||= {#{exp_list.join(',')}}}")
        class_def(:pk_hash, &block)
        
        exp_list = key.map {|k| '#{@values[%s]}' % k.inspect}.join(',')
        block = eval('proc {@cache_key ||= "#{self.class}:%s"}' % exp_list)
        class_def(:cache_key, &block)

        meta_def(:primary_key_hash) do |v|
          key.inject({}) {|m, i| m[i] = v.shift; m}
        end
      end
    end
    
    def self.no_primary_key #:nodoc:
      meta_def(:primary_key) {nil}
      meta_def(:primary_key_hash) {|v| raise Error, "#{self} does not have a primary key"}
      class_def(:this)      {raise Error, "No primary key is associated with this model"}
      class_def(:pk)        {raise Error, "No primary key is associated with this model"}
      class_def(:pk_hash)   {raise Error, "No primary key is associated with this model"}
      class_def(:cache_key) {raise Error, "No primary key is associated with this model"}
    end
    
    # Creates new instance with values set to passed-in Hash ensuring that
    # new? returns true.
    def self.create(values = {})
      db.transaction do
        obj = new(values, true)
        obj.save
        obj
      end
    end
    
    class << self
      def create_with_params(params)
        create(params.reject {|k, v| !columns.include?(k.to_sym)})
      end
      alias_method :create_with, :create_with_params
    end
    
    # Returns (naked) dataset bound to current instance.
    def this
      @this ||= self.class.dataset.filter(:id => @values[:id]).limit(1).naked
    end
    
    # Returns a key unique to the underlying record for caching
    def cache_key
      pk = @values[:id] || (raise Error, 'no primary key for this record')
      @cache_key ||= "#{self.class}:#{pk}"
    end

    # Returns primary key column(s) for object's Model class.
    def primary_key
      @primary_key ||= self.class.primary_key
    end
    
    # Returns value for primary key.
    def pkey
      warn "Model#pkey is deprecated. Please use Model#pk instead."
      @pkey ||= @values[self.class.primary_key]
    end
    
    # Returns the primary key value identifying the model instance. Stock implementation.
    def pk
      @pk ||= @values[:id]
    end
    
    # Returns a hash identifying the model instance. Stock implementation.
    def pk_hash
      @pk_hash ||= {:id => @values[:id]}
    end
    
    # Creates new instance with values set to passed-in Hash.
    #
    # This method guesses whether the record exists when
    # <tt>new_record</tt> is set to false.
    def initialize(values = {}, new_record = false, &block)
      @values = values
      @changed_columns = []

      @new = new_record
      unless @new # determine if it's a new record
        k = self.class.primary_key
        # if there's no primary key for the model class, or
        # @values doesn't contain a primary key value, then 
        # we regard this instance as new.
        @new = (k == nil) || (!(Array === k) && !@values[k])
      end
      
      block[self] if block
    end
    
    # Returns true if the current instance represents a new record.
    def new?
      @new
    end
    alias :new_record? :new?
    
    # Returns true when current instance exists, false otherwise.
    def exists?
      this.count > 0
    end
    
    # Creates or updates the associated record. This method can also
    # accept a list of specific columns to update.
    def save(*columns)
      run_hooks(:before_save)
      if @new
        run_hooks(:before_create)
        iid = model.dataset.insert(@values)
        # if we have a regular primary key and it's not set in @values,
        # we assume it's the last inserted id
        if (pk = primary_key) && !(Array === pk) && !@values[pk]
          @values[pk] = iid
        end
        if pk
          @this = nil # remove memoized this dataset
          refresh
        end
        @new = false
        run_hooks(:after_create)
      else
        run_hooks(:before_update)
        if columns.empty?
          this.update(@values)
          @changed_columns = []
        else # update only the specified columns
          this.update(@values.reject {|k, v| !columns.include?(k)})
          @changed_columns.reject! {|c| columns.include?(c)}
        end
        run_hooks(:after_update)
      end
      run_hooks(:after_save)
      self
    end
    
    # Saves only changed columns or does nothing if no columns are marked as 
    # chanaged.
    def save_changes
      save(*@changed_columns) unless @changed_columns.empty?
    end

    # Updates and saves values to database from the passed-in Hash.
    def set(values)
      this.update(values)
      values.each {|k, v| @values[k] = v}
    end
    alias_method :update, :set
    
    # Reloads values from database and returns self.
    def refresh
      @values = this.first || raise(Error, "Record not found")
      self
    end

    # Like delete but runs hooks before and after delete.
    def destroy
      db.transaction do
        run_hooks(:before_destroy)
        delete
        run_hooks(:after_destroy)
      end
    end
    
    # Deletes and returns self.
    def delete
      this.delete
      self
    end
    
    ATTR_RE = /^([a-zA-Z_]\w*)(=)?$/.freeze

    def method_missing(m, *args) #:nodoc:
      if m.to_s =~ ATTR_RE
        att = $1.to_sym
        write = $2 == '='
        
        # check whether the column is legal
        unless columns.include?(att)
          # if read accessor and a value exists for the column, we return it
          if !write && @values.has_key?(att)
            return @values[att]
          end
          
          # otherwise, raise an error
          raise Error, "Invalid column (#{att.inspect}) for #{self}"
        end

        # define the column accessor
        Thread.exclusive do
          if write
            model.class_def(m) {|v| self[att] = v}
          else
            model.class_def(m) {self[att]}
          end
        end
        
        # call the accessor
        respond_to?(m) ? send(m, *args) : super(m, *args)
      else
        super(m, *args)
      end
    end
  end
end