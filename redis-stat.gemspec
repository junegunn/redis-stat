# -*- encoding: utf-8 -*-
require File.expand_path('../lib/redis-stat/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Junegunn Choi"]
  gem.email         = ["junegunn.c@gmail.com"]
  gem.description   = %q{A command-line Redis monitoring tool}
  gem.summary       = %q{A command-line Redis monitoring tool}
  gem.homepage      = "https://github.com/junegunn/redis-stat"

  gem.files         = `git ls-files`.split("\n").reject { |f| f =~ /^screenshots/ }
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "redis-stat"
  gem.require_paths = ["lib"]
  gem.version       = RedisStat::VERSION

  gem.add_runtime_dependency "ansi", '~> 1.4.3'
  gem.add_runtime_dependency "redis", '~> 3.0.1'
  gem.add_runtime_dependency "tabularize", '~> 0.2.8'
  gem.add_runtime_dependency "insensitive_hash", '~> 0.3.0'
  gem.add_runtime_dependency "parallelize", '~> 0.4.0'

  gem.add_development_dependency 'test-unit'
end
