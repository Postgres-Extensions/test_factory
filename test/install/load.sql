\set ECHO none
/*
 * Foundation installer for the whole regression run. pgxntool's
 * PGXNTOOL_ENABLE_TEST_INSTALL feature runs this file, committed, in its
 * own pg_regress session before the regular test SQL files run -- so
 * whatever it commits here survives into every test file, instead of each
 * one creating its own install from scratch. This is the ONLY place that
 * knows how the extension gets onto the system, in every mode -- the
 * regular test files (test/sql/base.sql, test/sql/pgtap.sql) always assume
 * both extensions are already installed. NOTE: this comment deliberately
 * never spells out a bare wildcard glob right after a slash -- slash-star
 * is a comment opener, and Postgres nests block comments, so an unbalanced
 * extra opener earlier in a comment silently swallows the rest of the file
 * instead of erroring where you'd notice (hit this for real while writing
 * this file -- see the PR description).
 *
 * TEST_LOAD_SOURCE (make var -> test_factory.test_load_mode GUC, see
 * Makefile) picks how the extension gets to its target state:
 *   fresh    (default) - CREATE EXTENSION test_factory_pgtap CASCADE.
 *   update   - CREATE EXTENSION VERSION :from, then ALTER EXTENSION UPDATE,
 *              then install test_factory_pgtap too.
 *   existing - extension is already installed (a real pg_upgrade target, or
 *              an out-of-band update) -- assert-only, never drop/create.
 */
\i test/helpers/psql.sql
\i test/roles.sql

SET client_min_messages = WARNING;

/*
 * Read unconditionally, without missing_ok: the Makefile always exports
 * test_factory.test_load_mode, so an unset GUC here means the harness
 * itself is broken, not "assume fresh".
 */
SELECT
    current_setting('test_factory.test_load_mode')   AS load_mode
  , current_setting('test_factory.test_update_from') AS update_from
  , current_setting('test_factory.test_update_to')   AS update_to
  , current_setting('test_factory.test_update_to') <> '' AS has_update_to
\gset

DO $$
BEGIN
  IF current_setting('test_factory.test_load_mode') NOT IN ('fresh', 'update', 'existing') THEN
    RAISE EXCEPTION 'test_factory.test_load_mode must be fresh, update or existing, got %', current_setting('test_factory.test_load_mode');
  END IF;
END $$;

/*
 * test_role is test infrastructure, not part of what fresh/update/existing
 * describe -- (re)create it idempotently in every mode. A real pg_upgrade
 * target (existing mode) carries global objects like roles over, but don't
 * assume that; a from-scratch "existing" target might not have it.
 */
SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'test_role') AS need_role
\gset
\if :need_role
CREATE ROLE :test_role;
\endif

/*
 * Same issue as test_factory__owner (see sql/test_factory.sql's comment):
 * CREATE ROLE alone never grants the creator any relationship to the role
 * it just created, on ANY version -- confirmed directly, this session's
 * connecting role gets "permission denied to set role" on the very role
 * it just created above, with zero prior grant. test/helpers/create.sql's
 * later SET ROLE = test_role needs SET-enabled membership on PG16+, or
 * plain membership pre-16 (no WITH SET syntax there yet). Either branch
 * skips the GRANT when it's not actually needed, since GRANT ROLE needs
 * ADMIN OPTION to run at all, even for a no-op re-grant.
 *
 * Plain SQL + \if, not a DO block: :test_role is a psql variable, and psql
 * never substitutes :variables inside a dollar-quoted body (confirmed
 * directly -- it sends the literal text ":test_role" to the server,
 * producing a syntax error there instead of anywhere client-side that
 * would point at the real problem). GRANT ... TO CURRENT_USER sidesteps
 * needing the *installer's* name dynamically at all -- CURRENT_USER is a
 * real keyword, not a value needing substitution.
 */
SELECT (current_setting('server_version_num')::int >= 160000) AS test_role_pg16plus
\gset
\if :test_role_pg16plus
SELECT NOT pg_has_role(current_user, :'test_role', 'SET') AS test_role_needs_grant
\gset
\if :test_role_needs_grant
GRANT :test_role TO CURRENT_USER WITH SET TRUE;
\endif
\else
SELECT NOT pg_has_role(current_user, :'test_role', 'MEMBER') AS test_role_needs_grant
\gset
\if :test_role_needs_grant
GRANT :test_role TO CURRENT_USER;
\endif
\endif

/*
 * psql's \if only accepts a plain boolean token, not a comparison
 * expression -- compute it via SQL first (\if :load_mode = 'existing' would
 * silently misparse instead of erroring).
 */
