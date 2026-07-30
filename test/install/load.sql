\set ECHO none
/*
 * Foundation installer for the whole regression run. pgxntool's
 * PGXNTOOL_ENABLE_TEST_INSTALL feature runs this file, committed, in its
 * own pg_regress session before the regular test SQL files run -- so
 * whatever it commits here survives into every test file, instead of each
 * one creating its own install from scratch (which is still what the
 * regular test files do in the default 'fresh' mode, unchanged). NOTE: this
 * comment deliberately never spells out a bare wildcard glob right after a
 * slash -- slash-star is a comment opener, and Postgres nests block
 * comments, so an unbalanced extra opener earlier in a comment silently
 * swallows the rest of the file instead of erroring where you'd notice (hit
 * this for real while writing this file -- see the PR description).
 *
 * TEST_LOAD_SOURCE (make var -> test_factory.test_load_mode GUC, see
 * Makefile) picks how the extension gets to its target state:
 *   fresh    (default) - do nothing here; the regular test files still
 *                        install it themselves, exactly as before this
 *                        feature existed.
 *   update   - CREATE EXTENSION VERSION :from, then ALTER EXTENSION UPDATE.
 *   existing - extension is already installed (a real pg_upgrade target, or
 *              an out-of-band update) -- assert-only, never drop/create.
 */
\i test/helpers/psql.sql
\i test/roles.sql

SET client_min_messages = WARNING;

-- Read unconditionally, without missing_ok: the Makefile always exports
-- test_factory.test_load_mode, so an unset GUC here means the harness
-- itself is broken, not "assume fresh".
SELECT current_setting('test_factory.test_load_mode')   AS load_mode \gset
SELECT current_setting('test_factory.test_update_from') AS update_from \gset
SELECT current_setting('test_factory.test_update_to')   AS update_to \gset
SELECT :'update_to' <> '' AS has_update_to \gset

DO $$
BEGIN
  IF current_setting('test_factory.test_load_mode') NOT IN ('fresh', 'update', 'existing') THEN
    RAISE EXCEPTION 'test_factory.test_load_mode must be fresh, update or existing, got %', current_setting('test_factory.test_load_mode');
  END IF;
END $$;

-- test_role is test infrastructure, not part of what fresh/update/existing
-- describe -- (re)create it idempotently in every mode. A real pg_upgrade
-- target (existing mode) carries global objects like roles over, but don't
-- assume that; a from-scratch "existing" target might not have it.
SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'test_role') AS need_role \gset
\if :need_role
CREATE ROLE :test_role;
\endif

