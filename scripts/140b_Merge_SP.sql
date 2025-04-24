--  140b Create Merge SP, Run It, Show final TARGET and SOURCE tables
--  
--  The purpose of this script is to demonstrate how to create a Stored Procedure around the MERGE SP
--  Remmber this is just a TOY don't put TOYs into production (without serious hardening!)
--
--  The audience is folks new to Snowflake with a bit of SQL understanding.
--
--  Author:         John Miller
--  Last Updated:   2025-04-23

CREATE OR REPLACE PROCEDURE SP_MERGE_DEDUP(
  TARGET_TABLE VARCHAR(16777216),
  SOURCE_TABLE VARCHAR(16777216)
)
RETURNS STRING
LANGUAGE SQL
EXECUTE as caller 
AS 

DECLARE
  RETURN_MESSAGE STRING;
--  MISSING_PARAMETER EXCEPTION (-20002, 'PROCEDURE IS MISSING A PARAMETER!');
     

BEGIN
 
  -- IF (TARGET_TABLE IS NULL) -- OR (SOURCE_TABLE IS NULL) 
  --   THEN RAISE MISSING_PARAMETER;
  -- END IF;  

  merge into IDENTIFIER(:TARGET_TABLE) as TARGET  -- replaced orders with TARGET_TABLE identifer
  using (
     SELECT latest_order.*, SHA1(TO_JSON(OBJECT_CONSTRUCT(*))) AS ROW_HASH
     FROM (
        with RankedOrders AS (
            select *, row_number() over (partition by o_orderkey order by update_dt desc) as row_no
            from IDENTIFIER(:SOURCE_TABLE) )  -- replaced orders_update with SOURCE_TABLE identifer
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

  -- Return message

  RETURN_MESSAGE := (
    select 'Rows Inserted:  ' || $1 || '\n ' || 'Rows Updated: ' || $2 || '\n' 
    from  table(result_scan( last_query_id() ) ));

RETURN RETURN_MESSAGE;

END;


CALL SP_MERGE_DEDUP('ORDERS','ORDERS_UPDATE');


(select 'TARGET ROW' as ROW_TYPE, o_orderkey, o_comment, update_dt from orders order by o_orderkey asc)
union all
(select 'SOURCE ROW' as ROW_TYPE, o_orderkey, o_comment, update_dt from orders_update order by o_orderkey asc, update_dt asc )
;
