/******************************************************************************
  SNOWFLAKE EDW DATABASE SETUP
  ─────────────────────────────────────────────────────────────────────────────
  Architecture (3 zones):
    RAW   – Ingestion zone.   Source data landed as-is.
    INT   – Integration zone. Transformed and conformed data.
    PRES  – Presentation zone.Analytics-ready, consumer-facing data.

  Role model:
    Account Functional Roles  →  ADMIN > DEPLOY > WRITE > READ
    DB-level Database Roles   →  DB_C  > DB_W   > DB_R    (one set per database)
    Schema Access Roles       →  SC_C_ > SC_W_  > SC_R_   (one set per schema)

  ─────────────────────────────────────────────────────────────────────────────
  HOW TO USE THIS SCRIPT
    1. Edit SECTION 0 (parameters) with your org, environment, and workload.
    2. Run the entire script top-to-bottom in a single Snowflake session.

  HOW TO ADD A NEW DATABASE
    Copy any DATABASE block, paste it after the last one, and update its
    SET lines (znNm, dbComment, timetravelDays).

  HOW TO ADD A NEW SCHEMA
    Copy any SCHEMA block, paste it inside the correct DATABASE block, and
    update its SET lines (scNm, scComment).
    The SQL that follows is identical every time -- only the SET lines change.
******************************************************************************/


-- =============================================================================
-- SECTION 0: PARAMETERS  (the only section you need to edit)
-- =============================================================================

SET scimNm = 'SNFK';   -- Prefix of the SCIM Provisioner role
SET beNm   = 'SNOW';   -- Business entity / organization abbreviation
SET evNm   = 'D';      -- Environment:  D = Dev  |  T = Tst  |  P = Prd
SET dpNm   = '';        -- Data Product name (leave blank for a shared core EDW)

-- Derive the shared name prefix from the parameters above
SET prefixNm = $beNm
            || IFF($evNm = '', '', '_' || $evNm)
            || IFF($dpNm = '', '', '_' || $dpNm);

-- Derive the four Account Functional Role names
SET afrAdmin  = $prefixNm || '_ADMIN';
SET afrDeploy = $prefixNm || '_DEPLOY';
SET afrWrite  = $prefixNm || '_WRITE';
SET afrRead   = $prefixNm || '_READ';
-- SET scimRl    = $scimNm   || '_PROVISIONER';
SET scimRl    = 'SECURITYADMIN';

-- Preview all derived names before executing
SELECT
    $prefixNm  AS "Prefix"
  , $afrAdmin  AS "ADMIN Role"
  , $afrDeploy AS "DEPLOY Role"
  , $afrWrite  AS "WRITE Role"
  , $afrRead   AS "READ Role"
  , $scimRl    AS "SCIM Provisioner";


-- =============================================================================
-- SECTION 1: ACCOUNT FUNCTIONAL ROLES
--
-- Creates four roles representing the human / service-account access tiers.
-- Hierarchy:  READ  →  WRITE  →  DEPLOY  →  ADMIN  →  SYSADMIN
-- =============================================================================

USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS IDENTIFIER($afrAdmin)  COMMENT = 'Delegated Admin – full control of this environment';
CREATE ROLE IF NOT EXISTS IDENTIFIER($afrDeploy) COMMENT = 'Deploy Admin – create and modify objects';
CREATE ROLE IF NOT EXISTS IDENTIFIER($afrWrite)  COMMENT = 'Data Engineering – write data, operate pipelines';
CREATE ROLE IF NOT EXISTS IDENTIFIER($afrRead)   COMMENT = 'Data Engineering – read-only access';

-- Wire the hierarchy so each higher role inherits privileges of the roles below it
USE ROLE SECURITYADMIN;

GRANT ROLE IDENTIFIER($afrAdmin)  TO ROLE SYSADMIN;                 -- Central admin retains control
GRANT ROLE IDENTIFIER($afrRead)   TO ROLE IDENTIFIER($afrWrite);    -- WRITE  inherits READ
GRANT ROLE IDENTIFIER($afrWrite)  TO ROLE IDENTIFIER($afrDeploy);   -- DEPLOY inherits WRITE
GRANT ROLE IDENTIFIER($afrDeploy) TO ROLE IDENTIFIER($afrAdmin);    -- ADMIN  inherits DEPLOY

