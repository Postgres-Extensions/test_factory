SET ROLE = DEFAULT;
/*
 * test_role itself is created once, idempotently, by test/install/load.sql
 * (test/roles.sql is the single source of truth for the name; \i'd via
 * test/helpers/deps.sql).
 */
GRANT USAGE ON SCHEMA tap TO :test_role;
/*
 * DO NOT GRANT test_role TO test_factory__owner; the whole point test_role is
 * to check for security problems.
 */

CREATE SCHEMA test AUTHORIZATION :test_role;
SET ROLE = :test_role;
SET search_path = test, tap;

CREATE TABLE customer(
  customer_id   serial  PRIMARY KEY
  , first_name  text    NOT NULL
  , last_name   text    NOT NULL
);
CREATE TABLE invoice(
  invoice_id      serial  PRIMARY KEY
  , customer_id   int     NOT NULL REFERENCES customer
  , invoice_date  date  NOT NULL
  , due_date      date
);

SELECT lives_ok(
$lives_ok$SELECT tf.register(
  'customer'
  , array[
    row(
      'insert'
      , $$INSERT INTO customer VALUES (DEFAULT, 'first', 'last' ) RETURNING *$$
    )::tf.test_set
    , row(
      'function'
      , $$SELECT * FROM customer__add( 'func first', 'func last' )$$
    )::tf.test_set
  ]
);$lives_ok$
  , 'Register test customers'
);
SELECT lives_ok(
$lives_ok$CREATE FUNCTION customer__add(
  first_name text
  , last_name text
) RETURNS SETOF customer LANGUAGE plpgsql AS $body$
BEGIN
  RETURN QUERY
    INSERT INTO customer( first_name, last_name )
      VALUES( first_name, last_name )
      RETURNING *
  ;
END
$body$;$lives_ok$
  , 'Create function customer__add'
);

SELECT lives_ok(
$lives_ok$SELECT tf.register(
  'invoice'
  , array[
      row(
        'base'
        , $$INSERT INTO invoice VALUES(
            DEFAULT
            , (tf.get( NULL::customer, 'insert' )).customer_id
            , current_date
            , current_date + 30
          ) RETURNING *$$
      )::tf.test_set
  ]
);$lives_ok$
  , 'Register test invoices'
);

-- Arguably this should be in it's own file
SELECT hasnt_table(
  'pg_temp'
  , 'original_role'
  , 'Ensure original_role temp table was dropped'
);

-- Role-restore verification (does CREATE EXTENSION correctly restore the
-- calling role?) now lives in test/install/load.sql, where CREATE
-- EXTENSION actually runs in every mode -- there's nothing to check here
-- anymore now that this file no longer runs it itself.

SELECT cmp_ok(
      proconfig
      , '@>'
      , '{search_path=pg_catalog}'
      , 'Security definer function ' || p.oid::regproc || ' has search_path=pg_catalog'
    )
  FROM pg_proc p
    JOIN pg_namespace n ON n.oid = pronamespace
  WHERE n.nspname IN ( 'tf', '_tf' )
    AND p.prosecdef
;


-- vi: expandtab ts=2 sw=2
