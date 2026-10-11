-- Retailker Metric request
WITH filtered_sales AS (
  SELECT
    CASE
      WHEN retailers.Country IN ('United States', 'Canada') THEN 'North_America'
      WHEN retailers.Country IN ('United Kingdom', 'Germany', 'Switzerland', 'Netherlands', 'Spain', 'France', 'Belgium', 'Finland', 'Austria', 'Italy', 'Sweden', 'Denmark') THEN 'Europe'
      WHEN retailers.Country IN ('Mexico', 'Brazil') THEN 'Latin_America'
      WHEN retailers.Country IN ('Japan', 'China', 'Korea', 'Singapore') THEN 'Asia'
      ELSE 'Australia'
    END AS Region,
    DATE(EXTRACT(YEAR FROM sales.Date), EXTRACT(MONTH FROM sales.Date), 1) AS Month,
    retailers.Retailer_name,
    sales.Quantity * sales.Unit_sale_price AS Sales
  FROM `gooutside-510108.GoOutside.daily_sales` AS sales
  JOIN `gooutside-510108.GoOutside.retailers` AS retailers
    ON sales.Retailer_code = retailers.Retailer_code
  WHERE sales.Date >= PARSE_DATE('%Y%m%d', @DS_START_DATE)
    AND sales.Date < DATE_ADD(PARSE_DATE('%Y%m%d', @DS_END_DATE), INTERVAL 1 DAY)
),

monthly_retailer AS (
  SELECT
    Region,
    Month,
    Retailer_name,
    SUM(Sales) AS Sales_Volume
  FROM filtered_sales
  GROUP BY Region, Month, Retailer_name
),

retailer_total AS (
  SELECT
    Region,
    Retailer_name,
    SUM(Sales_Volume) AS Sales_Volume
  FROM monthly_retailer
  GROUP BY Region, Retailer_name
),

ranked AS (
  SELECT
    Region,
    Retailer_name,
    Sales_Volume,
    ROW_NUMBER() OVER (PARTITION BY Region ORDER BY Sales_Volume DESC) AS Retailer_Rank
  FROM retailer_total
),

market AS (
  SELECT
    Region,
    SUM(Sales_Volume) AS Total_Sales,
    SUM(CASE WHEN Retailer_Rank <= 3 THEN Sales_Volume ELSE 0 END) AS Top_3_Sales
  FROM ranked
  GROUP BY Region
),

monthly_market AS (
  SELECT
    Region,
    Month,
    SUM(Sales_Volume) AS Total_Sales,
    COUNT(DISTINCT Retailer_name) AS Retailer_Count,
    SAFE_DIVIDE(SUM(Sales_Volume), COUNT(DISTINCT Retailer_name)) AS Sales_Per_Retailer
  FROM monthly_retailer
  GROUP BY Region, Month
),

periods AS (
  SELECT
    Region,
    MIN(Month) AS Start_Month,
    MAX(Month) AS End_Month
  FROM monthly_market
  GROUP BY Region
),

growth AS (
  SELECT
    p.Region,
    p.Start_Month,
    p.End_Month,
    SAFE_DIVIDE(
      MAX(CASE WHEN mm.Month = p.End_Month THEN mm.Sales_Per_Retailer END),
      MAX(CASE WHEN mm.Month = p.Start_Month THEN mm.Sales_Per_Retailer END)
    ) - 1 AS Sales_Volume_Per_Retailer_Growth,
    SAFE_DIVIDE(
      MAX(CASE WHEN mm.Month = p.End_Month THEN mm.Retailer_Count END),
      MAX(CASE WHEN mm.Month = p.Start_Month THEN mm.Retailer_Count END)
    ) - 1 AS Retailer_Growth
  FROM periods AS p
  JOIN monthly_market AS mm
    ON mm.Region = p.Region
  GROUP BY p.Region, p.Start_Month, p.End_Month
),

