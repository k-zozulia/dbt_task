{{ config(materialized='view') }}

with src as (
    select * 
    from SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
), 

agg as (
    select
        c_nationkey,
        count(*) as customer_count,
        avg(c_acctbal) as avg_balance
    from src
    group by c_nationkey
)

select * from agg

