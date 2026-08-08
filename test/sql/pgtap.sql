\set ECHO none
\i test/helpers/setup.sql

SET search_path = tap;

/*
 * Confirms test_factory_pgtap.control's "requires = 'pgtap, test_factory'"
 * is actually enforced by Postgres, via a pg_depend extension-requires-
 * extension edge -- deptype 'n' (normal), NOT 'e' (DEPENDENCY_EXTENSION,
 * which instead means "this object belongs to this extension").
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
