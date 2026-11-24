source 'https://rubygems.org'

# The java gem is an empty placeholder, and lib/date.rb would shadow JRuby's own date
gemspec unless RUBY_ENGINE == 'jruby'

group :development do
  gem "bundler"
  gem "rake"
  gem "rake-compiler"
  gem "test-unit"
  gem "test-unit-ruby-core", ">= 1.0.7"
end
