-- =========================================
-- DATABASE SETUP
-- =========================================
-- Create Database 
CREATE DATABASE saas_analytics_db;
-- Create Schema
CREATE SCHEMA saas;
-- =========================================
-- TABLE CREATION
-- =========================================
-- Customers Table
CREATE TABLE saas.customers(
    customer_id VARCHAR(20) PRIMARY KEY,
    customer_name VARCHAR(100),
    email VARCHAR(100),
    country VARCHAR(50),
    signup_date DATE,
    age INT,
    subscription_plan VARCHAR(30),
    churn VARCHAR(10)
);

-- Events Table
CREATE TABLE saas.events(
    event_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20),
    event_type VARCHAR(50),
    event_date DATE,
    device_type VARCHAR(20),
    traffic_source VARCHAR(30),
    session_duration_minutes INT,

    FOREIGN KEY (customer_id)
    REFERENCES saas.customers(customer_id)
);

-- Payments Table
CREATE TABLE saas.payments(
    payment_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(20),
    paid_amount NUMERIC(10,2),
    payment_date DATE,
    payment_status VARCHAR(20),
    payment_method VARCHAR(20),

    FOREIGN KEY (customer_id)
    REFERENCES saas.customers(customer_id)
);

-- Support Tickets Table
CREATE TABLE saas.support_tickets(
    ticket_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20),
    issue_type VARCHAR(100),
    priority VARCHAR(20),
    resolution_time_hours INT,
    ticket_status VARCHAR(20),
	support_channel VARCHAR(20),

    FOREIGN KEY (customer_id)
    REFERENCES saas.customers(customer_id)
);




-- =========================================
-- REVENUE ANALYSIS
-- =========================================

-- How many customers do we have?
SELECT
     COUNT(*) AS total_customers,
     ROUND(AVG(age),2) AS avg_age
FROM saas.customers;


-- What is total revenue?
SELECT 
     SUM(paid_amount) AS total_revenue 
FROM saas.payments
WHERE payment_status = 'Success';


-- Revenue By Plan
SELECT C.subscription_plan,
	   SUM(P.paid_amount) AS total_revenue
FROM saas.customers C
INNER JOIN saas.payments P
ON C.customer_id = P.customer_id
WHERE P.payment_status = 'Success'
GROUP BY C.subscription_plan
ORDER BY total_revenue DESC;


--Revenue BY Country
SELECT C.country,
	   SUM(P.paid_amount) AS total_revenue
FROM saas.customers C
INNER JOIN saas.payments P
ON  C.customer_id = P.customer_id
WHERE payment_status = 'Success'
GROUP BY C.country
ORDER BY total_revenue DESC;


-- Which countries generate more than ₹100,000 revenue?
SELECT C.country,
       SUM(P.paid_amount) AS total_revenue
FROM saas.customers C
JOIN saas.payments P
ON C.customer_id = P.customer_id
WHERE P.payment_status = 'Success'
GROUP BY C.country
HAVING SUM(P.paid_amount) > 100000
ORDER BY total_revenue DESC;


-- Top 10 Customers
WITH customer_revenue AS (
SELECT C.customer_id,
       C.customer_name,
	   SUM(P.paid_amount) AS total_revenue
FROM saas.customers C
JOIN saas.payments P
ON C.customer_id = P.customer_id
WHERE P.payment_status = 'Success'
GROUP BY C.customer_id,
       C.customer_name
ORDER BY total_revenue DESC
LIMIT 10
)
SELECT *,
       ROW_NUMBER() OVER(ORDER BY total_revenue DESC) AS customer_rank
FROM customer_revenue
LIMIT 10;


