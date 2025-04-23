--  110 Basic Merge
--  
--  The purpose of this script is to demonstrate a very simple merge statement.
--  The audience is folks new to Snowflake with a bit of SQL understanding.
--
--  Author:         John Miller
--  Last Updated:   2025-04-23


create database if not exists toy_db;
create schema if not exists toy_sc;

-- if you don't have the Snowflake Sample Database imported from Snowflake
-- follow these guidelines:  https://docs.snowflake.com/en/user-guide/sample-data-using

select * from snowflake_sample_data.tpch_sf1.customer limit 10;

create or replace table customer_file as 
(select * from snowflake_sample_data.tpch_sf1.customer limit 10);

-- create or replace table customer_file_initial clone customer_file;


create or replace table customer_file_update as 
(select * from customer_file limit 3);

select * from customer_file;  -- 60001- 60010
select * from customer_file_update; -- 60001,2,3

-- Apply changes to "Update file"
update customer_file_update
    set C_ADDRESS = ';akjf;aljskdf'
    where C_CUSTKEY = 60001;

update customer_file_update
    set c_custkey = 60011
    where C_CUSTKEY = 60002;

/*
update customer_file_update
    set c_custkey = 60012, C_ADDRESS = 'BLABLA'
    where C_CUSTKEY = 60003;
*/

select * from customer_file_update;

/*
60001	Customer#000060001	;akjf;aljskdf                  <-- UPDATED RECORD
60011	Customer#000060002	ThGBMjDwKzkoOxhz               <-- INSERT RECORD
60003	Customer#000060003	Ed hbPtTXMTAsgGhCr4HuTzK,Md2   <-- UNCHANGED RECORD
*/

select * from customer_file_update BEFORE( STATEMENT => '01bbdd47-0105-0a97-0007-f3fb00022062');

/*
60001	Customer#000060001	9Ii4zQn9cX
60002	Customer#000060002	ThGBMjDwKzkoOxhz
60003	Customer#000060003	Ed hbPtTXMTAsgGhCr4HuTzK,Md2
*/

merge into CUSTOMER_FILE as TARGET
using CUSTOMER_FILE_UPDATE as SOURCE
    on TARGET.C_CUSTKEY = SOURCE.C_CUSTKEY
when MATCHED then
    UPDATE SET
        target.C_NAME = source.C_NAME,
        target.C_ADDRESS = source.C_ADDRESS,
        target.C_NATIONKEY = source.C_NATIONKEY,
        target.C_PHONE = source.C_PHONE,
        target.C_ACCTBAL = source.C_ACCTBAL,
        target.C_MKTSEGMENT = source.C_MKTSEGMENT,
        target.C_COMMENT = source.C_COMMENT
when NOT MATCHED then
    INSERT ( C_CUSTKEY, C_NAME, C_ADDRESS, C_NATIONKEY, C_PHONE, C_ACCTBAL, C_MKTSEGMENT, C_COMMENT )
        VALUES ( source.C_CUSTKEY, source.C_NAME, source.C_ADDRESS, source.C_NATIONKEY, source.C_PHONE, source.C_ACCTBAL, source.C_MKTSEGMENT, source.C_COMMENT)
        ;
-- select get_ddl('table','customer_file');

-- 1 row inserted, 2 rows updated
-- The assumption is that these ID's don't change
-- And that we can assume a new record means its a change...

select * from customer_file;

-- every time we run the merge henceforth it will update the records... is this what we really want?
-- Or do we actually need to detect a Change using Hash Key
-- i.e. Hash all columns together in source and target and compare the hash - if identical then no-update, if different then update





