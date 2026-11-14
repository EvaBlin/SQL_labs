-- Лабораторная работа 4
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Посчитаны скидки, долги, возвраты, выручка и выполнение плана.
SET search_path TO 'pitanie', 'public';

-- О: выручка = quantity*unit_price*(1-discount_pct/100); отменённые исключены.
-- Скидка = quantity*unit_price*discount_pct/100. Доли считаются по суммам.
-- Брак: 100.0*SUM(defect_qty)/SUM(produced_qty).
-- Расход к норме: SUM(mc.quantity)/SUM(r.qty_per_unit*b.produced_qty).
-- А1. Группируем по менеджерам. DISTINCT нужен для подсчёта заказов.
SELECT e.employee_id,
       e.full_name,
       count(DISTINCT o.order_id) AS orders,
       round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1000000, 2) AS revenue_mln,
       round(sum(oi.quantity * oi.unit_price * oi.discount_pct / 100) / 1000000, 2) AS discount_mln,
       round(avg(oi.discount_pct), 2) AS avg_discount,
       max(oi.discount_pct) AS max_discount,
       count(*) FILTER (WHERE oi.discount_pct > 10) AS violations
FROM orders AS o
     INNER JOIN order_items AS oi USING (order_id)
     INNER JOIN employees AS e ON e.employee_id = o.employee_id
WHERE o.status <> 'Отменён'
GROUP BY e.employee_id, e.full_name
ORDER BY discount_mln DESC;

SELECT e.full_name, avg(oi.discount_pct) AS avg_discount
FROM orders AS o
     INNER JOIN order_items AS oi USING (order_id)
     INNER JOIN employees AS e ON e.employee_id = o.employee_id
WHERE o.status <> 'Отменён'
GROUP BY e.employee_id, e.full_name
HAVING avg(oi.discount_pct) > 10;

SELECT round(sum(oi.quantity * oi.unit_price * (oi.discount_pct - 10) / 100), 2) AS excess_rub
FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
WHERE o.status <> 'Отменён' AND oi.discount_pct > 10;

-- Средняя скидка по суммам учитывает размер продажи, AVG — только число позиций.
-- А2. Сначала складываем оплаты по каждому счёту, затем считаем долг клиента.
SELECT c.customer_id,
       c.customer_name,
       c.credit_limit,
       count(i.invoice_id) AS invoices,
       sum(i.amount) AS invoiced,
       sum(COALESCE(p.paid, 0)) AS paid,
       sum(i.amount - COALESCE(p.paid, 0)) AS debt,
       sum(i.amount - COALESCE(p.paid, 0)) FILTER (WHERE i.due_date < CAST('2026-01-01' AS date)) AS overdue,
       round(sum(i.amount - COALESCE(p.paid, 0)) / NULLIF(c.credit_limit, 0), 2) AS limit_ratio
FROM customers AS c
     INNER JOIN orders AS o USING (customer_id)
     INNER JOIN invoices AS i USING (order_id)
     LEFT JOIN (SELECT invoice_id, sum(amount) AS paid
                FROM payments
                GROUP BY invoice_id) AS p USING (invoice_id)
GROUP BY c.customer_id, c.customer_name, c.credit_limit
HAVING sum(i.amount - COALESCE(p.paid, 0)) > c.credit_limit;

SELECT c.customer_id,
       c.customer_name,
       sum(i.amount - COALESCE(p.paid, 0)) FILTER (WHERE i.due_date < CAST('2026-01-01' AS date)) AS overdue
FROM customers AS c
     INNER JOIN orders AS o USING (customer_id)
     INNER JOIN invoices AS i USING (order_id)
     LEFT JOIN (SELECT invoice_id, sum(amount) AS paid
                FROM payments
                GROUP BY invoice_id) AS p USING (invoice_id)
GROUP BY c.customer_id
ORDER BY overdue DESC NULLS LAST
LIMIT 5;

-- А3. Возвраты по округам, затем по регионам и товарам. Стоимость считаем по базовой цене.
SELECT COALESCE(r.federal_district, 'не указан') AS district,
       count(*) AS returns,
       sum(rt.quantity) AS units,
       count(*) FILTER (WHERE rt.reason = 'Истёк срок годности') AS expired
