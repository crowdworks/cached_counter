# CachedCounter

[![Build Status](https://travis-ci.org/crowdworks/cached_counter.svg?branch=master)](https://travis-ci.org/crowdworks/cached_counter)
[![Coverage Status](https://coveralls.io/repos/crowdworks/cached_counter/badge.svg?branch=master)](https://coveralls.io/r/crowdworks/cached_counter?branch=master)
[![Code Climate](https://codeclimate.com/github/crowdworks/cached_counter/badges/gpa.svg)](https://codeclimate.com/github/crowdworks/cached_counter)

Cache Counter is an instantaneous but lock-friendly implementation of the counter.

It allows to increment/decrement/get counts primarily saved in the database in a faster way.
Utilizing the cache, it can be updated without big row-locks like the ActiveRecord's update_counters,
with instantaneous and consistency unlike the updated_counters within delayed, background jobs.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cached_counter'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cached_counter

## Usage

```ruby
# When you use the counter backed by Memcached via Dalli
require 'dalli'
require' cache_store'

# Give the Cached Counter the name of the Cache Store and options you want to pass.
# The built-in DalliCacheStore is named `:dalli` and accepts the `:hosts` option which is an array of Memcached hosts
# you want Dalli connect to.
CachedCounter.cache_store :dalli, hosts: %w| 127.0.0.1 |

# We have an integer column named `num_read` in the `articles` table.
article = Article.first

# Give Cached Counter the record which has an attribute containing the initial value of the counter.
cached_counter = CachedCounter.create(record: article, attribute: :num_read)

article.num_read
#=> 0
cached_counter.value
#=> 0

# The value of the counter is updated immediately,
# and a background job is scheduled to eventually update the value of the counter persisted in the database.
cached_counter.increment

# You can see the incremented value in the cache immediately
cached_counter.value
#=> 1

# But not yet in the database
article.reload.num_read
#=> 0

# When the scheduled background job is finished,
# you can also see the incremented value in the database, too.
article.reload.num_read
#=> 1
```


## Contributing

1. Fork it ( https://github.com/crowdworks/cached_counter/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
