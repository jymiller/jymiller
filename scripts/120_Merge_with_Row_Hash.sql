--  120 Merge with Row Hash
--  
--  The purpose of this script is to demonstrate an enhancement to the simple merge
--  The audience is folks new to Snowflake with a bit of SQL understanding.
--
--  Author:         John Miller
--  Last Updated:   2025-04-23

create database if not exists toy_db;
create schema if not exists toy_sc;

-- if you don't have the Snowflake Sample Database imported from Snowflake
-- follow these guidelines:  https://docs.snowflake.com/en/user-guide/sample-data-using

select * from snowflake_sample_data.tpch_sf1.customer limit 10;

use toy_db.toy_sc;

create or replace table customer_file as 
(select * from snowflake_sample_data.tpch_sf1.customer limit 10);

create or replace table customer_file_update as 
(select * from customer_file limit 3);

select * from customer_file;
select * from customer_file_update; -- 60001,11,3

--
--
alter table customer_file add column row_hash varchar;

update customer_file 
    set row_hash = SHA1(TO_JSON(OBJECT_CONSTRUCT(*)));

select * from customer_file;


-- Snowflake doesn't like CTE in front of Merge...

merge into CUSTOMER_FILE as TARGET
  using (
     SELECT *, SHA1(TO_JSON(OBJECT_CONSTRUCT(*))) AS ROW_HASH
     FROM CUSTOMER_FILE_UPDATE
    ) AS SOURCE
  on TARGET.C_CUSTKEY = SOURCE.C_CUSTKEY
when MATCHED AND TARGET.ROW_HASH != SOURCE.ROW_HASH then
    UPDATE SET
        target.C_NAME = source.C_NAME,
        target.C_ADDRESS = source.C_ADDRESS,
        target.C_NATIONKEY = source.C_NATIONKEY,
        target.C_PHONE = source.C_PHONE,
        target.C_ACCTBAL = source.C_ACCTBAL,
        target.C_MKTSEGMENT = source.C_MKTSEGMENT,
        target.C_COMMENT = source.C_COMMENT,
        target.ROW_HASH = source.ROW_HASH
when NOT MATCHED then
    INSERT ( C_CUSTKEY, C_NAME, C_ADDRESS, C_NATIONKEY, C_PHONE, C_ACCTBAL, C_MKTSEGMENT, C_COMMENT, ROW_HASH )
        VALUES ( source.C_CUSTKEY, source.C_NAME, source.C_ADDRESS, source.C_NATIONKEY, source.C_PHONE, source.C_ACCTBAL, source.C_MKTSEGMENT, source.C_COMMENT, source.ROW_HASH)
        ;

-- select get_ddl('table','customer_file');

select * from customer_file_update;



-- Let's create a task to do the merge... remember this is a toy example! don't do this at home!

CREATE or replace TASK my_1_minute_task
  WAREHOUSE = snow_d_adhoc
  SCHEDULE = 'USING CRON * * * * * America/Los_Angeles'
  AS
merge into CUSTOMER_FILE as TARGET
  using (
     SELECT *, SHA1(TO_JSON(OBJECT_CONSTRUCT(*))) AS ROW_HASH
     FROM CUSTOMER_FILE_UPDATE
    ) AS SOURCE
  on TARGET.C_CUSTKEY = SOURCE.C_CUSTKEY
when MATCHED AND TARGET.ROW_HASH != SOURCE.ROW_HASH then
    UPDATE SET
        target.C_NAME = source.C_NAME,
        target.C_ADDRESS = source.C_ADDRESS,
        target.C_NATIONKEY = source.C_NATIONKEY,
        target.C_PHONE = source.C_PHONE,
        target.C_ACCTBAL = source.C_ACCTBAL,
        target.C_MKTSEGMENT = source.C_MKTSEGMENT,
        target.C_COMMENT = source.C_COMMENT,
        target.ROW_HASH = source.ROW_HASH
when NOT MATCHED then
    INSERT ( C_CUSTKEY, C_NAME, C_ADDRESS, C_NATIONKEY, C_PHONE, C_ACCTBAL, C_MKTSEGMENT, C_COMMENT, ROW_HASH )
        VALUES ( source.C_CUSTKEY, source.C_NAME, source.C_ADDRESS, source.C_NATIONKEY, source.C_PHONE, source.C_ACCTBAL, source.C_MKTSEGMENT, source.C_COMMENT, source.ROW_HASH)    ;

show tasks;

alter task my_1_minute_task resume;

show tasks;

alter task my_1_minute_task suspend;

select * from customer_file;


update customer_file_update
    set   C_ADDRESS = 'San HAHAa'
    where C_CUSTKEY = 60001;


    