FROM returns AS rt
     INNER JOIN orders AS o USING (order_id)
     INNER JOIN customers AS c USING (customer_id)
     LEFT JOIN regions AS r USING (region_id)
GROUP BY r.federal_district
ORDER BY returns DESC;

SELECT COALESCE(r.region_name, 'не указан') AS region,
       p.product_name,
       p.shelf_life_days,
       count(*) AS returns,
       sum(rt.quantity * p.base_price) AS return_value
FROM returns AS rt
     INNER JOIN orders AS o USING (order_id)
     INNER JOIN customers AS c USING (customer_id)
     LEFT JOIN regions AS r USING (region_id)
     INNER JOIN products AS p USING (product_id)
GROUP BY r.region_name, p.product_id
HAVING count(*) >= 10
ORDER BY return_value DESC;

-- А4. Итоги по годам и кварталам. GROUPING показывает строки с итогами.
SELECT CASE
         WHEN  GROUPING(EXTRACT(YEAR FROM o.order_date)) = 1 THEN 'ВСЕГО'
         ELSE CAST(EXTRACT(YEAR FROM o.order_date) AS text)
       END AS year,
       CASE
         WHEN  GROUPING(EXTRACT(QUARTER FROM o.order_date)) = 1 THEN 'Итого за год'
         ELSE CAST(EXTRACT(QUARTER FROM o.order_date) AS text)
       END AS quarter,
       round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1000000, 2) AS revenue_mln
FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
WHERE o.status <> 'Отменён'
GROUP BY ROLLUP (EXTRACT(YEAR FROM o.order_date), EXTRACT(QUARTER FROM o.order_date))
ORDER BY year, quarter;

-- А5. План и продажи по категориям, годам и полугодиям считаем отдельно.
SELECT pc.category_name,
       pl.year,
       pl.half,
       round(pl.plan_amount / 1000000, 2) AS plan_mln,
       round(COALESCE(f.revenue, 0) / 1000000, 2) AS fact_mln,
       round(100 * COALESCE(f.revenue, 0) / NULLIF(pl.plan_amount, 0), 1) AS execution_pct
FROM (SELECT category_id,
             plan_year AS year,
             CASE
               WHEN plan_month <= 6 THEN 1
               ELSE 2
             END AS half,
             sum(plan_amount) AS plan_amount
      FROM sales_plan
      GROUP BY category_id, plan_year, CASE WHEN plan_month <= 6 THEN 1 ELSE 2 END) AS pl
     INNER JOIN product_categories AS pc USING (category_id)
     LEFT JOIN (SELECT cat.parent_category_id AS category_id,
                       EXTRACT(YEAR FROM o.order_date) AS year,
                       CASE
                         WHEN EXTRACT(MONTH FROM o.order_date) <= 6 THEN 1
                         ELSE 2
                       END AS half,
                       sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
                FROM orders AS o
                     INNER JOIN order_items AS oi USING (order_id)
                     INNER JOIN products AS p USING (product_id)
                     INNER JOIN product_categories AS cat USING (category_id)
                WHERE o.status <> 'Отменён'
                GROUP BY cat.parent_category_id,
                         EXTRACT(YEAR FROM o.order_date),
                         CASE
                           WHEN EXTRACT(MONTH FROM o.order_date) <= 6 THEN 1
                           ELSE 2
                         END) AS f ON (f.category_id, f.year, f.half) = (pl.category_id, pl.year, pl.half)
ORDER BY execution_pct;

-- А6. Сравниваем расходы и выручку по кварталам. Это ещё не доказывает пользу рекламы.
SELECT f.quarter,
       f.revenue,
       e.marketing,
       round(100 * e.marketing / NULLIF(f.revenue, 0), 2) AS marketing_pct
FROM (SELECT date_trunc('quarter', o.order_date) AS quarter,
             sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
      FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
      WHERE o.status <> 'Отменён'
      GROUP BY 1) AS f
     LEFT JOIN (SELECT date_trunc('quarter', expense_date) AS quarter,
                       sum(amount) AS marketing
                FROM expenses
                WHERE expense_category = 'Маркетинг'
                GROUP BY 1) AS e USING (quarter)
ORDER BY quarter;

