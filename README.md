has_many_through_redis
======================

Manage has_many_through relationships in Redis.


Simply delcare relationships has following:

Foo.rb

include RedisRelation

has_many_through_redis :bars

has_many_through_redis :attendees, reverse: :attending, class_name: :User


and create your relationships has following:

f = Foo.first

b = Bar.last

f.bars << b

f.bars # returns [b]

f.bar_ids # returns [b.id]

f.bars.remove(b)

f.bars # returns []
