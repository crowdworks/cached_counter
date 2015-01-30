# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cached_counter/version'

Gem::Specification.new do |spec|
  spec.name          = "cached_counter"
  spec.version       = CachedCounter::VERSION
  spec.authors       = ["Yusuke KUOKA"]
  spec.email         = ["ykuoka@gmail.com"]
  spec.summary       = %q{An instantaneous but lock-friendly implementation of the counter}
  spec.description   = %q{Cached Counter allows to increment/decrement/get counts primarily saved in the database in a faster way. Utilizing the cache, it can be updated without big row-locks like the ActiveRecord's update_counters, with instantaneous and consistency unlike the updated_counters within delayed, background jobs}
  spec.homepage      = "https://github.com/crowdworks/cached_counter"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
end