-- Revenue Segmentation
WITH customer_segment AS (
SELECT 
     C.customer_id,
	 COALESCE(SUM(P.paid_amount),0) AS total_revenue,
     CASE
        WHEN COALESCE(SUM(P.paid_amount),0) >= 5000 THEN 'High Value'
        WHEN COALESCE(SUM(P.paid_amount),0) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
     END AS customer_segment
FROM saas.customers C
LEFT JOIN saas.payments P
ON C.customer_id = P.customer_id
AND P.payment_status = 'Success'
GROUP BY C.customer_id
)
SELECT
    customer_segment,
    COUNT(customer_id) AS customers,
    SUM(total_revenue) AS segment_revenue
FROM customer_segment
GROUP BY customer_segment
ORDER BY segment_revenue DESC;


-- Revenue Contribution by Segment
WITH customer_segment AS (
SELECT 
     C.customer_id,
	 COALESCE(SUM(P.paid_amount),0) AS total_revenue,
     CASE
        WHEN COALESCE(SUM(P.paid_amount),0) >= 5000 THEN 'High Value'
        WHEN COALESCE(SUM(P.paid_amount),0) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
     END AS customer_segment
FROM saas.customers C
LEFT JOIN saas.payments P
ON C.customer_id = P.customer_id
AND P.payment_status = 'Success'
GROUP BY C.customer_id
)
SELECT customer_segment,
       COUNT(customer_id) AS total_customers,
	   SUM(total_revenue) AS total_segment_revenue,
	   ROUND(100.0*SUM(total_revenue)/SUM(SUM(total_revenue))OVER(),2)
	   AS revenue_percentage
FROM customer_segment
GROUP BY customer_segment
ORDER BY revenue_percentage DESC;


-- Month-over-Month Revenue Trend Analysis
WITH monthly_revenue AS (
SELECT
    DATE_TRUNC('month', payment_date) AS month,
    SUM(paid_amount) AS revenue
FROM saas.payments
WHERE payment_status='Success'
GROUP BY month
)

SELECT
    month,
    revenue,
    revenue -LAG(revenue)OVER(ORDER BY month) AS revenue_change
FROM monthly_revenue;


-- =========================================
-- CHURN ANALYSIS
-- =========================================

-- What is overall churn rate
SELECT
    ROUND(100.0 * AVG(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END),2
    ) AS churn_rate
FROM saas.customers;


-- Churn by Segment
WITH customer_segment AS (
SELECT
     C.customer_id,
     C.churn,
     COALESCE(SUM(P.paid_amount),0) AS total_revenue,
     CASE
        WHEN COALESCE(SUM(P.paid_amount),0) >= 5000 THEN 'High Value'
        WHEN COALESCE(SUM(P.paid_amount),0) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
     END AS customer_segment
FROM saas.customers C
LEFT JOIN saas.payments P
ON C.customer_id = P.customer_id
AND P.payment_status = 'Success'
GROUP BY
    C.customer_id,
    C.churn
)
SELECT
    customer_segment,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
	ROUND(100.0 * AVG(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END),2
    ) AS churn_rate
FROM customer_segment
GROUP BY customer_segment
ORDER BY churn_rate DESC;


-- Feature Usage Among Churned Customers
SELECT
    E.event_type,
    COUNT(*) AS usage_count,
	ROUND( 100.0*COUNT(*)/SUM(COUNT(*))OVER(),2) AS usage_percentage
FROM saas.events E
INNER JOIN saas.customers C
ON E.customer_id = C.customer_id
WHERE C.churn = 'Yes'
GROUP BY E.event_type
ORDER BY usage_count DESC;


-- Device Churn
SELECT
    E.device_type,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN c.churn = 'Yes' THEN c.customer_id END
    ) AS churned_customers,
    ROUND(100.0 * COUNT( DISTINCT CASE WHEN c.churn = 'Yes' THEN c.customer_id END)
	      / COUNT(DISTINCT c.customer_id),2
    ) AS churn_rate
FROM saas.events E
INNER JOIN saas.customers C
ON E.customer_id = C.customer_id
GROUP BY E.device_type
ORDER BY churn_rate DESC;



-- =========================================
-- ENGAGEMENT ANALYSIS
-- =========================================

