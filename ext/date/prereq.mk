.PHONY: update-zonetab
update-zonetab:
	$(RUBY) -C $(srcdir) update-abbr
	$(RUBY) -C $(top_srcdir) ext/date/generate-zonetab-rb ext/date/zonetab.list lib/date/zonetab.rb

.PHONY: update-nothing
update-nothing:

update = nothing

zonetab.list: update-$(update)
