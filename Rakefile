require "bundler/gem_tasks"
require "rake/testtask"

if RUBY_VERSION >= "3.3"
  # Pure Ruby — no compilation needed
  Rake::TestTask.new(:test) do |t|
    t.libs << "lib"
    t.libs << "test/lib"
    t.ruby_opts << "-rhelper"
    t.test_files = FileList['test/**/test_*.rb']
  end

  task :compile  # no-op

else
  # C extension for Ruby < 3.3
  require "shellwords"
  require "rake/extensiontask"

  extask = Rake::ExtensionTask.new("date") do |ext|
    ext.name = "date_core"
    ext.lib_dir.sub!(%r[(?=/|\z)], "/#{RUBY_VERSION}/#{ext.platform}")
  end

  Rake::TestTask.new(:test) do |t|
    t.libs << extask.lib_dir
    t.libs << "test/lib"
    t.ruby_opts << "-rhelper"
    t.test_files = FileList['test/**/test_*.rb']
  end

  task test: :compile

  task compile: "ext/date/zonetab.h"
  file "ext/date/zonetab.h" => "ext/date/zonetab.list" do |t|
    dir, hdr = File.split(t.name)
    make_program_name =
      ENV['MAKE'] || ENV['make'] ||
      RbConfig::CONFIG['configure_args'][/with-make-prog\=\K\w+/] ||
      (/mswin/ =~ RUBY_PLATFORM ? 'nmake' : 'make')
    make_program = Shellwords.split(make_program_name)
    sh(*make_program, "-f", "prereq.mk", "top_srcdir=.."+"/.."*dir.count("/"),
       hdr, chdir: dir)
  end
end

task :default => [:compile, :test]