-- Feature Usage Analysis
SELECT
    event_type,
    COUNT(*) AS usage_count,
	ROUND( 100.0*COUNT(*)/SUM(COUNT(*))OVER(),2) AS usage_percentage
FROM saas.events
GROUP BY event_type
ORDER BY usage_count DESC;


-- Device Usage Analysis
SELECT
    device_type,
    COUNT(*) AS usage_count,
	ROUND( 100.0*COUNT(*)/SUM(COUNT(*))OVER(),2) AS usage_percentage
FROM saas.events
GROUP BY device_type
ORDER BY usage_count DESC;


-- Customer Engagement by Value Segment
WITH payment_summary AS (
SELECT
      customer_id,
      SUM(paid_amount) AS total_revenue
FROM saas.payments
WHERE payment_status = 'Success'
GROUP BY customer_id
),

event_summary AS (
SELECT
     customer_id,
     COUNT(*) AS total_events,
     AVG(session_duration_minutes) AS avg_session_duration
FROM saas.events
GROUP BY customer_id
),
customer_segment AS (
SELECT
     c.customer_id,
     COALESCE(p.total_revenue,0) AS total_revenue,
     COALESCE(e.total_events,0) AS total_events,
     COALESCE(e.avg_session_duration,0) AS avg_session_duration,
     CASE
     WHEN COALESCE(p.total_revenue,0) >= 5000 THEN 'High Value'
     WHEN COALESCE(p.total_revenue,0) >= 1000 THEN 'Medium Value'
     ELSE 'Low Value'
     END AS customer_segment

FROM saas.customers c
LEFT JOIN payment_summary p
ON c.customer_id = p.customer_id
LEFT JOIN event_summary e
ON c.customer_id = e.customer_id
)
SELECT
customer_segment,
COUNT(*) AS total_customers,
ROUND(AVG(total_events),2) AS avg_events,
ROUND(AVG(avg_session_duration),2) AS avg_session_duration
FROM customer_segment
GROUP BY customer_segment
ORDER BY avg_events DESC;


-- =========================================
-- SUPPORT ANALYSIS
-- =========================================

-- Support Ticket Distribution
SELECT
    issue_type,
    COUNT(*) AS total_tickets,
	ROUND( 100.0*COUNT(*)/SUM(COUNT(*))OVER(),2) AS usage_percentage
FROM saas.support_tickets
GROUP BY issue_type
ORDER BY total_tickets DESC;

-- High Priority Issues Analysis
SELECT
    issue_type,
    COUNT(*) AS total_tickets,
    COUNT( CASE WHEN priority = 'High' THEN 1 END
    ) AS high_priority_tickets
FROM saas.support_tickets
GROUP BY issue_type
ORDER BY high_priority_tickets DESC;

-- Resolution Time Analysis
SELECT
    issue_type,
    ROUND(
        AVG(resolution_time_hours),
        2
    ) AS avg_resolution_time
FROM saas.support_tickets
GROUP BY issue_type
ORDER BY avg_resolution_time DESC;

-- Support Burden by Customer Segment
WITH payment_summary AS (
SELECT
    customer_id,
    SUM(paid_amount) AS total_revenue
FROM saas.payments
WHERE payment_status = 'Success'
GROUP BY customer_id
),

support_summary AS (
SELECT
    customer_id,
    COUNT(ticket_id) AS total_tickets
FROM saas.support_tickets
GROUP BY customer_id
),

customer_segment AS (
SELECT
    C.customer_id,
    COALESCE(P.total_revenue,0) AS total_revenue,
    COALESCE(S.total_tickets,0) AS total_tickets,
    CASE
        WHEN COALESCE(P.total_revenue,0) >= 5000 THEN 'High Value'
        WHEN COALESCE(P.total_revenue,0) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_segment
FROM saas.customers C
LEFT JOIN payment_summary P
ON C.customer_id = P.customer_id
LEFT JOIN support_summary S
ON C.customer_id = S.customer_id
)
SELECT
    customer_segment,
    COUNT(*) AS total_customers,
    SUM(total_tickets) AS total_support_tickets,
    ROUND(AVG(total_tickets),2) AS avg_tickets_per_customer
