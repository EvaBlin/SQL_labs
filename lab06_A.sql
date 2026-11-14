-- Лабораторная работа 6
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Собрана лента счетов, оплат и возвратов. Сравнены покупки за два года.
SET search_path TO 'pitanie', 'public';

-- Общая часть. Объединение строк и поиск общих ИНН.
-- 85 строк с UNION ALL и 81 с UNION: четыре лишние карточки по трём ИНН клиентов.
-- Между customers и suppliers одинаковых ИНН нет.
SELECT count(*)
FROM (SELECT inn FROM customers UNION ALL SELECT inn FROM suppliers) AS x;

SELECT count(*)
FROM (SELECT inn FROM customers UNION SELECT inn FROM suppliers) AS x;

SELECT inn
FROM customers

INTERSECT

SELECT inn
FROM suppliers;

-- А1. Общий список счетов, оплат и возвратов.
SELECT kind, count(*) AS documents, sum(amount) AS amount
FROM ((SELECT 'Счёт' AS kind, o.customer_id, i.invoice_date AS event_date, i.amount
       FROM invoices AS i INNER JOIN orders AS o USING (order_id)

       UNION ALL

       SELECT 'Оплата', o.customer_id, p.payment_date, p.amount
       FROM payments AS p
            INNER JOIN invoices AS i USING (invoice_id)
            INNER JOIN orders AS o USING (order_id))

      UNION ALL

      SELECT 'Возврат',
             o.customer_id,
             r.return_date,
             r.quantity * oi.unit_price * (1 - oi.discount_pct / 100)
      FROM returns AS r
           INNER JOIN orders AS o USING (order_id)
           INNER JOIN order_items AS oi ON oi.order_id = r.order_id
                                       AND oi.product_id = r.product_id) AS events
GROUP BY kind;

-- А2. Изменение долга Вектора. Возврат товара сам по себе не считается оплатой.
SELECT CAST(date_trunc('month', event_date) AS date) AS month,
       COALESCE(sum(amount) FILTER (WHERE kind = 'Счёт'), 0) AS invoiced,
       COALESCE(sum(amount) FILTER (WHERE kind = 'Оплата'), 0) AS paid,
       COALESCE(sum(amount) FILTER (WHERE kind = 'Возврат'), 0) AS returned,
       sum(CASE kind WHEN 'Счёт' THEN amount WHEN 'Оплата' THEN - amount ELSE 0 END) AS debt_change
FROM ((SELECT 'Счёт' AS kind, i.invoice_date AS event_date, i.amount
       FROM invoices AS i INNER JOIN orders AS o USING (order_id)
       WHERE o.customer_id = 1

       UNION ALL

       SELECT 'Оплата', p.payment_date, p.amount
       FROM payments AS p
            INNER JOIN invoices AS i USING (invoice_id)
            INNER JOIN orders AS o USING (order_id)
       WHERE o.customer_id = 1)

      UNION ALL

      SELECT 'Возврат',
             r.return_date,
             r.quantity * oi.unit_price * (1 - oi.discount_pct / 100)
      FROM returns AS r
           INNER JOIN orders AS o USING (order_id)
           INNER JOIN order_items AS oi ON oi.order_id = r.order_id
                                       AND oi.product_id = r.product_id
      WHERE o.customer_id = 1) AS events
WHERE event_date >= CAST('2025-01-01' AS date) AND event_date < CAST('2026-01-01' AS date)
GROUP BY 1
ORDER BY 1;

-- А3.1. Переставшие покупать клиенты.
SELECT customer_id
FROM orders
WHERE status <> 'Отменён'
  AND order_date >= CAST('2024-01-01' AS date)
  AND order_date < CAST('2025-01-01' AS date)

EXCEPT

SELECT customer_id
FROM orders
WHERE status <> 'Отменён'
  AND order_date >= CAST('2025-01-01' AS date)
  AND order_date < CAST('2026-01-01' AS date);

-- А3.2–3. Какие товары клиент перестал покупать и сколько они приносили.
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE NOT p.is_active) AS discontinued,
       sum(v.revenue) AS lost_2024_revenue
