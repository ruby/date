require "bundler/gem_tasks"
require "rake/testtask"

# Pure Ruby — no compilation needed
Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test/lib"
  t.ruby_opts << "-rhelper"
  t.test_files = FileList['test/**/test_*.rb']
end

task :compile  # no-op, kept for compatibility

task :default => [:compile, :test]
