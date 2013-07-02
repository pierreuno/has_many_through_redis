module RedisRelation
  extend ActiveSupport::Concern
  # example:
  # Event.rb
  # include RedisRelation
  # has_many_through_redis :tags
  # has_many_through_redis :attendees, reverse: :attending, class_name: :User

  included do
    class_attribute :redis_relations
    after_destroy :remove_from_redis
  end

  module ClassMethods
    def has_many_through_redis(relation, opts={})    
      klass   = opts[:class_name].nil? ? relation.to_s.classify.constantize  : opts[:class_name].to_s.classify.constantize
      reverse = opts[:reverse].nil?    ? self.to_s.downcase.pluralize.to_sym : opts[:reverse]
      
      # define the method, e.g. "tags", so we can do event.tags
      define_method relation do
        # RelationsList.new(self=Tag, relation=events, reverse=tags, klass=Event)
        RelationsList.new(self, relation, reverse, klass, true)
      end      

      # define the method, e.g. "tags=", so we can do event.tag_ids = [1,2,3]
      define_method "#{relation.to_s.singularize}_ids="  do |ids|
        # RelationsList.new(self=Tag, relation=events, reverse=tags, klass=Event)
        RelationsList.new(self, relation, reverse, klass).set(ids)
      end      

      # define the method for calling just the ids, e.g. "tag_ids"
      define_method "#{relation.to_s.singularize}_ids" do
        RelationsList.new(self, relation, reverse, klass).my_ids
      end

      self.redis_relations ||= []
      self.redis_relations.push(relation)
    end
  end


  def remove_from_redis
    self.class.redis_relations.each do |r| 
      # calling destroy on the redis_relation actually empties it, e.g. user.followers.destroy means user.followers = []
      self.send(r).destroy
    end
  end

end
