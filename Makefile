include pgxntool/base.mk

# Explicit rather than relying on base.mk's auto-detection of test/build/*.sql
# files, so an accidental deletion of test/build/'s contents is a loud error
# instead of silently disabling this check.
PGXNTOOL_ENABLE_TEST_BUILD = yes

# Hook for test to ensure dependencies in control file are set correctly
testdeps: check_control

.PHONY: check_control
check_control:
	grep -q "requires = 'pgtap, test_factory'" test_factory_pgtap.control

# Style linter (see https://github.com/Postgres-Extensions/linter, vendored
# at .vendor/linter -- lint.mk is the thin local hand-off, see its comment).
include lint.mk