-- А7
SELECT inn,
       count(*) AS cards,
       string_agg(customer_name, '; ' ORDER BY customer_id) AS names,
       array_agg(customer_id ORDER BY customer_id) AS ids,
       count(DISTINCT manager_id) AS managers
FROM customers
GROUP BY inn
HAVING count(*) > 1;

-- А8. Итоги по каналам продаж и годам.
SELECT CASE
         WHEN  GROUPING(o.channel) = 1 THEN 'Итого'
         ELSE o.channel
       END AS channel,
       CASE
         WHEN  GROUPING(EXTRACT(YEAR FROM o.order_date)) = 1 THEN 'Итого'
         ELSE CAST(EXTRACT(YEAR FROM o.order_date) AS text)
       END AS year,
       sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
WHERE o.status <> 'Отменён'
GROUP BY GROUPING SETS ((o.channel, EXTRACT(YEAR FROM o.order_date)),
                        o.channel,
                        EXTRACT(YEAR FROM o.order_date),
                        ());

SELECT sales_channel, EXTRACT(YEAR FROM expense_date) AS year, sum(amount) AS expenses
FROM expenses
WHERE sales_channel IS NOT NULL
GROUP BY sales_channel, EXTRACT(YEAR FROM expense_date)
ORDER BY sales_channel, year;

-- А9*
SELECT CASE
         WHEN  GROUPING(c.customer_type) = 1 THEN 'Итого'
         ELSE c.customer_type
       END AS customer_type,
       CASE
         WHEN  GROUPING(o.channel) = 1 THEN 'Итого'
         ELSE o.channel
       END AS channel,
       sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue,
       avg(oi.discount_pct) AS avg_discount
FROM orders AS o
     INNER JOIN customers AS c USING (customer_id)
     INNER JOIN order_items AS oi USING (order_id)
WHERE o.status <> 'Отменён'
  AND o.order_date >= CAST('2025-01-01' AS date)
  AND o.order_date < CAST('2026-01-01' AS date)
GROUP BY CUBE (c.customer_type, o.channel);

-- А6, ответ на вопрос: рост выручки IV квартала год к году.
SELECT round(100.0 * (sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) FILTER (WHERE o.order_date >= CAST('2025-10-01' AS date)) / NULLIF(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) FILTER (WHERE o.order_date < CAST('2025-01-01' AS date)),
                                                                                                                                                        0) - 1),
             2) AS q4_yoy_pct
FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
WHERE o.status <> 'Отменён'
  AND ((o.order_date >= CAST('2024-10-01' AS date)
    AND o.order_date < CAST('2025-01-01' AS date))
    OR (o.order_date >= CAST('2025-10-01' AS date)
    AND o.order_date < CAST('2026-01-01' AS date)));
-- А5. Кондитерские изделия во втором полугодии 2025 года — 80% плана.
-- А6. Выручка IV квартала выросла на 20,39% к прошлому году.

-- Вывод
-- Проблема                     | Объект                     | Потери или риск, руб. | Запрос
-- Скидки сверх 10%             | Все менеджеры              | 17 265 607,09         | А1
-- Долг сверх лимита            | Вектор                     |  3 907 600,45         | А2
-- Возвраты с истёкшим сроком   | Сибирский ФО               |  1 800 894,00         | А3
-- Недобор плана                | Кондитерские изделия       | 19 477 631,86         | А5
-- Рост расходов на маркетинг   | IV квартал 2025 к 2024     |  5 330 617,89         | А6
-- Расходы выше выручки         | Маркетплейс в 2025 году    | около 18 020 000      | А8
-- Без отменённых заказов скидки сверх 10% составляют 17 265 607,09 руб.
-- Долг Вектора больше лимита на 3 907 600,45 руб.
-- В Сибири 171 возврат связан с истёкшим сроком; по базовым ценам это 1 800 894 руб.
-- Это оценка стоимости товаров, а не сумма возвращённых денег.
-- За 2025 год расходы по маркетплейсу — 29,76 млн руб., выручка — 11,74 млн руб.
-- План по кондитерским изделиям во втором полугодии выполнен на 80%.
-- Расходы на маркетинг в IV квартале выросли на 5,33 млн руб., выручка выросла на 20,39%.
-- Чтобы оценить окупаемость рекламы, нужно проверить, сколько продаж принесла кампания.
