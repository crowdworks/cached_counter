require "cached_counter/version"

class CachedCounter
  attr_reader :model_class, :attribute, :id

  class ConcurrentCacheWriteError < StandardError; end

  # @param [#call] cache_key The proc which takes the single argument of the class inheriting ActiveRecord::Base and returns a cache key
  # @return [#call]
  def self.cache_key(cache_key=nil)
    if cache_key
      @cache_key = cache_key
    else
      @cache_key ||= -> c { "#{c.model_class.model_name.cache_key}/#{c.attribute}/cached_counter/#{c.id}" }
    end
  end

  # @param [#call] cache_store
  # @return [CacheStore::Base]
  def self.cache_store(cache_store=nil, *args, **options)
    if cache_store
      @cache_store = builder_for_cache_store(cache_store, *args, **options)
    else
      @cache_store
    end
  end

  # @param [Proc]
  def self.builder_for_cache_store(cache_store, *args, **options)
    case cache_store
    when Symbol
      klass = cache_store_class_for_symbol(cache_store)
      -> { klass.create(*args, **options) }
    when Class
      -> { cache_store.create(*args, **options)}
    when Proc
      cache_store
    else
      -> { cache_store }
    end
  end

  # @param [Symbol] symbol
  def self.cache_store_class_for_symbol(symbol)
    const_get CacheStore.name + '::' + symbol.to_s.split('_').map(&:capitalize).join + 'CacheStore'
  end

  # @param [ActiveRecord::Base] record
  # @param [Symbol] attribute
  def self.create(record:, attribute:, cache_store: nil)
    new(model_class: record.class, id: record.id, attribute: attribute, cache_store: cache_store)
  end

  def initialize(model_class:, id:, attribute:, cache_store: nil)
    @model_class = model_class
    @attribute = attribute
    @id = id
    @cache_store = cache_store
  end

  # Increment the specified attribute of the record utilizing the cache not to lock the table row as long as possible
  def increment
    cache_updated_successfully =
      with_cache_store do |store|
        begin
          store.incr(cache_key) ||
            # When the key doesn't exit in the cache because of cache expirations/clean-ups/restarts
            store.add(cache_key, value_in_db + 1) ||
            # In rare cases, the value for the key is updated by other client and we have to fail immediately, not to
            # run into race-conditions.
            raise(ConcurrentCacheWriteError, "Failing not to enter a race condition while writing a value for the key #{cache_key}")
        rescue store.error_class => e
          false
        end
      end

    begin
      if cache_updated_successfully
        # When this database transaction failed afterward, we have to rollback the incrementation by decrementing
        # the value in the cached.
        # Without the rollback, we'll fall into an inconsistent state between the database and the cache.
        on_error_rollback_by(:decrement_in_cache)

        # As we have successfully incremented the value in the cache, we can rely on the cache in order to
        # get/show the latest value.
        # Therefore, we have no need to update the database record in realtime and we can achieve
        # incrementing the counter with a little row-lock.
        increment_in_db_later
      else
        # The cache service seems to be down, but we don't want to stop the application service.
        # That's why we fall back to increment the value in the database which requires a bigger row-lock.
        increment_in_db
      end
    rescue => e
      raise e
    end
  end

  def value
    begin
      cache_store.get(cache_key).try(&:to_i)
    rescue cache_store.error_class => e
      nil
    end || value_in_db
  end

  # Decrement the specified attribute of the record utilizing the cache not to lock the table row as long as possible
  def decrement
    cache_updated_successfully =
      with_cache_store do |store|
        begin
          store.decr(cache_key) ||
            store.add(cache_key, value_in_db - 1) ||
            raise(ConcurrentCacheWriteError, "Failing not to enter a race condition while writing a value for the key #{cache_key}")
        rescue store.error_class => e
          false
        end
      end

    begin
      if cache_updated_successfully
        on_error_rollback_by(:increment_in_cache)

        decrement_in_db_later
      else
        decrement_in_db
      end
    rescue => e
      raise e
    end
  end

  def value_in_db
    @model_class.find(@id).send(@attribute)
  end

  def invalidate_cache
    cache_store.delete(cache_key)
  end

  def increment_in_cache
    with_cache_store do |d|
      d.incr(cache_key)
    end
  end

  def increment_in_db
    @model_class.increment_counter(@attribute, @id)
  end

  def increment_in_db_later
    call_method_later(:increment_in_db)
  end

  def decrement_in_cache
    with_cache_store do |d|
      d.decr(cache_key)
    end
  end

  def decrement_in_db
    @model_class.decrement_counter(@attribute, @id)
  end

  def decrement_in_db_later
    call_method_later(:decrement_in_db)
  end

  # @return [String]
  def cache_key
    self.class.cache_key.call(self)
  end

  private

  # @return [CacheStore::Base]
  def cache_store
    @cache_store ||= self.class.cache_store.call
  end

  def with_cache_store
    yield cache_store
  end

  # @param [Symbol] method
  def call_method_later(method)
    CachedCounter::RetriedJob.new(
      model_class: @model_class,
      id: @id,
      attribute: @attribute,
      method: method
    ).enqueue!
  end

  # @param [Symbol] method
  def on_error_rollback_by(method)
    listener = CachedCounter::RollbackByMethodCallListener.new(
      model_class: @model_class,
      id: @id,
      attribute: @attribute,
      method: method
    )

    # @see https://github.com/rails/rails/blob/v3.2.18/activerecord/lib/active_record/connection_adapters/abstract/database_statements.rb#L242
    # @see https://github.com/rails/rails/blob/v4.1.4/activerecord/lib/active_record/connection_adapters/abstract/database_statements.rb#L248
    # @see https://github.com/rails/rails/blob/v5.2.2/activerecord/lib/active_record/connection_adapters/abstract/database_statements.rb#L279
    @model_class.connection.add_transaction_record(listener)
  end

  class RetriedJob
    def initialize(model_class:, id:, attribute:, method:)
      @model_class = model_class
      @id = id
      @attribute = attribute
      @method = method
    end

    def perform
      CachedCounter.new(model_class: @model_class, id: @id, attribute: @attribute).send(@method)
    end

    def max_attempts
      10
    end

    def enqueue!
      Delayed::Job.enqueue self
    end
  end

  class RollbackByMethodCallListener
    def initialize(model_class:, id:, attribute:, method:)
      @model_class = model_class
      @id = id
      @attribute = attribute
      @method = method
    end

    # called only when Rails is 4+
    # Without this method implemented, you will see `undefined method `has_transactional_callbacks?' for #<CachedCounter::RollbackByMethodCallListener:0x007f5af749cd80>`
    # when the listener is passed to `#add_transaction_record`
    # @see Rails 4: https://github.com/rails/rails/blob/v4.1.4/activerecord/lib/active_record/connection_adapters/abstract/transaction.rb#L125
    def has_transactional_callbacks?
      true
    end

    # @see Rails 3: https://github.com/rails/rails/blob/v3.2.18/activerecord/lib/active_record/connection_adapters/abstract/database_statements.rb#L372
    # @see Rails 4: https://github.com/rails/rails/blob/v4.1.4/activerecord/lib/active_record/connection_adapters/abstract/transaction.rb#L147
    def committed!
      nil
    end

    def before_committed!
      nil
    end

    # @see ActiveRecord::Transactions::rolledback!
    # @see Rails 3: https://github.com/rails/rails/blob/v3.2.18/activerecord/lib/active_record/connection_adapters/abstract/database_statements.rb#L357
    # @see Rails 4: https://github.com/rails/rails/blob/v4.1.4/activerecord/lib/active_record/connection_adapters/abstract/transaction.rb#L136
    def rolledback!(force_restore_state = false)
      CachedCounter.new(model_class: @model_class, id: @id, attribute: @attribute).send(@method)
    end
  end

  module CacheStore
    class Base
      def incr(key); fail_with_not_implemented_error 'incr' end
      def decr(key); fail_with_not_implemented_error 'decr' end
      def add(key, value); fail_with_not_implemented_error 'add' end
      def delete(key); fail_with_not_implemented_error 'delete' end
      def error_class; fail_with_not_implemented_error 'incr' end

      private

      def fail_with_not_implemented_error(method_name)
        fail ::CacheStore::Base::NotImplementedError, "#{self.class.name}##{method_name} must be implemented."
      end

      class NotImplementedError < StandardError; end
    end

    class DalliCacheStore < Base
      # @param [Dalli::Client] dalli_client
      def initialize(dalli_client)
        @dalli_client = dalli_client
      end

      def self.create(options={})
        opts = options.dup
        hosts = opts.delete(:hosts)
        new(Dalli::Client.new(hosts, opts))
      end

      def incr(key)
        @dalli_client.incr(key)
      end

      def decr(key)
        @dalli_client.decr(key)
      end

      def add(key, value)
        @dalli_client.add(key, value, 0, raw: true)
      end

      def get(key)
        @dalli_client.get(key)
      end

      def delete(key)
        @dalli_client.delete(key)
      end

      def error_class
        Dalli::RingError
      end
    end
  end
end