final_market AS (
  SELECT
    Region,
    Total_Sales,
    Top_3_Sales,
    SAFE_DIVIDE(Top_3_Sales, Total_Sales) AS Top_3_Share,
    CASE
      WHEN SAFE_DIVIDE(Top_3_Sales, Total_Sales) >= 0.6 THEN 'Dominant Market'
      ELSE 'Competitive Market'
    END AS Market_Strategy
  FROM market
)

SELECT
  mr.Region,
  mr.Month,
  mr.Retailer_name,
  mr.Sales_Volume,
  fm.Total_Sales,
  fm.Top_3_Sales,
  fm.Top_3_Share,
  fm.Market_Strategy,
  g.Start_Month,
  g.End_Month,
  g.Sales_Volume_Per_Retailer_Growth,
  g.Retailer_Growth,
  CASE
    WHEN fm.Market_Strategy = 'Dominant Market' THEN g.Sales_Volume_Per_Retailer_Growth
    ELSE g.Retailer_Growth
  END AS Growth,
  CASE
    WHEN fm.Market_Strategy = 'Dominant Market' THEN 'Sales Volume per Retailer'
    ELSE 'Retailer Count'
  END AS Growth_Type
FROM monthly_retailer AS mr
JOIN final_market AS fm
  ON mr.Region = fm.Region
JOIN growth AS g
  ON mr.Region = g.Region
ORDER BY mr.Region, mr.Month, mr.Retailer_name


-- Master table request
SELECT sales.Retailer_code, retailers.Retailer_name, retailers.Country,
    CASE
    WHEN country IN('United States', 'Canada') THEN 'North_America'
    WHEN country IN('United Kingdom', 'Germany', 'Switzerland', 'Netherlands', 'Spain', 'France', 'Belgium', 'Finland', 'Austria', 'Italy', 'Sweden', 'Denmark') THEN 'Europe'
    WHEN country IN('Mexico', 'Brazil') THEN 'Latin_America'
    WHEN country IN('Japan', 'China', 'Korea', 'Singapore') THEN 'Asia'
    ELSE 'Australia'
  END AS Region,
  retailers.Type, sales.Product_number, products.product, products.Product_type, products.Product_brand, methods.Order_method_type AS Order_method,
  sales.Date, EXTRACT(YEAR FROM sales.Date) AS Year,
  FORMAT_DATE('%Y-%m', sales.Date) AS Year_Month,
  sales.Quantity,
  ROUND(SAFE_DIVIDE(sales.Quantity,SUM(sales.Quantity) OVER ()) * 100, 2) AS Quantity_Percentage, 
  sales.Unit_price, products.Unit_cost, sales.Unit_sale_price,
  sales.Unit_price - sales.Unit_sale_price AS Discount_per_Unit,
  (sales.Unit_price - sales.Unit_sale_price) * sales.Quantity AS Discount_Total,
  ROUND(SAFE_DIVIDE(sales.Unit_price - sales.Unit_sale_price,sales.Unit_price) * 100, 2) AS Discount_Percentage,
  sales.quantity * sales.unit_sale_price AS Revenue,
  ROUND(sales.quantity * products.unit_cost, 2) AS Cost,
  ROUND((sales.quantity * sales.unit_sale_price) - (sales.quantity * products.unit_cost), 2) AS Profit,
  ((sales.quantity * sales.unit_sale_price) -(sales.quantity * products.unit_cost)) / SUM((sales.quantity * sales.unit_sale_price) - (sales.quantity * products.unit_cost)) OVER () * 100 AS Profit_Percentage,
  ROUND(SAFE_DIVIDE((sales.quantity * sales.unit_sale_price) -(sales.quantity * products.unit_cost),sales.quantity * sales.unit_sale_price) * 100, 2) AS Profit_Margin
FROM `gooutside-510108.GoOutside.daily_sales` AS sales
JOIN `gooutside-510108.GoOutside.products` AS products
  ON sales.Product_number = products.Product_number
JOIN `gooutside-510108.GoOutside.methods` AS methods
  ON methods.Order_method_code = sales.Order_method_code
JOIN `gooutside-510108.GoOutside.retailers` AS retailers
  ON retailers.Retailer_code = sales.Retailer_code;
  
  -- Metric finance table
  -- Using the Code of the master table as a subquery in order to get monthly info about increase or decrease in profit and quantity sold

