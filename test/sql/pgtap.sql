\set ECHO none
\i test/helpers/setup.sql

SET search_path = tap;

/*
 * Prove test_factory_pgtap.control's "requires = 'pgtap, test_factory'"
 * line is real and enforced by Postgres, not just documentation -- via a
 * pg_depend extension-requires-extension edge, which CREATE EXTENSION
 * always records for anything in `requires`, regardless of whether CASCADE
 * was needed to satisfy it or the dependency was already present. Works
 * uniformly in every TEST_LOAD_SOURCE mode, since it only inspects final
 * state -- unlike attempting a bare, doomed CREATE EXTENSION
 * test_factory_pgtap (the previous approach here), which only worked when
 * this file could assume test_factory_pgtap wasn't installed yet; that
 * assumption stopped holding once test/install/load.sql started installing
 * both extensions in every mode, not just update/existing.
 *
 * deptype = 'n' (normal), NOT 'e': confirmed directly against a live
 * database (`SELECT deptype, ... FROM pg_depend ...`) rather than assumed
 * -- 'e' (DEPENDENCY_EXTENSION) is for "this object belongs to this
 * extension" (e.g. a function belongs to test_factory), a completely
 * different relationship from "this extension requires that extension",
 * which pg_depend records as an ordinary 'n' dependency between the two
 * pg_extension rows.
 */
SELECT ok(
  EXISTS (
    SELECT 1
      FROM pg_depend d
      JOIN pg_extension req ON d.objid = req.oid AND d.classid = 'pg_extension'::regclass
      JOIN pg_extension dep ON d.refobjid = dep.oid AND d.refclassid = 'pg_extension'::regclass
     WHERE req.extname = 'test_factory_pgtap'
       AND dep.extname = 'test_factory'
       AND d.deptype = 'n'
  )
  , 'test_factory_pgtap depends on test_factory (control file requires is real and enforced)'
);

-- NOTE: This runs some tests itself. It also changes search_path
\i test/helpers/create.sql

-- tf.tap already returns tap output
SELECT tf.tap( 'invoice' );
SELECT tf.tap( 'invoice', 'base' );
SELECT throws_ok(
  $$SELECT tf.tap( '"non-existent table"' )$$
  , '42P01'
  , 'relation "non-existent table" does not exist'
  , 'Ensure we get sane error for a non-existent table'
);

ROLLBACK;

-- vi: expandtab ts=2 sw=2
