--  140a Setup Merge SP 
--  
--  The purpose of this script is to prepare the demo data for the Stored Procedure in 140b
--  Following these steps: 
--  1. Create an ORDERS table with 10 rows of sample data (then add Update_Dt and Row_Hash)
--  2. Create an ORDERS UPDATE table with 4 Updates of OrderKey=1, 1 Update of OrderKey=2, 1 Insert or OrderKey=10 (
--  3. Print out the TARGET TABLE ROWS (ORDERS) and SOURCE TABLE ROWS (ORDERS_UPDATE)
--
--  The audience is folks new to Snowflake with a bit of SQL understanding.
--
--  Author:         John Miller
--  Last Updated:   2025-04-23


-- Make sure DB and SC are ready
create database if not exists toy_db;
create schema if not exists toy_sc;

-- Create Source Data - 10 Orders
create or replace table orders as 
  select * from snowflake_sample_data.tpch_sf1.orders order by o_orderkey asc limit 10;

alter table orders add column update_dt timestamp;
update orders 
  set update_dt = '2025-04-22 12:00:00';  -- current_timestamp();


--- Create Updates to Apply to Orders table

-- pick 3 rows from Orders table
create or replace table orders_update as 
(select * from orders limit 3);


-- update order 1
update orders_update
    set o_comment = 'The Door is a Jar',
    update_dt = '2025-04-22 13:00:00'
    where o_orderkey = 1;

-- insert duplicate / update
insert into orders_update (o_orderkey, o_comment, update_dt)
    values (1, 'The Door is Ajar','2025-04-22 13:05:00' );
    
-- insert duplicate / update
insert into orders_update (o_orderkey, o_comment, update_dt)
    values (1, 'The door is open.','2025-04-23 8:00' );

-- insert duplicate / update
insert into orders_update (o_orderkey, o_comment, update_dt)
    values (1, 'The door is closed.','2025-04-23 8:00' );

-- Create a single update
update orders_update
    set o_comment = 'updated comment',
    update_dt = '2025-04-23 13:00:01'
    where o_orderkey = 2;

-- insert a new order
insert into orders_update (o_orderkey, o_comment, update_dt)
    values (10, 'Why did Order 10 come','2025-04-23 7:00' );

/*
1	The Door is a Jar       2025-04-22 13:00:00            <-- First update to ORDER #1
1   The Door is Ajar        2025-04-22 13:05:00            <-- Second update to ORDER #1
1   The door is open.       2025-04-23 08:00:00            <-- Third update to ORDER #1
1   The door is closed.     2025-04-23 08:00:00            <-- Fourth update to ORDER #1 <-- occuring at the same instant as the Third update. 
2   updated comment         2025-04-23 13:00:01            <-- First update to ORDER #2
3   sly final accounts...   2025-04-22 12:00:00            <-- Unchanged ORDER #3
10  Why did Order 10 come   2025-04-23 07:00:00            <-- New Order (key=10) 
*/

-- ADD ROW HASH for Change Detection 
alter table orders add column row_hash varchar;

update orders 
    set row_hash = SHA1(TO_JSON(OBJECT_CONSTRUCT(*)));

-- show setup data
(select 'TARGET ROW' as ROW_TYPE, o_orderkey, o_comment, update_dt from orders order by o_orderkey asc)
union all
(select 'SOURCE ROW' as ROW_TYPE, o_orderkey, o_comment, update_dt from orders_update order by o_orderkey asc, update_dt asc )
;

