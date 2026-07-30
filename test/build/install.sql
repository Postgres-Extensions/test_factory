\set ECHO none
\i test/helpers/psql.sql

/*
 * Extension packaging/install-mechanics checks.
 *
 * These verify that the extension *packaging* is correct (control file
 * dependency declarations, clean install/uninstall) -- not test_factory's
 * actual business logic (registering/getting test data; that's covered by
 * test/sql/base.sql and test/sql/pgtap.sql). This lives in test/build
 * because that's exactly what pgxntool's test/build feature is for. Quoting
 * pgxntool/base.mk's own comment on the purpose of test/build:
 *
 *   Validates that extension SQL files are syntactically correct by running
 *   files from test/build/ through pg_regress. This provides better error
 *   messages than CREATE EXTENSION failures.
 *
 * test/build runs in an isolated database with none of the main suite's
 * test/helpers/setup.sql machinery (no pgTAP, no roles, no --dbname), so
 * this file uses plain SQL and lets pg_regress's classic expected-output
 * diffing do the comparison instead of pgTAP assertions.
 *
 * The one intentional error below (the bare CREATE EXTENSION) is expected to
 * abort only its own statement, not the rest of this script, since psql runs
 * each top-level statement as its own autocommit transaction by default. We
 * still disable ON_ERROR_STOP (which test/helpers/psql.sql just turned on)
 * to make that reliance explicit rather than depending on pg_regress's own
 * default.
 *
 * We also dial VERBOSITY back down from psql.sql's "verbose" to "default":
 * verbose mode appends a LOCATION line with the triggering backend C source
 * file/line for every error, which differs across PG major versions (and
 * even between builds of the same version) -- fine for interactive
 * debugging, but it would make this file's expected output impossible to
 * match across the PG12/PG17 matrix this repo tests against.
 */
\set ON_ERROR_STOP false
\set VERBOSITY default

SET client_min_messages = WARNING;

-- pgtap is a declared dependency of test_factory_pgtap too. Install it up
-- front so the bare-create failure below isolates specifically on
-- test_factory being missing, not on pgtap also being missing (test/build's
-- database doesn't have pgtap pre-installed the way the main suite's
-- test/helpers/setup.sql arranges).
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Start from a clean slate. Non-CASCADE so we'd notice if a previous step in
-- this file (or a run before it) left something installed unexpectedly.
DROP EXTENSION IF EXISTS test_factory_pgtap;
DROP EXTENSION IF EXISTS test_factory;

/*
 * A bare (non-CASCADE) CREATE EXTENSION for test_factory_pgtap must fail,
 * since test_factory isn't installed. This proves
 * test_factory_pgtap.control's "requires = 'pgtap, test_factory'" line is
 * real and enforced by Postgres, not just documentation.
 * IF YOU GET A "schema tf does not exist" ERROR HERE INSTEAD (i.e. the
 * CREATE EXTENSION below succeeds), the dependency declaration is
 * missing/broken -- check test_factory_pgtap.control.
 */
CREATE EXTENSION test_factory_pgtap;

-- CASCADE should pull test_factory in automatically.
CREATE EXTENSION test_factory_pgtap CASCADE;

-- Confirm tf.tap(text, text) exists after install. Casting to regprocedure
-- errors out (visibly, in the diff) if the function doesn't exist.
SELECT 'tf.tap(text, text)'::regprocedure;

-- Clean removal: a bare (non-CASCADE) DROP must not error, proving nothing
-- else was left depending on either extension.
DROP EXTENSION test_factory_pgtap;
DROP EXTENSION test_factory;

-- vi: expandtab ts=2 sw=2