-- psql's \if only accepts a plain boolean token, not a comparison
-- expression -- compute it via SQL first (\if :load_mode = 'existing' would
-- silently misparse instead of erroring).
SELECT :'load_mode' = 'existing' AS is_existing \gset
\if :is_existing

  -- existing: never drop/create/update -- only assert the extensions are
  -- actually there, at the version this build considers current. Never
  -- hardcode the expected version (see doc's CI dynamic-version-assertion
  -- guidance); default_version comes from the same control file `make`
  -- itself builds from.
  DO $$
  DECLARE
    v_installed text := (SELECT extversion FROM pg_extension WHERE extname = 'test_factory');
    v_default   text := (SELECT default_version FROM pg_available_extensions WHERE name = 'test_factory');
  BEGIN
    IF v_installed IS NULL THEN
      RAISE EXCEPTION 'test_load_mode=existing but test_factory is not installed';
    END IF;
    IF v_installed IS DISTINCT FROM v_default THEN
      RAISE EXCEPTION 'test_factory installed at % but default_version is %', v_installed, v_default;
    END IF;
  END $$;

  DO $$
  DECLARE
    v_installed text := (SELECT extversion FROM pg_extension WHERE extname = 'test_factory_pgtap');
    v_default   text := (SELECT default_version FROM pg_available_extensions WHERE name = 'test_factory_pgtap');
  BEGIN
    IF v_installed IS NULL THEN
      RAISE EXCEPTION 'test_load_mode=existing but test_factory_pgtap is not installed';
    END IF;
    IF v_installed IS DISTINCT FROM v_default THEN
      RAISE EXCEPTION 'test_factory_pgtap installed at % but default_version is %', v_installed, v_default;
    END IF;
  END $$;

  /*
   * Dependency guard (advanced-extension-testing checklist item 6): nothing
   * else stops a stray CASCADE drop, or a logic bug that falls through to
   * the fresh/update branch below, from silently destroying the real
   * upgraded/updated objects this mode exists to test -- the suite would
   * then quietly pass against a fresh reinstall instead.
   *
   * Only test_factory_pgtap needs an artificial guard here. test_factory
   * already has a natural one for free: test_factory_pgtap's own control
   * file (`requires = 'pgtap, test_factory'`) already makes a non-CASCADE
   * DROP EXTENSION test_factory fail on its own, as long as
   * test_factory_pgtap is still installed -- proved below too, so a future
   * change that weakens that dependency doesn't go unnoticed. Nothing
   * depends on test_factory_pgtap itself, so it gets an explicit guard.
   *
   * Only planted in existing mode, not fresh/update: test/sql/install.sql's
   * own non-CASCADE DROP EXTENSION is a deliberate, self-contained test of
   * drop/recreate -- that test is skipped under existing mode (see
   * install.sql) precisely because it's incompatible with this guard.
   */
  CREATE SCHEMA IF NOT EXISTS test_factory_drop_guard;
  CREATE OR REPLACE VIEW test_factory_drop_guard.guard AS
    SELECT 'tf.tap(text,text)'::regprocedure AS guarded_member;

  DO $$
  BEGIN
    BEGIN
      DROP EXTENSION test_factory_pgtap;
      RAISE EXCEPTION 'dependency guard is not working: non-CASCADE DROP EXTENSION test_factory_pgtap succeeded';
    EXCEPTION
      WHEN dependent_objects_still_exist THEN
        NULL; -- expected: the guard view blocked it
    END;
  END $$;

  DO $$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'test_factory_pgtap') THEN
      RAISE EXCEPTION 'dependency guard proof left test_factory_pgtap dropped';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_class
      WHERE relname = 'guard' AND relnamespace = 'test_factory_drop_guard'::regnamespace
    ) THEN
      RAISE EXCEPTION 'dependency guard proof left the guard view itself missing';
    END IF;
  END $$;

  DO $$
  BEGIN
    BEGIN
      DROP EXTENSION test_factory;
      RAISE EXCEPTION 'test_factory''s natural drop-guard (test_factory_pgtap''s requires clause) is not working: non-CASCADE DROP EXTENSION test_factory succeeded';
    EXCEPTION
      WHEN dependent_objects_still_exist THEN
        NULL; -- expected
    END;
  END $$;

\else

  /*
   * fresh/update: drop-first reset, so a re-run against a non-fresh DB
   * (e.g. local dev) starts from a known state. test_factory's own role
   * bootstrapping (CREATE ROLE test_factory__owner, guarded by WHEN
   * duplicate_object in sql/test_factory.sql) already tolerates being
   * re-run, so unlike pgxntool's own drop-first example there's no
   * separate role-drop step needed here.
   */
  DROP EXTENSION IF EXISTS test_factory_pgtap CASCADE;
  DROP EXTENSION IF EXISTS test_factory CASCADE;

  SELECT :'load_mode' = 'update' AS is_update \gset
  \if :is_update

    CREATE EXTENSION test_factory VERSION :'update_from';
    SET client_min_messages = ERROR; -- suppress update-script deprecation NOTICEs
    \if :has_update_to
    ALTER EXTENSION test_factory UPDATE TO :'update_to';
    \else
    ALTER EXTENSION test_factory UPDATE;
    \endif
    SET client_min_messages = WARNING;

  \endif
  /*
   * fresh: nothing else to do here -- the regular test files install the
   * extension themselves, same as before this feature existed (see
   * test/helpers/create_extension.sql).
   *
   * test_factory has only ever shipped one version (0.5.0), so 'update'
   * mode above has no real historical update script to exercise yet --
   * CREATE EXTENSION VERSION '0.5.0' + ALTER EXTENSION UPDATE is a no-op
   * today. The mechanism is built now per the advanced-extension-testing
   * checklist (items 3-5); no CI job drives TEST_LOAD_SOURCE=update yet,
   * since doing so wouldn't prove anything fresh-mode CI doesn't already
   * cover. See the PR description for this reasoning.
   */

\endif

SET client_min_messages = NOTICE;

-- vi: expandtab ts=2 sw=2
