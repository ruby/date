require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/test_*.rb']
end

require 'rake/extensiontask'
Rake::ExtensionTask.new("date") do |ext|
  ext.name = "date_core"
end

task :default => [:compile, :test]
