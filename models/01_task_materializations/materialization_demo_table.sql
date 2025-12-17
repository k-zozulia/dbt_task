{{ config(materialized='table') }}

with src as (
    select * 
    from {{source("tpch", "customer")}}
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
