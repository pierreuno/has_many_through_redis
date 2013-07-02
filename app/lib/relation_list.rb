# http://www.ruby-doc.org/stdlib-1.9.3/libdoc/delegate/rdoc/SimpleDelegator.html
class RelationsList < SimpleDelegator
  def initialize(assoc, relation_name, reversed_relation_name, klass, find_objects=false)
    @assoc                  = assoc
    @klass                  = klass
    @relation_name          = relation_name 
    @reversed_relation_name = reversed_relation_name 
    @assoc_class            = @assoc.is_a?(Class) ? @assoc : @assoc.class

    @key_prefix = defined?(@assoc.redis_prefix) ? @assoc.redis_prefix : ""

    # dont need this any more now that test env runs on a different Redis DB
    # @key_prefix = "Test_" + @key_prefix if Rails.env.test?

    if find_objects
      super(_relations_list)
    end
  end

  def my_ids 
    unless @assoc.is_a?(Class)
      # puts "Getting: #{_key}"
      ids = $redis.exists(_key) ? $redis.smembers(_key) : []
    end
  end

  def _relations_list
    ids = self.my_ids
    ids.present? ? @klass.find_all_by_id(ids) : []
  end

  def _key
    "#{@key_prefix}:#{@assoc_class.name}#{@assoc.is_a?(Integer) ? @assoc : @assoc.id}:#{@relation_name}"
  end

  def _reversed_key(e, relation_name)
    "#{@key_prefix }:#{@klass.name}#{e.is_a?(Integer) ? e : e.id}:#{relation_name}"
  end

  def _get_count_key
    @relation_name[-3, 3] == "ing" ? @reversed_relation_name : @relation_name
  end

  # allows you to set an array of ids for this relation
  # e.g. user.followers.set([1,2,3]) or user.followers.set([])
  # gets aliased via redis_relation so that you can do user.followers = [1,2,3]
  # NOTE: is actually not a whole lot different from <<(u) below
  def set(ids)
    # reset 
    self.destroy

    unless ids.blank?
      result = $redis.multi do
        # puts "Adding: #{_key}, #{ids}"
        $redis.sadd(_key, ids)
        ids.each do |id|
          # puts "and Adding: #{_reversed_key(id, @reversed_relation_name)}, #{@assoc.id}"
          $redis.sadd(_reversed_key(id, @reversed_relation_name), @assoc.id)
        end
      end
      _cache_set(@assoc, ids, true) if result[0]
      result[0] ? ids : result[0]
    end
  end


  def <<(u)
    id = (u.is_a? Integer) ? u : u.id
    result = $redis.multi do
      # puts "Adding: #{_key}, #{id}"
      $redis.sadd(_key, id)
      # puts "and Adding: #{_reversed_key(u, @reversed_relation_name)}, #{@assoc.id}"
      $redis.sadd(_reversed_key(u, @reversed_relation_name), @assoc.id)
    end
    _cache(@assoc, u) if result[0]
    result[0] ? u : result[0]
  end

  # remove member 'u' from this relation_list
  def remove(u)
    id = (u.is_a? Integer) ? u : u.id    
    result = $redis.multi do
      # remove the member from the list
      # puts "Removing: #{_key}, #{id}"
      $redis.srem(_key, id)
      # puts "and Removing: #{_reversed_key(u, @reversed_relation_name)}, #{@assoc.id}"
      $redis.srem(_reversed_key(u, @reversed_relation_name), @assoc.id)
    end
    _cache(@assoc, u, false) if result[0]
    result[0]
  end

  # destroy this relation_list altogether (e.g. if I destroy Tag99, I want to destroy the "Tag99<->events" relation)
  # and remove Tag99 from each of its events
  def destroy
    # id = (u.is_a? Integer) ? u : u.id    
    ids = $redis.exists(_key) ? $redis.smembers(_key) : false
    result = $redis.multi do
      if ids
        ids.each do |id|
          id = id.to_i
          # puts "REMOVING: #{_reversed_key(id, @reversed_relation_name)}, #{@assoc.id}"
          $redis.srem(_reversed_key(id, @reversed_relation_name), @assoc.id)
        end
      end
      # puts "DELETING: #{_key}"
      $redis.del(_key)

    end
    # handle caching after destroy!!!
    _cache_set(@assoc, ids, true) if ids and result[0]
    result[0]
  end

  # cache the count for the addition or removal of entity1 <-> entity2
  def _cache(entity1, entity2, incr=true)
    incr_val = incr ? 1 : -1
    $redis.multi do 
      {_cache_key => entity1, _reversed_cache_key => entity2}.each do |key, entity|
        entity_id = entity.is_a?(Integer) ? entity : entity.id
        $redis.zincrby(key, incr_val, entity_id)
      end
    end
  end

  # cache the count for the addition or removal of entity1 <-> [ids]
  def _cache_set(entity, ids, destroy=false)
    incr_val = destroy ? -1 : 1
    id_count = destroy ? 0 : ids.count
    $redis.multi do
      $redis.zadd(_cache_key, id_count, @assoc)
      ids.each do |id|
        $redis.zincrby(_reversed_cache_key, incr_val, id)
      end
    end
  end


  def _cache_key
    "#{@key_prefix}#{@assoc_class.name}#{@klass.name}#{@relation_name}"
  end

  def _reversed_cache_key
    "#{@key_prefix}#{@klass.name}#{@assoc_class.name}#{@reversed_relation_name}"
  end

  # used when calling as_json
  def serializable_hash(params)
    self
  end

  def 

  def count
    $redis.scard _key
  end

  def order_by_count
    $redis.zrevrangebyscore _cache_key, "+inf", "-inf"
  end

  def include?(e)
    id = (e.is_a? Integer) ? e : e.id
    $redis.sismember _key, id
  end
end

class UserRelationsList < RelationsList
  def initialize(assoc, relation_name, reversed_relation_name)
    super(assoc, relation_name, reversed_relation_name, User)
  end
end