-- Account-level grants required by the WRITE role
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK        ON ACCOUNT           TO ROLE IDENTIFIER($afrWrite);
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE IDENTIFIER($afrWrite);

-- Transfer ownership of functional roles to the SCIM Provisioner
-- so that IdP group assignments drive access going forward
USE ROLE SECURITYADMIN;
GRANT OWNERSHIP ON ROLE IDENTIFIER($afrAdmin)  TO ROLE IDENTIFIER($scimRl) COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE IDENTIFIER($afrDeploy) TO ROLE IDENTIFIER($scimRl) COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE IDENTIFIER($afrWrite)  TO ROLE IDENTIFIER($scimRl) COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE IDENTIFIER($afrRead)   TO ROLE IDENTIFIER($scimRl) COPY CURRENT GRANTS;


-- =============================================================================
-- SECTION 2: WAREHOUSE
--
-- Creates one general-purpose warehouse.
-- To add workload-specific warehouses (ingest, reporting, etc.), copy this
-- block, paste it below, and update the SET lines.
-- =============================================================================

SET wlNm = 'ADHOC';    -- Workload label:  INGEST | TRANSFORM | REPORT | ADHOC
SET whNm = $prefixNm || '_' || $wlNm;
SET warU = '_WH_U_' || $whNm;   -- Access Role: Monitor & Usage   (underscore prefix = access role)
SET warO = '_WH_O_' || $whNm;   -- Access Role: Operate & Modify

SELECT
    $whNm AS "Warehouse"
  , $warU AS "Usage Access Role"
  , $warO AS "Operate Access Role";

-- Create the warehouse and immediately hand ownership to the delegated admin
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($whNm) WITH
    WAREHOUSE_SIZE               = XSMALL
    INITIALLY_SUSPENDED          = TRUE
    AUTO_RESUME                  = TRUE
    AUTO_SUSPEND                 = 60
    STATEMENT_TIMEOUT_IN_SECONDS = 1800
    COMMENT                      = 'General-purpose warehouse for the core EDW';

GRANT OWNERSHIP ON WAREHOUSE IDENTIFIER($whNm) TO ROLE IDENTIFIER($afrAdmin);

-- Create two warehouse access roles
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS IDENTIFIER($warU) COMMENT = 'WH Access Role – Monitor & Usage';
GRANT MONITOR, USAGE  ON WAREHOUSE IDENTIFIER($whNm) TO ROLE IDENTIFIER($warU);

CREATE ROLE IF NOT EXISTS IDENTIFIER($warO) COMMENT = 'WH Access Role – Operate & Modify';
GRANT OPERATE, MODIFY ON WAREHOUSE IDENTIFIER($whNm) TO ROLE IDENTIFIER($warO);

GRANT ROLE IDENTIFIER($warU) TO ROLE IDENTIFIER($warO);  -- Operate inherits Usage

GRANT OWNERSHIP ON ROLE IDENTIFIER($warU) TO ROLE IDENTIFIER($afrAdmin) COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE IDENTIFIER($warO) TO ROLE IDENTIFIER($afrAdmin) COPY CURRENT GRANTS;

-- Wire warehouse access roles to functional roles
USE ROLE IDENTIFIER($afrAdmin);
GRANT ROLE IDENTIFIER($warU) TO ROLE IDENTIFIER($afrRead);    -- READ   can use the warehouse
GRANT ROLE IDENTIFIER($warO) TO ROLE IDENTIFIER($afrWrite);   -- WRITE  can operate the warehouse
GRANT ROLE IDENTIFIER($warO) TO ROLE IDENTIFIER($afrDeploy);  -- DEPLOY can operate the warehouse


