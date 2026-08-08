\set ECHO none
\i test/helpers/setup.sql

-- test/install/load.sql already installed the extension, in every mode.

-- NOTE: This runs some tests itself
\i test/helpers/create.sql

SELECT is_empty(
  'SELECT * FROM customer'
  , 'customer table is empty'
);
SELECT is_empty(
  'SELECT * FROM invoice'
  , 'invoice table is empty'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::invoice, 'base' )$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice factory output'
);

SELECT bag_eq(
  $$SELECT * FROM invoice$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice table content'
);

SELECT bag_eq(
  $$SELECT * FROM customer$$
  , $$VALUES( 1, 'first', 'last' )$$
  , 'customer table content'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::invoice, 'base' )$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice factory second call'
);

SELECT bag_eq(
  $$SELECT * FROM invoice$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice table content stayed constant'
);

SELECT bag_eq(
  $$SELECT * FROM customer$$
  , $$VALUES( 1, 'first', 'last' )$$
  , 'customer table content stayed constant'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::customer, 'function' )$$
  , $$VALUES( 2, 'func first', 'func last' )$$
  , 'Test function factory'
);

SELECT bag_eq(
  $$SELECT * FROM customer$$
  , $$VALUES
      ( 1, 'first', 'last' )
      , ( 2, 'func first', 'func last' )
    $$
  , 'customer table has new row'
);

SELECT lives_ok(
  $$TRUNCATE invoice$$
  , 'truncate invoice'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::invoice, 'base' )$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice factory get remains the same after truncate'
);

ROLLBACK;

-- vi: expandtab ts=2 sw=2
