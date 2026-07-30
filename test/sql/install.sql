\set ECHO none
\i test/helpers/setup.sql

SET client_min_messages = WARNING;

/*
 * DO NOT use CASCADE here; we want this to fail if there's anything installed
 * that depends on it.
 */
SELECT lives_ok($$DROP EXTENSION IF EXISTS test_factory_pgtap$$, 'drop extension test_factory_pgtap');
SELECT lives_ok($$DROP EXTENSION IF EXISTS test_factory$$, 'drop extension test_factory');
/*
 * test_factory__owner is deliberately left behind by DROP EXTENSION (the
 * install script tolerates it already existing, so a real install/uninstall
 * cycle by the same installer keeps working). But this test creates a fresh,
 * disposable test_factory_installer role below, and an orphaned owner role
 * from a previous run of *this file* would belong to an installer that no
 * longer exists -- drop it defensively so repeated local `make installcheck`
 * runs against the same cluster don't flake.
 */
DROP ROLE IF EXISTS test_factory__owner;

SELECT hasnt_extension( 'test_factory' );
SELECT hasnt_extension( 'test_factory_pgtap' );

/*
 * Install as a genuine non-superuser role (NOSUPERUSER + CREATEROLE mirrors
 * what a real RDS/Aurora master user has), now that both control files are
 * marked `superuser = false`. Before the issue #14 fix this fails with
 * "must be able to SET ROLE test_factory__owner"; after the fix it succeeds.
 */
CREATE ROLE test_factory_installer NOSUPERUSER CREATEROLE;
-- USAGE on tap is a pgtap test-harness necessity (to call lives_ok() etc.
-- below), not one of the grants under test here.
GRANT USAGE ON SCHEMA tap TO test_factory_installer;
-- CREATE ON DATABASE is never granted to PUBLIC by default (only CONNECT/TEMP
-- are) -- a real RDS/Aurora master user gets this explicitly via rds_superuser,
-- so grant it here to mirror that setup.
DO $body$
BEGIN
  EXECUTE format('GRANT CREATE ON DATABASE %I TO test_factory_installer', current_database());
END
$body$;
SET SESSION AUTHORIZATION test_factory_installer;
SELECT lives_ok($$CREATE EXTENSION test_factory_pgtap CASCADE$$, 'create extension as a non-superuser role (issue #14)');
RESET SESSION AUTHORIZATION;
COMMIT;

SELECT has_function('tf', 'tap', array['text','text']);

-- Cleanup
SELECT lives_ok($$DROP EXTENSION IF EXISTS test_factory_pgtap$$, 'clean-up test_factory_pgtap');
SELECT lives_ok($$DROP EXTENSION IF EXISTS test_factory$$, 'clean-up test_factory');
-- DROP ROLE alone fails while the GRANT USAGE ON SCHEMA tap above still holds;
-- DROP OWNED clears any privileges/ownership left in this database first.
DROP OWNED BY test_factory_installer;
DROP ROLE IF EXISTS test_factory_installer;
-- See the comment above the earlier DROP ROLE IF EXISTS test_factory__owner.
DROP ROLE IF EXISTS test_factory__owner;

/*
 * Arguably we should cleanup pgtap and the tap schema...
 */

-- vi: expandtab ts=2 sw=2