FROM customer_segment
GROUP BY customer_segment
ORDER BY total_support_tickets DESC;

-- Support Tickets vs Churn
WITH support_summary AS (
SELECT
    customer_id,
    COUNT(ticket_id) AS total_tickets
FROM saas.support_tickets
GROUP BY customer_id
)
SELECT
    C.churn,
    COUNT(*) AS total_customers,
    ROUND(
        AVG(COALESCE(s.total_tickets,0)),2
        ) AS avg_tickets
FROM saas.customers C
LEFT JOIN support_summary S
ON C.customer_id = S.customer_id
GROUP BY C.churn;


-- Churn Rate by Ticket Group
WITH support_summary AS (
SELECT
    customer_id,
    COUNT(ticket_id) AS total_tickets
FROM saas.support_tickets
GROUP BY customer_id
),

customer_tickets AS (
SELECT
    c.customer_id,
    c.churn,
    COALESCE(s.total_tickets,0) AS total_tickets,
    CASE
        WHEN COALESCE(s.total_tickets,0) = 0 THEN '0 Tickets'
        WHEN COALESCE(s.total_tickets,0) = 1 THEN '1 Ticket'
        WHEN COALESCE(s.total_tickets,0) = 2 THEN '2 Tickets'
        ELSE '3+ Tickets'
    END AS ticket_group
FROM saas.customers c
LEFT JOIN support_summary s
ON c.customer_id = s.customer_id
)
SELECT
    ticket_group,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END
    ) AS churned_customers,
    ROUND(100.0 * SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END
        )/ COUNT(*),2
        ) AS churn_rate
FROM customer_tickets
GROUP BY ticket_group
ORDER BY ticket_group;


-- =========================================
-- CUSTOMER RISK ANALYSIS
-- =========================================

-- Customer Risk Classification
WITH payment_summary AS (
SELECT
    customer_id,
    SUM(paid_amount) AS total_revenue
FROM saas.payments
WHERE payment_status = 'Success'
GROUP BY customer_id
),

event_summary AS (
SELECT
    customer_id,
    COUNT(event_id) AS total_events,
    MAX(event_date) AS last_activity_date
FROM saas.events
GROUP BY customer_id
),

support_summary AS (
SELECT
    customer_id,
    COUNT(ticket_id) AS total_tickets,
    COUNT(CASE WHEN priority = 'High' THEN 1 END
    ) AS high_priority_tickets
FROM saas.support_tickets
GROUP BY customer_id
)
SELECT
    C.customer_id,
    C.customer_name,
    C.subscription_plan,
    COALESCE(P.total_revenue,0) AS total_revenue,
    COALESCE(E.total_events,0) AS total_events,
    COALESCE(S.total_tickets,0) AS total_tickets,
    COALESCE(S.high_priority_tickets,0) AS high_priority_tickets,
    E.last_activity_date,
    CASE WHEN total_events < 10
         AND total_tickets >= 4
    THEN 'Critical'
    WHEN total_events < 20
         AND total_tickets >= 3
    THEN 'At Risk'
    ELSE 'Healthy'
    END AS customer_status
FROM saas.customers C
LEFT JOIN payment_summary P
ON C.customer_id = P.customer_id
LEFT JOIN event_summary E
ON C.customer_id = E.customer_id
LEFT JOIN support_summary S
ON C.customer_id = S.customer_id
ORDER BY customer_status,
         total_tickets DESC
LIMIT 20;


-- =========================================
-- CUSTOMER PROFILE ANALYSIS
-- =========================================

--Which email providers do our customers use?
SELECT
    SPLIT_PART(email,'@',2) AS email_domain,
    COUNT(*) AS customers
FROM saas.customers
GROUP BY email_domain
ORDER BY customers DESC;
