{% docs order_key %}
Unique identifier for each order. Primary key from the TPC-H Orders table.
{% enddocs %}

{% docs customer_key %}
Foreign key reference to the Customer table. Links orders to customers.
{% enddocs %}

{% docs order_status %}
Current status of the order:
- **O** = Open (in progress)
- **F** = Fulfilled (completed)
- **P** = Partial (partially fulfilled)
{% enddocs %}

{% docs total_price %}
Total monetary value of the order in USD, including all line items.
{% enddocs %}

{% docs tpch_source %}
Data sourced from Snowflake's TPC-H benchmark dataset (Scale Factor 1).
Contains standardized e-commerce transaction data for testing and development.
{% enddocs %}

{% docs fct_orders_model %}
Production-ready fact table for order analytics.
Combines order details with derived business metrics for reporting and dashboards.
Refreshed on each dbt run.
{% enddocs %}

{% docs fulfillment_status %}
Combined status showing completion and priority:
- Completed High Priority
- Completed Normal
- Pending High Priority
- Pending Normal
{% enddocs %}
