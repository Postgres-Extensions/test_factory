include pgxntool/base.mk

# Explicit rather than relying on base.mk's auto-detection of test/build/*.sql
# files, so an accidental deletion of test/build/'s contents is a loud error
# instead of silently disabling this check.
PGXNTOOL_ENABLE_TEST_BUILD = yes

PGXNTOOL_ENABLE_TEST_INSTALL = yes

# ------------------------------------------------------------------------------
# TEST_LOAD_SOURCE: how test/install/load.sql gets the extension to its
# target state (fresh/update/existing). See test/install/load.sql for what
# each mode actually does.
# ------------------------------------------------------------------------------
TEST_LOAD_SOURCE ?= fresh
ifeq ($(filter $(TEST_LOAD_SOURCE),fresh update existing),)
$(error TEST_LOAD_SOURCE must be 'fresh', 'update' or 'existing', got '$(TEST_LOAD_SOURCE)')
endif

# Only meaningful in 'update' mode; empty TO means "update to current".
TEST_UPDATE_FROM ?= 0.5.0
TEST_UPDATE_TO ?=

# Export unconditionally -- load.sql must never treat "absent" as "fresh".
export PGOPTIONS := $(PGOPTIONS) -c test_factory.test_load_mode=$(TEST_LOAD_SOURCE) -c test_factory.test_update_from=$(TEST_UPDATE_FROM) -c test_factory.test_update_to=$(TEST_UPDATE_TO)

# make test-update: convenience wrapper. Must re-invoke $(MAKE) (not just
# depend on test) so the parse-time TEST_LOAD_SOURCE validation above
# re-evaluates for the child invocation.
.PHONY: test-update
test-update:
	$(MAKE) test TEST_LOAD_SOURCE=update

# Hook for test to ensure dependencies in control file are set correctly
testdeps: check_control

.PHONY: check_control
check_control:
	grep -q "requires = 'pgtap, test_factory'" test_factory_pgtap.control

# Style linter (see https://github.com/Postgres-Extensions/linter, vendored
# at .vendor/linter -- lint.mk is the thin local hand-off, see its comment).
include lint.mk
