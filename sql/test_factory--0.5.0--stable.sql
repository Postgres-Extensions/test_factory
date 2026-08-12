/*
 * Genuine no-op: nothing in this extension has changed since 0.5.0 yet.
 * This file exists purely so ALTER EXTENSION test_factory UPDATE has an
 * edge to follow at all -- Postgres's version-graph resolution requires
 * an actual sql/test_factory--<from>--<to>.sql file to exist for a
 * transition, regardless of whether its content would be a no-op
 * (confirmed directly: without this file, ALTER EXTENSION UPDATE fails
 * outright with "has no update path from version 0.5.0 to version
 * stable", even though nothing would actually need to change). See
 * ../ai/RELEASE.md's `stable` pseudo-version workflow: every subsequent
 * SQL-touching PR adds whatever ALTER .../CREATE OR REPLACE ... statements
 * are needed here to bring an install on 0.5.0 up to that change.
 */

-- vi: expandtab ts=2 sw=2
