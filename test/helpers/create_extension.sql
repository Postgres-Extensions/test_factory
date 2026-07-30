\echo Creating extension :extension_name
/*
 * In 'update'/'existing' mode, test/install/load.sql already installed (and,
 * for 'update', updated) the extensions in its own earlier committed
 * session -- skip re-creating here instead of erroring or, worse, silently
 * replacing the state those modes exist to test. In 'fresh' mode (the only
 * mode test/install/load.sql leaves untouched), keep the original
 * behavior: no IF NOT EXISTS, so we're confused loudly if something's
 * already there instead of silently testing stale state.
 */
SELECT
  current_setting('test_factory.test_load_mode') <> 'fresh'
  AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = :'extension_name')
  AS already_installed
\gset
\if :already_installed
\echo :extension_name already installed -- skipping CREATE EXTENSION (test_load_mode is not fresh)
\else
CREATE TEMP TABLE pre_install_role AS SELECT current_user;
GRANT SELECT ON pre_install_role TO public; -- In case role is different
CREATE EXTENSION :extension_name;
CREATE TEMP TABLE post_install_role AS SELECT current_user;
GRANT SELECT ON post_install_role TO public; -- In case role is different
\endif
