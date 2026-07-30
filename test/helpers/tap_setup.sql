\i test/helpers/psql.sql

SET client_min_messages = WARNING;
CREATE SCHEMA IF NOT EXISTS tap;
SET search_path = tap;
CREATE EXTENSION IF NOT EXISTS pgtap SCHEMA tap;
SET client_min_messages = NOTICE;

\pset format unaligned
\pset tuples_only true
\pset pager