-- =============================================================================
-- =============================================================================
--
--   DATABASE & SCHEMA SETUP
--   ─────────────────────────────────────────────────────────────────────────
--   The same SQL block is repeated for every database and every schema.
--   Only the SET lines at the top of each block change.
--
--   DATABASE block creates:
--     • The database itself
--     • Three DB-level database roles: DB_R  DB_W  DB_C
--     • Grants wiring DB roles → functional roles
--
--   SCHEMA block creates (inside the current database):
--     • The schema
--     • Three schema access roles:  SC_R_<name>  SC_W_<name>  SC_C_<name>
--     • All object-level privilege grants for current and future objects
--     • Role hierarchy:  SC_R_ → SC_W_ → SC_C_
--     • Grants wiring schema roles → DB roles
--
-- =============================================================================
-- =============================================================================


-- ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
-- DATABASE: RAW   (ingestion zone – source data landed as-is)
-- ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

SET znNm           = 'RAW';
SET dbNm           = $prefixNm || '_' || $znNm;
SET dbComment      = 'Raw ingestion zone – source data landed as-is';
SET timetravelDays = 7;

SELECT $dbNm AS "Database to be created";

-- Step 1: Create database (SYSADMIN) and transfer ownership to the delegated admin
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS IDENTIFIER($dbNm)
    DATA_RETENTION_TIME_IN_DAYS = $timetravelDays
    COMMENT                     = $dbComment;
USE DATABASE IDENTIFIER($dbNm);
DROP SCHEMA IF EXISTS PUBLIC;  -- Remove the default PUBLIC schema
GRANT OWNERSHIP ON DATABASE IDENTIFIER($dbNm) TO ROLE IDENTIFIER($afrAdmin);

-- Step 2: Create three database-level roles and wire them to functional roles
USE ROLE IDENTIFIER($afrAdmin);
USE DATABASE IDENTIFIER($dbNm);
CREATE DATABASE ROLE IF NOT EXISTS DB_R  COMMENT = 'DB-level Read';
CREATE DATABASE ROLE IF NOT EXISTS DB_W  COMMENT = 'DB-level Write';
CREATE DATABASE ROLE IF NOT EXISTS DB_C  COMMENT = 'DB-level Create';
GRANT DATABASE ROLE DB_R TO ROLE IDENTIFIER($afrRead);    -- READ   users get DB_R
GRANT DATABASE ROLE DB_W TO ROLE IDENTIFIER($afrWrite);   -- WRITE  users get DB_W
GRANT DATABASE ROLE DB_C TO ROLE IDENTIFIER($afrDeploy);  -- DEPLOY users get DB_C

-- ─────────────────────────────────────────────────────────────────────────────
-- SCHEMA: RAW.TPCH
-- ─────────────────────────────────────────────────────────────────────────────

SET scNm      = 'TPCH';
SET scComment = 'Raw TPCH source data';
SET sarR      = 'SC_R_' || $scNm;
SET sarW      = 'SC_W_' || $scNm;
SET sarC      = 'SC_C_' || $scNm;

-- Step 1: Create schema
USE ROLE IDENTIFIER($afrAdmin);
USE DATABASE IDENTIFIER($dbNm);
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($scNm) WITH MANAGED ACCESS COMMENT = $scComment;

-- Step 2a: READ access role – SELECT on all current and future readable objects
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarR);
GRANT USAGE, MONITOR ON DATABASE IDENTIFIER($dbNm)  TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE, MONITOR ON SCHEMA   IDENTIFIER($scNm)  TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL TABLES                IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE TABLES             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL VIEWS                 IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE VIEWS              IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL EXTERNAL TABLES       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE EXTERNAL TABLES    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL DYNAMIC TABLES        IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE DYNAMIC TABLES     IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL MATERIALIZED VIEWS    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE MATERIALIZED VIEWS IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE  ON ALL FUNCTIONS             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE  ON FUTURE FUNCTIONS          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);

