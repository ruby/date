.SUFFIXES: .list

.list.h:
	gperf --ignore-case -L ANSI-C -C -c -P -p -j1 -i 1 -g -o -t -N $(*F) $< \
	| sed -f $(top_srcdir)/tool/gperf.sed \
	> $(@F)

zonetab.h: zonetab.list

.PHONY: update-zonetab
update-zonetab:
	$(RUBY) -C $(srcdir) update-abbr
	$(RUBY) -C $(srcdir) generate-zonetab-rb

.PHONY: update-nothing
update-nothing:

update = nothing

zonetab.list: update-$(update)