FROM (SELECT o.customer_id, oi.product_id
      FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
      WHERE o.status <> 'Отменён'
        AND o.order_date >= CAST('2024-01-01' AS date)
        AND o.order_date < CAST('2025-01-01' AS date)

      EXCEPT

      SELECT o.customer_id, oi.product_id
      FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
      WHERE o.status <> 'Отменён'
        AND o.order_date >= CAST('2025-01-01' AS date)
        AND o.order_date < CAST('2026-01-01' AS date)) AS l
     INNER JOIN products AS p USING (product_id)
     CROSS JOIN LATERAL (SELECT sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
                         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
                         WHERE o.customer_id = l.customer_id
                           AND oi.product_id = l.product_id
                           AND o.status <> 'Отменён'
                           AND o.order_date >= CAST('2024-01-01' AS date)
                           AND o.order_date < CAST('2025-01-01' AS date)) AS v;

-- А3.4*. Категория, которую клиент перестал покупать.
SELECT customer_id, parent_category_id
FROM (SELECT o.customer_id,
             pc.parent_category_id,
             CAST(EXTRACT(YEAR FROM o.order_date) AS integer) AS year
      FROM orders AS o
           INNER JOIN order_items AS oi USING (order_id)
           INNER JOIN products AS p USING (product_id)
           INNER JOIN product_categories AS pc USING (category_id)
      WHERE o.status <> 'Отменён') AS pairs
WHERE year = 2024

EXCEPT

SELECT customer_id, parent_category_id
FROM (SELECT o.customer_id,
             pc.parent_category_id,
             CAST(EXTRACT(YEAR FROM o.order_date) AS integer) AS year
      FROM orders AS o
           INNER JOIN order_items AS oi USING (order_id)
           INNER JOIN products AS p USING (product_id)
           INNER JOIN product_categories AS pc USING (category_id)
      WHERE o.status <> 'Отменён') AS pairs
WHERE year = 2025;

-- А4. Топ-10 по выручке.
SELECT p.product_name,
       sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
FROM order_items AS oi
     INNER JOIN orders AS o USING (order_id)
     INNER JOIN products AS p USING (product_id)
WHERE o.status <> 'Отменён'
GROUP BY p.product_id
ORDER BY revenue DESC, p.product_id
LIMIT 10;

