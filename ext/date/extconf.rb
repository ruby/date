# frozen_string_literal: true
require 'mkmf'

if RUBY_VERSION >= "3.3"
  # Pure Ruby implementation; skip C extension build
  File.write("Makefile", dummy_makefile($srcdir).join(""))
else
  config_string("strict_warnflags") {|w| $warnflags += " #{w}"}
  append_cflags("-Wno-compound-token-split-by-macro") if RUBY_VERSION < "2.7."
  have_func("rb_category_warn")
  with_werror("", {:werror => true}) do |opt, |
    have_var("timezone", "time.h", opt)
    have_var("altzone", "time.h", opt)
  end
  create_makefile('date_core')
end