-- Step 2b: WRITE access role – DML + pipeline operations
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarW);
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES            IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT SELECT                           ON ALL STREAMS            IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT SELECT                           ON FUTURE STREAMS         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL PROCEDURES         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE PROCEDURES      IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL SEQUENCES          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE SEQUENCES       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL TASKS              IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE TASKS           IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL FILE FORMATS       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE FILE FORMATS    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE, READ, WRITE               ON ALL STAGES             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE, READ, WRITE               ON FUTURE STAGES          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL DYNAMIC TABLES     IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE DYNAMIC TABLES  IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL ALERTS             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE ALERTS          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);

-- Step 2c: CREATE access role – DDL privileges
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarC);
GRANT CREATE TABLE             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE VIEW              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STREAM            ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE FUNCTION          ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE PROCEDURE         ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE SEQUENCE          ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE TASK              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE FILE FORMAT       ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STAGE             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE EXTERNAL TABLE    ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE PIPE              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE DYNAMIC TABLE     ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE MATERIALIZED VIEW ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STREAMLIT         ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE ALERT             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE TAG               ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE MASKING POLICY    ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE ROW ACCESS POLICY ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);

-- Step 3: Schema role hierarchy – each role inherits privileges from the one below it
GRANT DATABASE ROLE IDENTIFIER($sarR) TO DATABASE ROLE IDENTIFIER($sarW);  -- WRITE  inherits READ
GRANT DATABASE ROLE IDENTIFIER($sarW) TO DATABASE ROLE IDENTIFIER($sarC);  -- CREATE inherits WRITE

-- Step 4: Wire schema access roles up to the database-level roles
GRANT DATABASE ROLE IDENTIFIER($sarR) TO DATABASE ROLE DB_R;
GRANT DATABASE ROLE IDENTIFIER($sarW) TO DATABASE ROLE DB_W;
GRANT DATABASE ROLE IDENTIFIER($sarC) TO DATABASE ROLE DB_C;


-- ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
-- DATABASE: INT   (integration zone – transformed and conformed data)
-- ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

SET znNm           = 'INT';
SET dbNm           = $prefixNm || '_' || $znNm;
SET dbComment      = 'Integration zone – transformed and conformed data';
SET timetravelDays = 7;

SELECT $dbNm AS "Database to be created";

-- Step 1: Create database (SYSADMIN) and transfer ownership to the delegated admin
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS IDENTIFIER($dbNm)
    DATA_RETENTION_TIME_IN_DAYS = $timetravelDays
    COMMENT                     = $dbComment;
USE DATABASE IDENTIFIER($dbNm);
DROP SCHEMA IF EXISTS PUBLIC;  -- Remove the default PUBLIC schema
GRANT OWNERSHIP ON DATABASE IDENTIFIER($dbNm) TO ROLE IDENTIFIER($afrAdmin);

-- Step 2: Create three database-level roles and wire them to functional roles
USE ROLE IDENTIFIER($afrAdmin);
USE DATABASE IDENTIFIER($dbNm);
CREATE DATABASE ROLE IF NOT EXISTS DB_R  COMMENT = 'DB-level Read';
CREATE DATABASE ROLE IF NOT EXISTS DB_W  COMMENT = 'DB-level Write';
CREATE DATABASE ROLE IF NOT EXISTS DB_C  COMMENT = 'DB-level Create';
GRANT DATABASE ROLE DB_R TO ROLE IDENTIFIER($afrRead);    -- READ   users get DB_R
GRANT DATABASE ROLE DB_W TO ROLE IDENTIFIER($afrWrite);   -- WRITE  users get DB_W
GRANT DATABASE ROLE DB_C TO ROLE IDENTIFIER($afrDeploy);  -- DEPLOY users get DB_C

-- ─────────────────────────────────────────────────────────────────────────────
-- SCHEMA: INT.TPCH
-- ─────────────────────────────────────────────────────────────────────────────

SET scNm      = 'TPCH';
SET scComment = 'Integration TPCH data';
SET sarR      = 'SC_R_' || $scNm;
SET sarW      = 'SC_W_' || $scNm;
SET sarC      = 'SC_C_' || $scNm;