-- А4. Топ-10 по сумме возвратов.
SELECT p.product_name,
       sum(r.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS returned
FROM returns AS r
     INNER JOIN order_items AS oi ON oi.order_id = r.order_id AND oi.product_id = r.product_id
     INNER JOIN products AS p ON p.product_id = r.product_id
GROUP BY p.product_id
ORDER BY returned DESC, p.product_id
LIMIT 10;

-- А4. Пересечение и разность двух списков.
SELECT 'пересечение' AS kind, p.product_name, p.shelf_life_days
FROM (SELECT product_id
      FROM (SELECT oi.product_id,
                   sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS amount
            FROM order_items AS oi INNER JOIN orders AS o USING (order_id)
            WHERE o.status <> 'Отменён'
            GROUP BY oi.product_id
            ORDER BY amount DESC, product_id
            LIMIT 10) AS sales

      INTERSECT

      SELECT product_id
      FROM (SELECT r.product_id,
                   sum(r.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS amount
            FROM returns AS r
                 INNER JOIN order_items AS oi ON oi.order_id = r.order_id
                                             AND oi.product_id = r.product_id
            GROUP BY r.product_id
            ORDER BY amount DESC, product_id
            LIMIT 10) AS ret) AS in_both
     INNER JOIN products AS p USING (product_id)

UNION ALL

SELECT 'только топ возвратов', p.product_name, p.shelf_life_days
FROM (SELECT product_id
      FROM (SELECT r.product_id,
                   sum(r.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS amount
            FROM returns AS r
                 INNER JOIN order_items AS oi ON oi.order_id = r.order_id
                                             AND oi.product_id = r.product_id
            GROUP BY r.product_id
            ORDER BY amount DESC, product_id
            LIMIT 10) AS ret

      EXCEPT

      SELECT product_id
      FROM (SELECT oi.product_id,
                   sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS amount
            FROM order_items AS oi INNER JOIN orders AS o USING (order_id)
            WHERE o.status <> 'Отменён'
            GROUP BY oi.product_id
            ORDER BY amount DESC, product_id
            LIMIT 10) AS sales) AS only_returns
     INNER JOIN products AS p USING (product_id);

-- А5. CROSS JOIN LATERAL оставляет только сотрудников с продажами.
SELECT e.full_name, t.*
FROM employees AS e
     CROSS JOIN LATERAL (SELECT oi.order_item_id,
                                oi.quantity * oi.unit_price * oi.discount_pct / 100 AS discount
                         FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
                         WHERE o.employee_id = e.employee_id AND o.status <> 'Отменён'
                         ORDER BY discount DESC, oi.order_item_id
                         LIMIT 3) AS t;

-- А5. LEFT JOIN LATERAL оставляет всех сотрудников отдела продаж.
SELECT e.full_name, t.*
FROM employees AS e
     LEFT JOIN LATERAL (SELECT oi.order_item_id,
                               oi.quantity * oi.unit_price * oi.discount_pct / 100 AS discount
                        FROM orders AS o INNER JOIN order_items AS oi USING (order_id)
                        WHERE o.employee_id = e.employee_id AND o.status <> 'Отменён'
                        ORDER BY discount DESC, oi.order_item_id
                        LIMIT 3) AS t ON TRUE
WHERE e.department = 'Продажи';

-- А6*. Менеджер с наибольшей скидкой в каждом месяце.
SELECT CAST(m AS date) AS month, t.*
FROM generate_series(CAST('2025-01-01' AS date),
                     CAST('2025-12-01' AS date),
                     CAST('1 month' AS interval)) AS g (m)
     CROSS JOIN LATERAL (SELECT e.full_name,
                                sum(oi.quantity * oi.unit_price * oi.discount_pct / 100) AS discount
                         FROM orders AS o
                              INNER JOIN order_items AS oi USING (order_id)
                              INNER JOIN employees AS e ON e.employee_id = o.employee_id
                         WHERE o.order_date >= m
                           AND o.order_date < m + CAST('1 month' AS interval)
                           AND o.status <> 'Отменён'
                         GROUP BY e.employee_id
                         ORDER BY discount DESC, e.employee_id
                         LIMIT 1) AS t;

-- А7*. UNION убирает совпадающие строки, даже если документы разные.
SELECT (SELECT count(*)
        FROM (SELECT *
              FROM (SELECT o.customer_id, i.invoice_date AS day, i.amount
                    FROM invoices AS i INNER JOIN orders AS o USING (order_id)) AS invoices_events

              UNION ALL

              SELECT *
              FROM (SELECT o.customer_id, p.payment_date AS day, p.amount
                    FROM payments AS p
                         INNER JOIN invoices AS i USING (invoice_id)
                         INNER JOIN orders AS o USING (order_id)) AS payments_events) AS all_events) AS union_all_count,
       (SELECT count(*)
        FROM (SELECT *
              FROM (SELECT o.customer_id, i.invoice_date AS day, i.amount
                    FROM invoices AS i INNER JOIN orders AS o USING (order_id)) AS invoices_events

              UNION

              SELECT *
              FROM (SELECT o.customer_id, p.payment_date AS day, p.amount
                    FROM payments AS p
                         INNER JOIN invoices AS i USING (invoice_id)
                         INNER JOIN orders AS o USING (order_id)) AS payments_events) AS unique_events) AS union_count;
-- А2. В 2025 году у Вектора было пять месяцев без оплат.
-- Самый большой рост долга был в декабре — 1 540 300,27 руб.
-- А6*. Соколов лидировал по сумме скидок во всех месяцах.

-- Вывод
-- В общей ленте получилось 4 242 счёта, 4 519 оплат и 308 возвратов.
-- Клиентов, которые полностью перестали покупать между 2024 и 2025 годами, нет.
-- При этом исчезли 127 пар «клиент — товар», из них 31 относится к снятому товару.
-- Все 127 исчезнувших пар принесли в 2024 году 8 223 886,16 руб. выручки.
-- В обоих списках масло 82,5%, сырный соус, сливки 33% и шоколадные конфеты ассорти.
-- Только в топе возвратов оба йогурта, оба вида пастеризованного молока, кефир и ряженка. Они хранятся 7–10 дней.
-- Больше всего скидок за весь период у Соколова (38,78 млн руб.), Морозовой (10,32 млн) и Павлова (7,10 млн).
-- Соколов лидировал в каждом месяце 2025 года.
-- Если заменить UNION ALL на UNION без типа документа, число счетов и оплат уменьшится с 8 761 до 8 703. Часть разных событий потеряется.
