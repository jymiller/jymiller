--  130 Merge with Dedup
--  
--  The purpose of this demo is to show
--  1. Using a Merge Statement
--  2. Using a Row_Hash to detect whether column values are the same
--  3. Using a Window function to select the most RECENT update row
--
--  The audience is folks new to Snowflake with a bit of SQL understanding.
--
--  Author:         John Miller
--  Last Updated:   2025-04-23

-- Make sure DB and SC are ready
create database if not exists toy_db;
create schema if not exists toy_sc;

-- Create Source Data - 10 Orders
select * from snowflake_sample_data.tpch_sf1.orders order by o_orderkey asc limit 10;

create or replace table orders as 
  select * from snowflake_sample_data.tpch_sf1.orders order by o_orderkey asc limit 10;

alter table orders add column update_dt timestamp;
update orders 
  set update_dt = '2025-04-22 12:00:00';  -- current_timestamp();

select * from orders;

--- Create Updates to Apply to Orders table

-- pick 3 rows from Orders table
create or replace table orders_update as 
(select * from orders limit 3);

-- select o_orderkey, o_comment, update_dt from orders order by o_orderkey asc;  -- 1,2,3,4,5,6,7,32,33,34
select o_orderkey, o_comment, update_dt from orders_update order by o_orderkey asc; -- 1,2,3



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



select o_orderkey, o_comment, update_dt from orders_update order by o_orderkey asc;

/*
1	The Door is a Jar       2025-04-22 13:00:00            <-- First update to ORDER #1
1   The Door is Ajar        2025-04-22 13:05:00            <-- Second update to ORDER #1
1   The door is open.       2025-04-23 08:00:00            <-- Third update to ORDER #1
1   The door is closed.     2025-04-23 08:00:00            <-- Fourth update to ORDER #1 <-- occuring at the same instant as the Third update. 
2   updated comment         2025-04-23 13:00:01            <-- First update to ORDER #2
3   sly final accounts...   2025-04-22 12:00:00            <-- Unchanged ORDER #3
*/

-- To see the data before we updated the data, go back to BEFORE the first change...
-- select o_orderkey, o_comment, update_dt from orders_update BEFORE( STATEMENT => '01bbde68-0105-0bd9-0007-f3fb0001c3f6');



-- Eliminate Dupes by only processing the most recent update
WITH RankedOrders AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY O_ORDERKEY
            ORDER BY UPDATE_DT DESC
        ) as Row_No
    FROM
        orders_update
    WHERE
        UPDATE_DT IS NOT NULL -- Filter out NULL dates before ranking
)
SELECT
    *
FROM
    RankedOrders
WHERE
    Row_No = 1;

-- ADD ROW HASH for Change Detection 
alter table orders add column row_hash varchar;

update orders 
    set row_hash = SHA1(TO_JSON(OBJECT_CONSTRUCT(*)));
-- 

select * from orders;
select * from orders_update;



merge into ORDERS as TARGET
  using (
     SELECT latest_order.*, SHA1(TO_JSON(OBJECT_CONSTRUCT(*))) AS ROW_HASH
     FROM (
        with RankedOrders AS (
            select *, row_number() over (partition by o_orderkey order by update_dt desc) as row_no
            from orders_update )
        select * exclude row_no from RankedOrders where row_no = 1
        ) AS latest_order
    ) AS SOURCE
  on TARGET.O_ORDERKEY = SOURCE.O_ORDERKEY  
  
when MATCHED AND TARGET.ROW_HASH != SOURCE.ROW_HASH then
    UPDATE SET
        target.O_CUSTKEY = source.O_CUSTKEY,
        target.O_ORDERSTATUS = source.O_ORDERSTATUS,
        target.O_TOTALPRICE = source.O_TOTALPRICE,
        target.O_ORDERDATE = source.O_ORDERDATE,
        target.O_ORDERPRIORITY = source.O_ORDERPRIORITY,
        target.O_CLERK = source.O_CLERK,
        target.O_SHIPPRIORITY = source.O_SHIPPRIORITY,
        target.O_COMMENT = source.O_COMMENT,
        target.UPDATE_DT = source.UPDATE_DT,
        target.ROW_HASH = source.ROW_HASH
when NOT MATCHED then
    INSERT ( 
    	    O_ORDERKEY,O_CUSTKEY,O_ORDERSTATUS,O_TOTALPRICE,O_ORDERDATE,O_ORDERPRIORITY,
            O_CLERK,O_SHIPPRIORITY,O_COMMENT,UPDATE_DT,ROW_HASH )
        VALUES
            ( SOURCE.O_ORDERKEY, SOURCE.O_CUSTKEY,SOURCE.O_ORDERSTATUS,SOURCE. O_TOTALPRICE,
              SOURCE.O_ORDERDATE, SOURCE.O_ORDERPRIORITY, SOURCE.O_CLERK,SOURCE.O_SHIPPRIORITY,
              SOURCE.O_COMMENT,SOURCE.UPDATE_DT,SOURCE.ROW_HASH );

-- select get_ddl('table','customer_file');

select * from orders;

-- insert a new order
insert into orders_update (o_orderkey, o_comment, update_dt)
    values (10, 'Why did Order 10 come','2025-04-23 7:00' );

select * from orders_update;
    
