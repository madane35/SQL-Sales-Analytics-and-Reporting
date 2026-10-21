use sales;
SELECT 
    YEAR(order_date) AS order_year,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS cust_count,
    COUNT(quantity) AS total_quantity
FROM
    fact_sales
WHERE
    YEAR(order_date) IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date);

-- Calculate the total sales per month and running total of sales over time
select 
order_date,total_sales,sum(total_sales) over(order by order_date) as running_total_sales from (
select 
year(order_date) as order_date,
sum(sales_amount) as total_sales
from fact_sales
where year(order_date) is not null
group by year(order_date))t;

# Performance Analysis

 -- Analyze the yearly performance of products by comparing their sales to both the average sales performace of the product an the previous year sales
select order_date,product_name,total_sales ,avg(total_sales) over (partition by product_name) as avg_sales,lag(total_sales) over(partition by product_name order by order_date) as Pervious_year_sales from
(select year(f.order_date) as order_date,sum(f.sales_amount) as total_sales  ,p.product_name as product_name
from fact_sales f left join dim_products p on f.product_key = p.product_key
where year(order_date) is not null
group by year(f.order_date),p.product_name
) t;

-- What categories contribute the most to overall sales
with category_sales as (Select p.category,sum(f.sales_amount) as total_sales from fact_sales f left join dim_products p on f.product_key=p.product_key 
group by p.category)

select category,total_sales,
sum(total_sales) over() as overall_sales,
concat(round((total_sales/sum(total_sales) over())*100,2),'%') as percentage 
from category_sales
order by total_sales desc;



# Data Segmentation
-- segment product into cost range and count how amny product fall into each segment
with product_segment as(select product_key,product_name,cost,
case when cost < 100 then 'Below 100'
	 when cost between 100 and 500 then '100-500'
     when cost between 500 and 1000 then '500-1000'
     else 'above 1000'
     end  as cost_range
from dim_products)
select count(product_key) as total_product ,cost_range
from product_segment
group by cost_range
order by total_product desc;

-- group customers into three segment based on their spending behavioure
SELECT 
    customer_range, COUNT(*) AS total_cust
FROM
    (SELECT 
        customer_key,
            TIMESTAMPDIFF(MONTH, first_date, last_date) AS Month,
            total_sales,
            CASE
                WHEN
                    TIMESTAMPDIFF(MONTH, first_date, last_date) >= 12
                        AND total_sales >= 5000
                THEN
                    'VIP'
                WHEN
                    TIMESTAMPDIFF(MONTH, first_date, last_date) >= 12
                        AND total_sales < 5000
                THEN
                    'REGULAR'
                ELSE 'NEW'
            END customer_range
    FROM
        (SELECT 
        customer_key,
            MIN(order_date) AS first_date,
            MAX(order_date) AS last_date,
            SUM(sales_amount) AS total_sales
    FROM
        fact_sales
    GROUP BY customer_key) t) customer_segments
GROUP BY customer_range;


# Reporting
create view customer_report as-- Retrives core columns from tables
with base_query as (SELECT 
    f.order_number,
    c.customer_key,
    c.customer_number,
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    TIMESTAMPDIFF(YEAR,
        c.birthdate,
        CURDATE()) AS age,
    f.product_key,
    f.order_date,
    f.quantity,
    f.sales_amount
FROM
    fact_sales f
        LEFT JOIN
    dim_customers c ON f.customer_key = c.customer_key
WHERE
    order_date IS NOT NULL)
    
-- Customer Aggregation
, customer_aggregation as (select customer_key,customer_number,customer_name,age,
count(distinct order_number) as total_orders,
sum(sales_amount) as total_sales,
sum(quantity) as total_quantity,
count(distinct product_key) as total_products,
max(order_date ) as last_order_date,
timestampdiff(month,min(order_date),max(order_date)) as lifespan
from base_query
group by customer_key,customer_number,customer_name,age)

SELECT 
    customer_key,
    customer_number,
    customer_name,
    age,
    CASE
        WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'REGULAR'
        ELSE 'NEW'
    END AS customer_segment,
    total_orders,
    total_sales,
    -- Avg_Order_Value
    case when total_sales = 0 then 0
    else total_sales/ total_orders
    end as avg_order_value,
    -- avg_monthly_spend
    case when total_sales = 0 then 0
    else total_sales/lifespan
    end as avg_monthly_spend,
    total_quantity,
    total_products,
    last_order_date,
    timestampdiff( month,last_order_date,curdate()) as recency
FROM
    customer_aggregation;
    
# Product Report
create view product_report as (with product_info as (SELECT 
    p.product_key,
	p.product_name,
    p.category,
    p.subcategory,
    p.cost,
    f.customer_key,
    f.order_number,
    f.order_date,
    f.sales_amount,
    f.quantity,
    f.price
FROM
    fact_sales f
        LEFT JOIN
    dim_products p ON f.product_key = p.product_key
    where order_date is not null),
    
product_agg as (SELECT 
    product_key,
	product_name,
    category,
    subcategory,
    cost,COUNT(DISTINCT order_number) AS total_order,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS sold_quantity,
    COUNT(DISTINCT customer_key) AS total_customer,
    TIMESTAMPDIFF(MONTH,
        MIN(order_date),
        MAX(order_date)) AS lifespan,
	max(order_date) as last_order_date
FROM
    product_info
group by  product_key,
	product_name,
    category,
    subcategory,
    cost)
    
    
select product_key,
	product_name,
    category,
    subcategory,
    cost,last_order_date,
    timestampdiff(month,last_order_date,curdate()) as recency_in_month,
    case
		when total_sales >= 50000 then 'HIGH-PERFORMANCE'
        when total_sales >= 10000 then 'MID-PERFORMANCE'
        ELSE 'LOW-PERFORMANCE'
	END AS product_segment,
    lifespan,
    total_order,
    total_sales,
    sold_quantity,
	total_customer,
    case
		when total_order  = 0 then 0
        else total_sales / total_order
	end as avg_order_revenue,
    
    case 
		when lifespan = 0 then total_sales
        else total_sales / lifespan
	end as avg_monthly_revenue
from product_agg)









