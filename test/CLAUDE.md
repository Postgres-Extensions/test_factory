# Test Framework Documentation

This file provides guidance for understanding and working with the test_factory extension test suite.

## Test Framework Overview

The test_factory extension uses **pgTAP** (PostgreSQL's unit testing framework) for comprehensive testing. Tests are organized using PGXNtool's standardized testing infrastructure.

## Test Structure

### Test Files
- `test/sql/base.sql` - Core functionality tests (22 tests)
- `test/sql/pgtap.sql` - pgTAP integration and `tf.tap()` function tests
- `test/build/syntax.sql` - Runs the actual source SQL files (`sql/test_factory.sql`,
  `sql/test_factory_pgtap.sql` -- the ones a developer edits, NOT the
  pgxntool-generated `sql/*--VERSION.sql` copies) directly via `\i`, to catch
  SQL syntax errors with a clearer error than a `CREATE EXTENSION` failure
  would give. This is the *only* file `test/build` is for: running extension
  scripts "bare" for better error context. Its results are always thrown
  away (unlike `test/install`, which is intended to commit and persist) --
  packaging checks (dependency declarations, clean install/uninstall) belong
  in `test/install/load.sql` instead, not here.

### Expected Results
- `test/expected/*.out` - Expected test output for regression testing
- `test/results/*.out` - Actual test output (generated during test runs)

### Test Helpers
- `test/helpers/setup.sql` - Test environment initialization and pgTAP setup
- `test/helpers/create.sql` - Test data registration and security validation
- `test/helpers/deps.sql` - Test dependency management (`\i`'s `test/roles.sql`)
- `test/roles.sql` - Single source of truth for test-only role names
- Other helper files for role management and pgTAP integration

## Load Modes (`TEST_LOAD_SOURCE`)

`test/install/load.sql` runs once, committed, before the regular test files
(pgxntool's `PGXNTOOL_ENABLE_TEST_INSTALL` feature), so its state survives
into every test file. It is the *only* place that knows how the extension
gets onto the system -- `test/sql/base.sql` and `test/sql/pgtap.sql` always
assume both extensions are already installed, in every mode, and are
otherwise identical regardless of which mode ran. `TEST_LOAD_SOURCE`
(default `fresh`) picks how the extension gets to its target state:

- **fresh** (default) - drops both extensions first (so a re-run against a
  non-fresh dev DB starts clean), lands `pgtap` in a dedicated `tap` schema,
  then `CREATE EXTENSION test_factory_pgtap CASCADE` (proving
  `test_factory_pgtap.control`'s `requires` line actually pulls
  `test_factory` in).
- **update** - `CREATE EXTENSION test_factory VERSION :from` then
  `ALTER EXTENSION UPDATE` (`TEST_UPDATE_FROM`/`TEST_UPDATE_TO` make vars),
  then installs `test_factory_pgtap` at current (it has only ever shipped
  one version, so there's no update path of its own to exercise yet -- the
  mechanism exists for when a second version ships, but no CI job drives it
  yet). `make test-update` is a shorthand for `make test
  TEST_LOAD_SOURCE=update`.
- **existing** - the extension is already installed (a real `pg_upgrade`
  target, or an out-of-band update) -- `load.sql` only asserts it's present
  at the current version, plants a dependency guard (see below), and
  proves it; never drops/creates/updates anything.

  Run against a real pre-existing install with:
  ```
  make test TEST_LOAD_SOURCE=existing CONTRIB_TESTDB=<db> \
    EXTRA_REGRESS_OPTS=--use-existing PGXNTOOL_ENABLE_TEST_BUILD=no
  ```

All three modes leave the system in the same observable end state (both
extensions installed, `pgtap` in schema `tap`), so `base.sql`/`pgtap.sql`
and their expected output are shared across all of them -- no
per-mode alternate expected files.

### Non-superuser installer (`test_factory_installer`)

Connecting as a superuser (CI's default, and most developers' local setup)
bypasses every role-membership check involved in
https://github.com/Postgres-Extensions/test_factory/issues/14's fix
(`pg_has_role(current_user, 'test_factory__owner', ...)` is unconditionally
true for a superuser). Asserting that property from `base.sql` while
staying connected as a superuser would prove nothing about whether the fix
works -- it's true either way.

Rather than running the whole suite a second time as a separate disposable
role (which would only prove what's already implied: a superuser can do
anything a properly-privileged non-superuser can), `load.sql`'s own
fresh/update branch creates a non-login `test_factory_installer` role
(`CREATEROLE` only -- the exact privilege floor `CREATE EXTENSION` needs,
paired with `CREATE` granted on the test database) and switches to it with
`SET SESSION AUTHORIZATION` before running `CREATE EXTENSION`/`ALTER
EXTENSION UPDATE`. No separate login, password, or CI job needed: the
switch only affects `load.sql`'s own already-authenticated session, and
every mode this suite runs in (superuser CI, a developer's local
superuser) ends up exercising the exact same non-superuser install path.

### Dependency Guard

Planted only in `existing` mode (see `load.sql`): a view in schema
`test_factory_drop_guard` depending on `tf.tap(text,text)` blocks a
non-CASCADE `DROP EXTENSION test_factory_pgtap`. `test_factory` itself
doesn't need an artificial guard -- `test_factory_pgtap`'s own control file
(`requires = 'pgtap, test_factory'`) already blocks a non-CASCADE
`DROP EXTENSION test_factory` as long as `test_factory_pgtap` is installed;
`load.sql` proves that natural protection too. The point of the guard: in
`existing` mode, nothing else stops a stray drop (or a logic bug that falls
through to the fresh/update branch) from silently destroying the real
upgraded/updated objects this mode exists to test.

## Test Coverage Analysis

### Core Functionality Tests (`base.sql`)
Assumes both extensions are already installed (by `test/install/load.sql`,
in every mode) and test tables not yet created:
1. **Data Registration** - Tests `tf.register()` with multiple test sets
2. **Basic Retrieval** - Tests `tf.get()` returns correct data
3. **Dependency Resolution** - Tests automatic creation of dependent data (customer → invoice)
4. **Caching Behavior** - Verifies data consistency across multiple `tf.get()` calls  
5. **Table Independence** - Tests that cached data persists after source table changes
6. **Function-based Test Data** - Tests using functions as test data sources

### Security Tests (`create.sql`)
- **Security Definer Functions** - Ensures all privileged functions use `search_path=pg_catalog`
- **Permission Isolation** - Tests with unprivileged `test_role`
- **Temp Table Cleanup** - Verifies temporary installation objects are removed

Role-restore verification (does `CREATE EXTENSION` correctly restore the
calling role?) lives in `test/install/load.sql` instead, where `CREATE
EXTENSION` actually runs.

### Raw SQL Syntax Tests (`test/build/syntax.sql`)
- Runs `sql/test_factory.sql` and `sql/test_factory_pgtap.sql` (the actual
  source files, not the generated `sql/*--VERSION.sql` copies) directly via
  `\i` (not `CREATE EXTENSION`), so a genuine syntax error is reported
  clearly instead of being obscured by a generic CREATE EXTENSION failure.
- See the comments in that file for the known/expected errors baked into its
  expected output (`pg_extension_config_dump()` and `SET ROLE ""`), which are
  artifacts of running the file outside of CREATE EXTENSION, not bugs.
- This is the *only* thing `test/build` is for: running extension scripts
  "bare" for better error context. Its results are always thrown away
  (unlike `test/install`, which is intended to commit and persist).
  Packaging checks (dependency declarations, clean install) belong in
  `test/install/load.sql` instead.

### pgTAP Integration Tests (`pgtap.sql`)
- **Dependency Enforcement** - Confirms `test_factory_pgtap.control`'s
  `requires = 'pgtap, test_factory'` line is real and enforced by Postgres,
  via a `pg_depend` extension-requires-extension edge (`deptype = 'n'`),
  not just documentation. Checking final catalog state this way works
  uniformly in every `TEST_LOAD_SOURCE` mode.
- **tf.tap() Function** - Tests pgTAP wrapper functionality
- **Error Handling** - Tests proper error reporting for invalid inputs

## Test Data Model

### Test Tables
```sql
CREATE TABLE customer(
    customer_id   serial  PRIMARY KEY,
    first_name    text    NOT NULL, 
    last_name     text    NOT NULL
);

CREATE TABLE invoice(
    invoice_id      serial  PRIMARY KEY,
    customer_id     int     NOT NULL REFERENCES customer,
    invoice_date    date    NOT NULL,
    due_date        date
);
```

### Test Data Sets
- **customer 'insert'** - Simple INSERT statement returning customer data
- **customer 'function'** - Function-based test data creation  
- **invoice 'base'** - Invoice with dependency on customer 'insert' set

## Running Tests

### Basic Test Execution
```bash
make test              # Full test suite with clean install
make installcheck      # Run tests against already installed extension
```

### Test Development Workflow
```bash
# Make changes to test files
vim test/sql/base.sql

# Run tests to verify
make test

# If tests pass but output differs, update expected results
make results
```

### Test Debugging
- Test output appears in `test/results/`
- Differences shown in `test/regression.diffs` if tests fail
- Use `\set ECHO all` in test SQL files for detailed debugging

## Test Architecture Details

### pgTAP Integration
- Tests use pgTAP assertion functions: `is()`, `results_eq()`, `bag_eq()`, `lives_ok()`
- `no_plan()` allows dynamic test counting
- Tests run in transactions with automatic rollback

### Security Testing Strategy
- Creates unprivileged `test_role` to validate security boundaries
- Tests run with restricted permissions to catch privilege escalation issues
- Validates all security definer functions use safe search_path settings

### Dependency Testing
- Tests multi-level dependencies (invoice → customer)
- Validates data creation order and consistency
- Tests that dependency data is created automatically and cached

### Error Condition Testing
- Tests invalid table names and missing test sets
- Validates proper error messages and SQL state codes
- Tests edge cases like non-existent tables in tf.tap()

## Test Data Lifecycle

1. **Setup Phase** - Creates test role, schemas, and tables
2. **Registration Phase** - Registers test data definitions  
3. **Execution Phase** - Calls tf.get() to trigger data creation
4. **Validation Phase** - Verifies data correctness and caching behavior
5. **Cleanup Phase** - Transaction rollback removes all test data

This comprehensive test suite ensures the test_factory extension works correctly across different PostgreSQL versions and usage patterns, with particular attention to security and data integrity.