-- Step 1: Create schema
USE ROLE IDENTIFIER($afrAdmin);
USE DATABASE IDENTIFIER($dbNm);
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($scNm) WITH MANAGED ACCESS COMMENT = $scComment;

-- Step 2a: READ access role – SELECT on all current and future readable objects
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarR);
GRANT USAGE, MONITOR ON DATABASE IDENTIFIER($dbNm)  TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE, MONITOR ON SCHEMA   IDENTIFIER($scNm)  TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL TABLES                IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE TABLES             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL VIEWS                 IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE VIEWS              IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL EXTERNAL TABLES       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE EXTERNAL TABLES    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL DYNAMIC TABLES        IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE DYNAMIC TABLES     IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL MATERIALIZED VIEWS    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE MATERIALIZED VIEWS IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE  ON ALL FUNCTIONS             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE  ON FUTURE FUNCTIONS          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);

-- Step 2b: WRITE access role – DML + pipeline operations
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarW);
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES            IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT SELECT                           ON ALL STREAMS            IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT SELECT                           ON FUTURE STREAMS         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL PROCEDURES         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE PROCEDURES      IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL SEQUENCES          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE SEQUENCES       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL TASKS              IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE TASKS           IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL FILE FORMATS       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE FILE FORMATS    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE, READ, WRITE               ON ALL STAGES             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE, READ, WRITE               ON FUTURE STAGES          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL DYNAMIC TABLES     IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE DYNAMIC TABLES  IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL ALERTS             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE ALERTS          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);

-- Step 2c: CREATE access role – DDL privileges
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarC);
GRANT CREATE TABLE             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE VIEW              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STREAM            ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE FUNCTION          ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE PROCEDURE         ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE SEQUENCE          ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE TASK              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE FILE FORMAT       ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STAGE             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE EXTERNAL TABLE    ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE PIPE              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE DYNAMIC TABLE     ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE MATERIALIZED VIEW ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STREAMLIT         ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE ALERT             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE TAG               ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE MASKING POLICY    ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE ROW ACCESS POLICY ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);

-- Step 3: Schema role hierarchy – each role inherits privileges from the one below it
GRANT DATABASE ROLE IDENTIFIER($sarR) TO DATABASE ROLE IDENTIFIER($sarW);  -- WRITE  inherits READ
GRANT DATABASE ROLE IDENTIFIER($sarW) TO DATABASE ROLE IDENTIFIER($sarC);  -- CREATE inherits WRITE

-- Step 4: Wire schema access roles up to the database-level roles
GRANT DATABASE ROLE IDENTIFIER($sarR) TO DATABASE ROLE DB_R;
GRANT DATABASE ROLE IDENTIFIER($sarW) TO DATABASE ROLE DB_W;
GRANT DATABASE ROLE IDENTIFIER($sarC) TO DATABASE ROLE DB_C;


-- ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
-- DATABASE: PRES  (presentation zone – analytics-ready, consumer-facing)
-- ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

SET znNm           = 'PRES';
SET dbNm           = $prefixNm || '_' || $znNm;
SET dbComment      = 'Presentation zone – analytics-ready, consumer-facing data';
SET timetravelDays = 7;

SELECT $dbNm AS "Database to be created";

-- Step 1: Create database (SYSADMIN) and transfer ownership to the delegated admin
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS IDENTIFIER($dbNm)
    DATA_RETENTION_TIME_IN_DAYS = $timetravelDays
    COMMENT                     = $dbComment;
USE DATABASE IDENTIFIER($dbNm);
DROP SCHEMA IF EXISTS PUBLIC;  -- Remove the default PUBLIC schema
GRANT OWNERSHIP ON DATABASE IDENTIFIER($dbNm) TO ROLE IDENTIFIER($afrAdmin);