WITH mastertable AS(
  SELECT
    sales.Retailer_code, retailers.Retailer_name, retailers.Country,
    CASE
    WHEN country IN('United States', 'Canada') THEN 'North_America'
    WHEN country IN('United Kingdom', 'Germany', 'Switzerland', 'Netherlands', 'Spain', 'France', 'Belgium', 'Finland', 'Austria', 'Italy', 'Sweden', 'Denmark') THEN 'Europe'
    WHEN country IN('Mexico', 'Brazil') THEN 'Latin_America'
    WHEN country IN('Japan', 'China', 'Korea', 'Singapore') THEN 'Asia'
    ELSE 'Australia'
  END AS Region,
  retailers.Type, sales.Product_number, products.product, products.Product_type, products.Product_brand, methods.Order_method_type AS Order_method,
  sales.Date, EXTRACT(YEAR FROM sales.Date) AS Year,
  FORMAT_DATE('%Y-%m', sales.Date) AS Year_Month,
  sales.Quantity,
  ROUND(SAFE_DIVIDE(sales.Quantity,SUM(sales.Quantity) OVER ()) * 100, 2) AS Quantity_Percentage, 
  sales.Unit_price, products.Unit_cost, sales.Unit_sale_price,
  sales.Unit_price - sales.Unit_sale_price AS Discount_per_Unit,
  (sales.Unit_price - sales.Unit_sale_price) * sales.Quantity AS Discount_Total,
  ROUND(SAFE_DIVIDE(sales.Unit_price - sales.Unit_sale_price,sales.Unit_price) * 100, 2) AS Discount_Percentage,
  sales.quantity * sales.unit_sale_price AS Revenue,
  ROUND(sales.quantity * products.unit_cost, 2) AS Cost,
  ROUND((sales.quantity * sales.unit_sale_price) - (sales.quantity * products.unit_cost), 2) AS Profit,
  ((sales.quantity * sales.unit_sale_price) -(sales.quantity * products.unit_cost)) / SUM((sales.quantity * sales.unit_sale_price) - (sales.quantity * products.unit_cost)) OVER () * 100 AS Profit_Percentage,
  ROUND(SAFE_DIVIDE((sales.quantity * sales.unit_sale_price) -(sales.quantity * products.unit_cost),sales.quantity * sales.unit_sale_price) * 100, 2) AS Profit_Margin
FROM `gooutside-510108.GoOutside.daily_sales` AS sales
JOIN `gooutside-510108.GoOutside.products` AS products
  ON sales.Product_number = products.Product_number
JOIN `gooutside-510108.GoOutside.methods` AS methods
  ON methods.Order_method_code = sales.Order_method_code
JOIN `gooutside-510108.GoOutside.retailers` AS retailers
  ON retailers.Retailer_code = sales.Retailer_code
WHERE Date >= DATE_SUB((SELECT MAX(Date) FROM `gooutside-510108.GoOutside.daily_sales`), INTERVAL 24 MONTH)),

-- in this section we create a table based on mastertable in order to be able to calculate the monthly increase or decrease in Quantity and profit in %.
monthly AS (
  SELECT
    Year_Month,
    SUM(Profit) AS Profit,
    SUM(Quantity) AS Quantity
  FROM mastertable
  GROUP BY Year_Month
)

-- now we create the final table containing monthly percantage increase in profit and produkts sold
SELECT
  Year_Month,
  Profit,
  Quantity,
  ROUND(SAFE_DIVIDE(Profit - Previous_Profit, Previous_Profit), 4) AS Profit_MoM_Percentage,
  ROUND(SAFE_DIVIDE(Quantity - Previous_Quantity, Previous_Quantity), 4) AS Quantity_MoM_Percentage
FROM (
  SELECT
    Year_Month,
    Profit,
    Quantity,
    LAG(Profit) OVER (ORDER BY Year_Month) AS Previous_Profit,
    LAG(Quantity) OVER (ORDER BY Year_Month) AS Previous_Quantity
  FROM monthly
)
ORDER BY Year_Month;