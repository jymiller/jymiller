/******************************************************************************
  SNOWFLAKE EDW TEARDOWN
  ─────────────────────────────────────────────────────────────────────────────
  Drops everything created by 1_EDW_DB_Setup.sql, in the correct reverse order.

  WARNING: This script permanently deletes databases, schemas, all data inside
           them, warehouses, and roles.  There is NO undo.
           Run only when you are certain and only in dev/test environments.

  Drop order (reverse of creation):
    1. Databases  – dropping a database automatically removes all schemas,
                    DB-level roles, and schema access roles inside it
    2. Warehouse
    3. Warehouse access roles  (warO, warU)
    4. Account functional roles (READ → WRITE → DEPLOY → ADMIN)

  Run top-to-bottom in a single Snowflake session.
******************************************************************************/


-- =============================================================================
-- SECTION 0: PARAMETERS  (must match 1_EDW_DB_Setup.sql exactly)
-- =============================================================================

SET scimNm = 'SNFK';
SET beNm   = 'SNOW';
SET evNm   = 'D';
SET dpNm   = '';

SET prefixNm = $beNm
            || IFF($evNm = '', '', '_' || $evNm)
            || IFF($dpNm = '', '', '_' || $dpNm);

SET afrAdmin  = $prefixNm || '_ADMIN';
SET afrDeploy = $prefixNm || '_DEPLOY';
SET afrWrite  = $prefixNm || '_WRITE';
SET afrRead   = $prefixNm || '_READ';

SET wlNm = 'ADHOC';
SET whNm = $prefixNm || '_' || $wlNm;
SET warU = '_WH_U_' || $whNm;
SET warO = '_WH_O_' || $whNm;

-- Preview everything that will be dropped before executing
SELECT
    $prefixNm  AS "Prefix"
  , $afrAdmin  AS "ADMIN Role"
  , $afrDeploy AS "DEPLOY Role"
  , $afrWrite  AS "WRITE Role"
  , $afrRead   AS "READ Role"
  , $whNm      AS "Warehouse"
  , $warU      AS "WH Usage Role"
  , $warO      AS "WH Operate Role";


-- =============================================================================
-- STEP 1: DROP DATABASES
--
-- Drop in reverse creation order: PRES → INT → RAW
-- Dropping a database automatically removes everything inside it:
--   schemas, DB-level roles (DB_R / DB_W / DB_C), and all schema access roles.
-- =============================================================================

USE ROLE SYSADMIN;

SET znNm = 'PRES';
SET dbNm = $prefixNm || '_' || $znNm;
SELECT $dbNm AS "Dropping database";
DROP DATABASE IF EXISTS IDENTIFIER($dbNm);

SET znNm = 'INT';
SET dbNm = $prefixNm || '_' || $znNm;
SELECT $dbNm AS "Dropping database";
DROP DATABASE IF EXISTS IDENTIFIER($dbNm);

SET znNm = 'RAW';
SET dbNm = $prefixNm || '_' || $znNm;
SELECT $dbNm AS "Dropping database";
DROP DATABASE IF EXISTS IDENTIFIER($dbNm);


-- =============================================================================
-- STEP 2: DROP WAREHOUSE
-- =============================================================================

USE ROLE SYSADMIN;
DROP WAREHOUSE IF EXISTS IDENTIFIER($whNm);


-- =============================================================================
-- STEP 3: DROP WAREHOUSE ACCESS ROLES
--
-- USERADMIN can drop any role regardless of ownership.
-- Drop Operate first since it inherits from Usage.
-- =============================================================================

USE ROLE USERADMIN;
DROP ROLE IF EXISTS IDENTIFIER($warO);  -- Operate (inherits Usage)
DROP ROLE IF EXISTS IDENTIFIER($warU);  -- Usage


-- =============================================================================
-- STEP 4: DROP ACCOUNT FUNCTIONAL ROLES
--
-- Drop from the bottom of the hierarchy upward: READ → WRITE → DEPLOY → ADMIN
-- USERADMIN can drop any role regardless of ownership (even roles owned by SCIM).
-- All role grants and privilege assignments are automatically removed on drop.
-- =============================================================================

USE ROLE USERADMIN;
DROP ROLE IF EXISTS IDENTIFIER($afrRead);    -- Bottom of hierarchy
DROP ROLE IF EXISTS IDENTIFIER($afrWrite);
DROP ROLE IF EXISTS IDENTIFIER($afrDeploy);
DROP ROLE IF EXISTS IDENTIFIER($afrAdmin);   -- Top of hierarchy
