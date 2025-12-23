{{ config(
    materialized='table',
    cluster_by=['ship_date', 'return_flag', 'ship_mode']
) }}

with source as (
    select * from {{ source('tpch', 'lineitem') }}
),

fact_table as (
    select
        l_orderkey as order_key,
        l_partkey as part_key,
        l_suppkey as supplier_key,
        l_linenumber as line_number,
        l_quantity as quantity,
        l_extendedprice as extended_price,
        l_discount as discount,
        l_tax as tax,
        l_returnflag as return_flag,
        l_linestatus as line_status,
        l_shipdate as ship_date,
        l_commitdate as commit_date,
        l_receiptdate as receipt_date,
        l_shipinstruct as ship_instructions,
        l_shipmode as ship_mode,
        
        -- Derived metrics
        l_extendedprice * (1 - l_discount) as discounted_price,
        l_extendedprice * (1 - l_discount) * (1 + l_tax) as final_price,
        
        -- Date parts for analysis
        year(l_shipdate) as ship_year,
        month(l_shipdate) as ship_month,
        quarter(l_shipdate) as ship_quarter,
        
        current_timestamp() as loaded_at
    from source
)

select * from fact_table