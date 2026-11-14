-- Лабораторная работа 8
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Посчитаны рейтинги, выполнение плана, классы клиентов и динамика долга.
SET search_path TO 'pitanie', 'public';

-- Общая часть: выручка = quantity*unit_price*(1-discount_pct/100), без отменённых заказов.
-- Брак = 100.0*defect_qty/produced_qty, простой в часах = EXTRACT(EPOCH FROM end_time-start_time)/3600.

-- А1. Рейтинг менеджеров по кварталам.
WITH q AS (
         SELECT o.employee_id,
                EXTRACT(QUARTER FROM o.order_date) AS qtr,
                sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue,
                avg(oi.discount_pct) AS discount
         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
         WHERE o.status <> 'Отменён'
           AND o.order_date >= CAST('2025-01-01' AS date)
           AND o.order_date < CAST('2026-01-01' AS date)
         GROUP BY 1, 2
       )
  SELECT e.full_name,
         q.*,
         rank() OVER (PARTITION BY qtr
                      ORDER BY revenue DESC) AS revenue_rank,
         dense_rank() OVER (PARTITION BY qtr
                            ORDER BY discount DESC) AS discount_rank
  FROM q INNER JOIN employees AS e USING (employee_id)
  ORDER BY qtr, revenue_rank;

