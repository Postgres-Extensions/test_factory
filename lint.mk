# lint.mk — thin wrapper; the whole local footprint for consuming
# https://github.com/Postgres-Extensions/linter. Everything else lives in
# the .vendor/linter submodule; see its README for available targets/rules.
#
# Self-initializing (via the rule below) so `make lint` works right after a
# plain `git clone`, with no --recurse-submodules needed, and so CI can rely
# on the exact same entry point a developer would use locally.
#
# Guarded on .git existing: a source tarball (git archive, PGXN's own dist
# step) has no .git and no submodule content, so `git submodule update`
# fails outright ("fatal: not a git repository") -- and because Make tries
# to satisfy every `include` before doing anything else, for any target
# requested, an unconditional include here aborted EVERY make invocation
# (make, make install, everything), not just make lint, the moment a real
# consumer built from a distribution tarball rather than a git checkout.
# Confirmed by building a real `git archive` tarball into a clean directory
# with no .git at all and running a plain `make` there. Outside a real git
# checkout, lint support is simply unavailable; nothing else in the build
# needs it -- `make lint` there now fails with Make's own "no rule to make
# target" instead of `make`/`make install` failing too.
ifneq ($(wildcard .git),)
.vendor/linter/lint.mk:
	git submodule update --init -- .vendor/linter

include .vendor/linter/lint.mk
endif
