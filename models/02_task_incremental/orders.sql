{{ config(
    materialized='incremental',
    unique_key='order_key',
    incremental_strategy='merge'
) }}

with src as (
    select 
        o_orderkey as order_key,
        o_custkey as customer_key,
        o_orderstatus as order_status,
        o_totalprice as total_price,
        o_orderdate as order_date,
        o_orderpriority as order_priority,
        o_clerk as clerk,
        o_shippriority as ship_priority,
        current_timestamp() as loaded_at
    from SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS

    {% if is_incremental() %}
        where o_orderdate > (
            select dateadd(day, -3, max(order_date))
            from {{this}}
        )
    {% endif %}
)

select * from src