-- А2. План и продажи за каждый месяц, затем суммы с начала года.
WITH f AS (
         SELECT CAST(date_trunc('month', o.order_date) AS date) AS month,
                sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
         WHERE o.status <> 'Отменён'
         GROUP BY 1
       ),
     pl AS (
         SELECT to_date(plan_year || '-' || plan_month || '-01', 'YYYY-MM-DD') AS month, sum(plan_amount) AS plan
         FROM sales_plan
         GROUP BY 1
       ),
     m AS (
         SELECT pl.month, COALESCE(f.revenue, 0) AS revenue, pl.plan
         FROM pl LEFT JOIN f USING (month)
       )
  SELECT *,
         sum(revenue) OVER w AS cum_revenue,
         sum(plan) OVER w AS cum_plan,
         round(100 * sum(revenue) OVER w / NULLIF(sum(plan) OVER w, 0), 1) AS cum_pct,
         sum(plan - revenue) OVER w AS cum_shortfall
  FROM m
  WINDOW w AS (PARTITION BY EXTRACT(YEAR FROM month)
               ORDER BY month
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
  ORDER BY month;

-- А3. Класс клиента зависит от общей доли выручки с учётом этого клиента.
WITH r AS (
         SELECT o.customer_id,
                sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
         WHERE o.status <> 'Отменён'
           AND o.order_date >= CAST('2025-01-01' AS date)
           AND o.order_date < CAST('2026-01-01' AS date)
         GROUP BY 1
       ),
     c AS (
         SELECT *,
                sum(revenue) OVER (ORDER BY revenue DESC, customer_id
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / sum(revenue) OVER () AS cum_share
         FROM r
       ),
     abc AS (
         SELECT *,
                CASE
                  WHEN cum_share <= 0.80 THEN 'A' WHEN cum_share <= 0.95 THEN 'B'
                  ELSE 'C'
                END AS class
         FROM c
       )
  SELECT class,
         count(*) AS customers,
         sum(revenue) AS revenue,
         round(100 * sum(revenue) / sum(sum(revenue)) OVER (), 1) AS share
  FROM abc
  GROUP BY class
  ORDER BY class;

-- А4. Возможно, в июле не хватало продукции из-за простоев.
-- У команды Б нужно взять часы простоя и выпуск по линиям за июнь и июль и сверить с продажами по товарам.
WITH r AS (
         SELECT CAST(date_trunc('month', o.order_date) AS date) AS month,
                sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
         WHERE o.status <> 'Отменён'
         GROUP BY 1
       )
  SELECT *,
         round(100 * (revenue / NULLIF(lag(revenue) OVER (ORDER BY month), 0) - 1), 1) AS mom_pct,
         round(100 * (revenue / NULLIF(lag(revenue, 12) OVER (ORDER BY month), 0) - 1), 1) AS yoy_pct
  FROM r
  ORDER BY month;

-- А5.1. Для первого заказа 2025 года учитываем предыдущий заказ 2024 года.
WITH gaps AS (
         SELECT customer_id,
                CAST(EXTRACT(YEAR FROM order_date) AS integer) AS year,
                order_date - lag(order_date) OVER (PARTITION BY customer_id
                                                   ORDER BY order_date, order_id) AS gap
         FROM orders
         WHERE status <> 'Отменён'
       ),
     s AS (
         SELECT customer_id,
                avg(gap) FILTER (WHERE year = 2024) AS gap24,
                avg(gap) FILTER (WHERE year = 2025) AS gap25,
                count(*) FILTER (WHERE year = 2024) AS n24
         FROM gaps
         GROUP BY 1
       )
  SELECT c.customer_name, s.*, gap25 - gap24 AS growth
  FROM s INNER JOIN customers AS c USING (customer_id)
  WHERE n24 >= 10
  ORDER BY growth DESC NULLS LAST, s.customer_id
  LIMIT 5;

-- А5.2. Складываем неоплаченные остатки счетов на дату среза.
WITH x AS (
         SELECT i.*,
                COALESCE(sum(p.amount) FILTER (WHERE p.payment_date <= CAST('2025-12-31' AS date)),
                         0) AS paid,
                GREATEST(COALESCE(max(p.payment_date) FILTER (WHERE p.payment_date <= CAST('2025-12-31' AS date)),
                                  CAST('2025-12-31' AS date)) - i.due_date,
                         0) AS overdue_days
         FROM invoices AS i
              INNER JOIN orders AS o USING (order_id)
              LEFT JOIN payments AS p USING (invoice_id)
         WHERE o.customer_id = 1
         GROUP BY i.invoice_id
       )
  SELECT invoice_id,
         invoice_date,
         amount,
         paid,
         overdue_days,
         overdue_days - lag(overdue_days) OVER w AS delay_change,
         sum(amount - paid) OVER w AS cum_open_balance
  FROM x
  WINDOW w AS (ORDER BY invoice_date, invoice_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);

-- А5.3. Проверка из задания: складываем конечные остатки счетов.
-- 03.07.2025. Всего 22 счёта с учётом счёта, на котором превышен лимит, и 21 строго после него.
WITH balances AS (
         SELECT i.invoice_id, i.invoice_date, i.amount - COALESCE(sum(p.amount) FILTER (WHERE p.payment_date <= DATE '2025-12-31'), 0) AS balance
         FROM invoices AS i
              INNER JOIN orders AS o USING (order_id)
              LEFT JOIN payments AS p USING (invoice_id)
         WHERE o.customer_id = 1
         GROUP BY i.invoice_id
       ),
     running AS (
         SELECT *,
                sum(balance) OVER (ORDER BY invoice_date, invoice_id
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_open_balance
         FROM balances
       ),
     first_cross AS (
         SELECT invoice_date AS day, invoice_id
         FROM running
         WHERE cum_open_balance > 3000000
         ORDER BY invoice_date, invoice_id
         LIMIT 1
       )
  SELECT f.day, count(r.invoice_id) AS invoices_from_crossing,
         count(r.invoice_id) FILTER (WHERE r.invoice_date > f.day) AS invoices_after_day
  FROM first_cross AS f
       LEFT JOIN running AS r ON (r.invoice_date, r.invoice_id) >= (f.day, f.invoice_id)
  GROUP BY f.day;

-- Дополнительно считаем долг по счетам и оплатам на каждую дату.
-- При таком расчёте первое превышение — 24.06.2025.
WITH events AS (
         SELECT i.invoice_date AS day, i.amount AS delta
         FROM invoices AS i INNER JOIN orders AS o USING (order_id)
         WHERE o.customer_id = 1

         UNION ALL

         SELECT p.payment_date, - p.amount
         FROM payments AS p
              INNER JOIN invoices AS i USING (invoice_id)
              INNER JOIN orders AS o USING (order_id)
         WHERE o.customer_id = 1
       ),
     daily AS (
         SELECT day, sum(delta) AS delta
         FROM events
         GROUP BY day
       ),
     running AS (
         SELECT day, sum(delta) OVER (ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS debt
         FROM daily
       ),
     first_cross AS (
         SELECT min(day) AS day
         FROM running
         WHERE debt > 3000000
       )
  SELECT first_cross.day, count(i.invoice_id) AS later_invoices
  FROM first_cross
       LEFT JOIN orders AS o ON o.customer_id = 1
       LEFT JOIN invoices AS i ON i.order_id = o.order_id AND i.invoice_date > first_cross.day
  GROUP BY first_cross.day;

-- А6. При равном количестве ранг одинаковый, поэтому строк может быть больше трёх.
WITH r AS (
         SELECT c.region_id, rt.product_id, sum(rt.quantity) AS units
         FROM returns AS rt
              INNER JOIN orders AS o USING (order_id)
              INNER JOIN customers AS c USING (customer_id)
         GROUP BY 1, 2
       ),
     ranked AS (
         SELECT *,
                dense_rank() OVER (PARTITION BY region_id
                                   ORDER BY units DESC) AS rank,
                sum(units) OVER (PARTITION BY region_id) AS region_total
         FROM r
       )
  SELECT COALESCE(rg.region_name, 'не указан') AS region,
         p.product_name,
         p.shelf_life_days,
         x.units,
         x.rank,
         x.region_total
  FROM ranked AS x
       LEFT JOIN regions AS rg USING (region_id)
       INNER JOIN products AS p USING (product_id)
  WHERE x.rank <= 3
  ORDER BY x.region_total DESC, x.rank, p.product_id;

-- А7*
WITH s AS (
         SELECT o.employee_id,
                100.0 * count(*) FILTER (WHERE oi.discount_pct > 10) / count(*) AS violation_pct,
                sum(oi.quantity * oi.unit_price * oi.discount_pct / 100) AS discount
         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
         WHERE o.status <> 'Отменён'
         GROUP BY 1
       )
  SELECT e.full_name, s.*, percent_rank() OVER (ORDER BY discount) AS discount_percent_rank
  FROM s INNER JOIN employees AS e USING (employee_id)
  ORDER BY discount DESC;
-- А1. Средняя скидка Соколова по кварталам — 17,70%, 17,94%, 18,17% и 18,20%.
-- А2. Выполнение плана снижалось с апреля по ноябрь, в декабре немного выросло.
-- До годового плана не хватило 32 438 986,91 руб.
-- А3. Вектор входит в класс A.

-- Вывод
-- С апреля по ноябрь выполнение плана снижалось. К декабрю план выполнен на 98,0% за 2024 год и на 93,2% за 2025 год.
-- В июле 2025 года выручка упала на 25,1% к июню и на 23,3% к июлю прошлого года. Проверим простои и выпуск по данным команды Б.
-- В класс A вошли 33 клиента с 79,8% выручки, но их долги всё равно нужно проверять.
-- По остаткам счетов Вектор превышает лимит 03.07.2025, а по счетам и оплатам на каждую дату —
-- 24.06.2025.
-- У ИП Носова средний перерыв между заказами вырос с 19,1 до 60,9 дня.
-- В Новосибирской области вернули 15 355 единиц, в Красноярском крае — 8 377. В топе два йогурта и молоко 3,2%, которые хранятся 7–10 дней.
-- Соколов лидировал по средней скидке во всех кварталах 2025 года. За весь период он дал скидок на 38,78 млн руб.