-- Step 2: Create three database-level roles and wire them to functional roles
USE ROLE IDENTIFIER($afrAdmin);
USE DATABASE IDENTIFIER($dbNm);
CREATE DATABASE ROLE IF NOT EXISTS DB_R  COMMENT = 'DB-level Read';
CREATE DATABASE ROLE IF NOT EXISTS DB_W  COMMENT = 'DB-level Write';
CREATE DATABASE ROLE IF NOT EXISTS DB_C  COMMENT = 'DB-level Create';
GRANT DATABASE ROLE DB_R TO ROLE IDENTIFIER($afrRead);    -- READ   users get DB_R
GRANT DATABASE ROLE DB_W TO ROLE IDENTIFIER($afrWrite);   -- WRITE  users get DB_W
GRANT DATABASE ROLE DB_C TO ROLE IDENTIFIER($afrDeploy);  -- DEPLOY users get DB_C

-- ─────────────────────────────────────────────────────────────────────────────
-- SCHEMA: PRES.SALES
-- ─────────────────────────────────────────────────────────────────────────────

SET scNm      = 'SALES';
SET scComment = 'Presentation Sales data';
SET sarR      = 'SC_R_' || $scNm;
SET sarW      = 'SC_W_' || $scNm;
SET sarC      = 'SC_C_' || $scNm;

-- Step 1: Create schema
USE ROLE IDENTIFIER($afrAdmin);
USE DATABASE IDENTIFIER($dbNm);
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($scNm) WITH MANAGED ACCESS COMMENT = $scComment;

-- Step 2a: READ access role – SELECT on all current and future readable objects
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarR);
GRANT USAGE, MONITOR ON DATABASE IDENTIFIER($dbNm)  TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE, MONITOR ON SCHEMA   IDENTIFIER($scNm)  TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL TABLES                IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE TABLES             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL VIEWS                 IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE VIEWS              IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL EXTERNAL TABLES       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE EXTERNAL TABLES    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL DYNAMIC TABLES        IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE DYNAMIC TABLES     IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON ALL MATERIALIZED VIEWS    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE MATERIALIZED VIEWS IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE  ON ALL FUNCTIONS             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT USAGE  ON FUTURE FUNCTIONS          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);

-- Step 2b: WRITE access role – DML + pipeline operations
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarW);
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES            IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT SELECT                           ON ALL STREAMS            IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT SELECT                           ON FUTURE STREAMS         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL PROCEDURES         IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE PROCEDURES      IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL SEQUENCES          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE SEQUENCES       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL TASKS              IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE TASKS           IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON ALL FILE FORMATS       IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE                            ON FUTURE FILE FORMATS    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE, READ, WRITE               ON ALL STAGES             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT USAGE, READ, WRITE               ON FUTURE STAGES          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL DYNAMIC TABLES     IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE DYNAMIC TABLES  IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON ALL ALERTS             IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);
GRANT MONITOR, OPERATE                 ON FUTURE ALERTS          IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarW);

-- Step 2c: CREATE access role – DDL privileges
CREATE DATABASE ROLE IF NOT EXISTS IDENTIFIER($sarC);
GRANT CREATE TABLE             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE VIEW              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STREAM            ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE FUNCTION          ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE PROCEDURE         ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE SEQUENCE          ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE TASK              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE FILE FORMAT       ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STAGE             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE EXTERNAL TABLE    ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE PIPE              ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE DYNAMIC TABLE     ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE MATERIALIZED VIEW ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE STREAMLIT         ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE ALERT             ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE TAG               ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE MASKING POLICY    ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);
GRANT CREATE ROW ACCESS POLICY ON SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarC);

-- Step 3: Schema role hierarchy – each role inherits privileges from the one below it
GRANT DATABASE ROLE IDENTIFIER($sarR) TO DATABASE ROLE IDENTIFIER($sarW);  -- WRITE  inherits READ
GRANT DATABASE ROLE IDENTIFIER($sarW) TO DATABASE ROLE IDENTIFIER($sarC);  -- CREATE inherits WRITE

-- Step 4: Wire schema access roles up to the database-level roles
GRANT DATABASE ROLE IDENTIFIER($sarR) TO DATABASE ROLE DB_R;
GRANT DATABASE ROLE IDENTIFIER($sarW) TO DATABASE ROLE DB_W;
GRANT DATABASE ROLE IDENTIFIER($sarC) TO DATABASE ROLE DB_C;