SELECT :'load_mode' = 'existing' AS is_existing
\gset
-- existing-vs-fresh/update
\if :is_existing

  /*
   * existing: never drop/create/update -- only assert the extensions are
   * actually there, at the version this build considers current. Never
   * hardcode the expected version (see doc's CI dynamic-version-assertion
   * guidance); default_version comes from the same control file `make`
   * itself builds from.
   */
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
   * Only planted in existing mode, not fresh/update: the guard's whole
   * point is protecting the real upgraded/updated objects this mode exists
   * to test, and fresh/update modes have nothing irreplaceable to protect
   * (a re-run recreates everything from scratch there anyway). Note the
   * guard only blocks a non-CASCADE drop -- it can't stop a logic bug that
   * misroutes into the fresh/update branch below, since that branch's own
   * drop-first reset uses CASCADE. Real protection against that specific
   * failure mode is the is_existing check itself being correct, not this
   * guard; this guard's job is narrower (an accidental *non-cascade* drop
   * elsewhere while existing mode's state is live).
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

-- existing-vs-fresh/update
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

  /*
   * pgtap must land in a dedicated "tap" schema BEFORE test_factory_pgtap
   * installs, not after. test_factory_pgtap.control declares pgtap as a
   * requirement too, so the CREATE EXTENSION ... CASCADE (or plain CREATE
   * EXTENSION, in update mode) below would otherwise cascade-install pgtap
   * itself into whatever schema this session's ambient search_path
   * resolves to (public, by default) -- and since that satisfies "pgtap is
   * already installed", the main suite's own tap_setup.sql (which does
   * CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA tap) then skips creating it
   * in "tap" at all, leaving every pgTAP-based test file failing with
   * "function no_plan() does not exist" (hit this for real writing this
   * file). IF NOT EXISTS on both statements: harmless no-op on a rerun
   * where a previous pass already did this and the drop-first reset above
   * didn't touch it (cascading test_factory_pgtap's drop doesn't remove
   * pgtap -- pgtap is its dependency, not the other way around).
   */
  CREATE SCHEMA IF NOT EXISTS tap;
  CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA tap;

  -- Captured before either branch below runs CREATE EXTENSION, so the
  -- role-restore proof after \endif covers whichever one actually ran.
  SELECT current_user AS role_before_install
  \gset

  SELECT :'load_mode' = 'update' AS is_update
  \gset
  -- update-vs-fresh install
  \if :is_update

    CREATE EXTENSION test_factory VERSION :'update_from';
    SET client_min_messages = ERROR; -- suppress update-script deprecation NOTICEs
    \if :has_update_to
    ALTER EXTENSION test_factory UPDATE TO :'update_to';
    \else
    ALTER EXTENSION test_factory UPDATE;
    \endif
    SET client_min_messages = WARNING;
    /*
     * test_factory_pgtap has only ever shipped one version, so there's no
     * update path of its own to exercise -- just install it at current so
     * the rest of the suite can assume it's present, same as fresh mode.
     */
    CREATE EXTENSION test_factory_pgtap;

  -- update-vs-fresh install
  \else

    /*
     * fresh: install for real, right here, uniformly with update/existing --
     * so test/sql/base.sql and test/sql/pgtap.sql can assume both
     * extensions are already present in every mode, instead of each mode
     * needing its own install-or-skip dance (what test/helpers/
     * create_extension.sql used to do; deleted along with this change).
     * CASCADE proves test_factory_pgtap.control's "requires = 'pgtap,
     * test_factory'" line actually pulls test_factory in --
     * test/sql/pgtap.sql separately proves the dependency is *enforced*
     * (via pg_depend), not just that cascade happens to work.
     */
    CREATE EXTENSION test_factory_pgtap CASCADE;

  -- update-vs-fresh install
  \endif

  /*
   * Prove CREATE EXTENSION restored the calling role (whichever branch
   * above actually ran it) -- a real security property, not a formality:
   * test_factory.sql's install script does its own work as
   * test_factory__owner via SET LOCAL ROLE, saving/restoring the original
   * role around it. Compared from OUTSIDE (current_user before vs after),
   * not by inspecting the internal GUC test_factory.sql saves it to --
   * that GUC is transaction-scoped (set_config(..., true)) and would
   * already be gone by the time a later statement in this autocommit
   * session could read it.
   */
  SELECT current_user AS role_after_install
  \gset
  SELECT :'role_before_install' = :'role_after_install' AS role_was_restored
  \gset
  \if :role_was_restored
  \else
  DO $$ BEGIN RAISE EXCEPTION 'CREATE EXTENSION did not restore the calling role'; END $$;
  \endif

-- existing-vs-fresh/update
\endif

SET client_min_messages = NOTICE;

-- vi: expandtab ts=2 sw=2
