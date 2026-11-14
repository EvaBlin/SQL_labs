-- Лабораторная работа 5
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Найдены убыточные продажи, должники и товары с частыми возвратами.
SET search_path TO 'pitanie', 'public';

-- Общая часть. Для NOT IN нужно проверить, что в подзапросе нет NULL.
SELECT p.*
FROM products AS p
WHERE p.base_price > (SELECT avg(x.base_price)
                      FROM products AS x);

SELECT c.*
FROM customers AS c
WHERE NOT c.customer_id IN (SELECT o.customer_id
                            FROM orders AS o);

SELECT c.*
FROM customers AS c
WHERE NOT EXISTS (SELECT 1
                  FROM orders AS o
                  WHERE o.customer_id = c.customer_id);

-- А1. Получаем название и себестоимость товара через подзапросы.
SELECT count(*)
FROM order_items AS oi
WHERE oi.order_id IN (SELECT o.order_id
                      FROM orders AS o
                      WHERE o.status <> 'Отменён')
  AND oi.unit_price * (1 - oi.discount_pct / 100) < (SELECT p.standard_cost
                                                     FROM products AS p
                                                     WHERE p.product_id = oi.product_id);

SELECT oi.product_id,
       (SELECT p.product_name
        FROM products AS p
        WHERE p.product_id = oi.product_id) AS product,
       sum(oi.quantity * ((SELECT p.standard_cost
                           FROM products AS p
                           WHERE p.product_id = oi.product_id) - oi.unit_price * (1 - oi.discount_pct / 100))) AS loss
FROM order_items AS oi
WHERE oi.order_id IN (SELECT o.order_id
                      FROM orders AS o
                      WHERE o.status <> 'Отменён')
  AND oi.unit_price * (1 - oi.discount_pct / 100) < (SELECT p.standard_cost
                                                     FROM products AS p
                                                     WHERE p.product_id = oi.product_id)
GROUP BY oi.product_id;

-- А2
SELECT e.employee_id,
       e.full_name,
       avg(oi.discount_pct) AS avg_discount,
       (SELECT avg(x.discount_pct)
        FROM order_items AS x INNER JOIN orders AS y USING (order_id)
        WHERE y.status <> 'Отменён') AS company_avg
FROM employees AS e
     INNER JOIN orders AS o ON o.employee_id = e.employee_id
     INNER JOIN order_items AS oi USING (order_id)
WHERE o.status <> 'Отменён'
GROUP BY e.employee_id
HAVING avg(oi.discount_pct) > (SELECT avg(x.discount_pct)
                               FROM order_items AS x INNER JOIN orders AS y USING (order_id)
                               WHERE y.status <> 'Отменён')
ORDER BY avg_discount DESC;

-- А3. В А2 найден менеджер 10. Через ALL сравниваем его скидки со скидками остальных.
SELECT count(*) AS lines,
       sum(oi.quantity * oi.unit_price * oi.discount_pct / 100) AS discounts
FROM order_items AS oi
WHERE oi.order_id IN (SELECT o.order_id
                      FROM orders AS o
                      WHERE o.employee_id = 10 AND o.status <> 'Отменён')
  AND oi.discount_pct > ALL (SELECT x.discount_pct
                             FROM order_items AS x INNER JOIN orders AS o USING (order_id)
                             WHERE o.employee_id <> 10 AND o.status <> 'Отменён');

SELECT sum(oi.quantity * oi.unit_price * (oi.discount_pct - 10) / 100) AS excess
FROM order_items AS oi
WHERE oi.discount_pct > 10
  AND oi.order_id IN (SELECT o.order_id
                      FROM orders AS o
                      WHERE o.employee_id = 10 AND o.status <> 'Отменён');

-- А4. Клиент без заказов может оказаться дублем другой карточки.
SELECT c.customer_id,
       c.customer_name,
       c.inn,
       (SELECT max(o.order_date)
        FROM orders AS o
        WHERE o.customer_id = c.customer_id) AS last_order,
       EXISTS (SELECT 1
               FROM customers AS x
               WHERE x.inn = c.inn AND x.customer_id <> c.customer_id) AS has_duplicate
FROM customers AS c
WHERE NOT EXISTS (SELECT 1
                  FROM orders AS o
                  WHERE o.customer_id = c.customer_id
                    AND o.order_date >= CAST('2025-12-31' AS date) - CAST('3 months' AS interval));

-- А5. Возвраты и продажи считаем отдельно, чтобы не повторять строки.
SELECT z.*, 100 * z.returned / NULLIF(z.sold, 0) AS return_pct
FROM (SELECT p.product_id,
             p.product_name,
             p.shelf_life_days,
             CAST(COALESCE((SELECT sum(r.quantity)
                            FROM returns AS r
                            WHERE r.product_id = p.product_id),
                           0) AS numeric) AS returned,
             (SELECT sum(oi.quantity)
              FROM order_items AS oi INNER JOIN orders AS o USING (order_id)
              WHERE oi.product_id = p.product_id AND o.status <> 'Отменён') AS sold
      FROM products AS p) AS z
WHERE z.returned / NULLIF(z.sold, 0) > (SELECT CAST(sum(r.quantity) AS numeric)
                                        FROM returns AS r) / NULLIF((SELECT sum(oi.quantity)
                                                                     FROM order_items AS oi
                                                                          INNER JOIN orders AS o USING (order_id)
                                                                     WHERE o.status <> 'Отменён'),
                                                                    0);

SELECT 100.0 * sum(r.quantity) FILTER (WHERE r.order_id IN (SELECT o.order_id
                                                            FROM orders AS o
                                                            WHERE o.customer_id IN (SELECT c.customer_id
                                                                                    FROM customers AS c
                                                                                    WHERE c.region_id IN (SELECT rg.region_id
                                                                                                          FROM regions AS rg
                                                                                                          WHERE rg.federal_district = 'Сибирский')))) / NULLIF(sum(r.quantity),
                                                                                                                                                               0) AS siberia_share
FROM returns AS r
WHERE r.product_id IN (SELECT p.product_id
                       FROM products AS p
                       WHERE p.shelf_life_days <= 10);

-- А6
SELECT z.*, z.debt - z.credit_limit AS excess
FROM (SELECT c.customer_id,
             c.customer_name,
             c.credit_limit,
             COALESCE((SELECT sum(i.amount)
                       FROM invoices AS i INNER JOIN orders AS o USING (order_id)
                       WHERE o.customer_id = c.customer_id),
                      0) - COALESCE((SELECT sum(p.amount)
                                     FROM payments AS p
                                          INNER JOIN invoices AS i USING (invoice_id)
                                          INNER JOIN orders AS o USING (order_id)
                                     WHERE o.customer_id = c.customer_id),
                                    0) AS debt
      FROM customers AS c) AS z
WHERE z.debt > z.credit_limit;

-- А7. Для каждой отгрузки берём только счета и оплаты до её даты.
SELECT c.customer_id, c.customer_name
FROM customers AS c
WHERE EXISTS (SELECT 1
              FROM orders AS o
              WHERE o.customer_id = c.customer_id
                AND o.shipped_date IS NOT NULL
                AND COALESCE((SELECT sum(i.amount)
                              FROM invoices AS i INNER JOIN orders AS x USING (order_id)
                              WHERE x.customer_id = c.customer_id
                                AND i.invoice_date < o.shipped_date),
                             0) - COALESCE((SELECT sum(p.amount)
                                            FROM payments AS p
                                                 INNER JOIN invoices AS i USING (invoice_id)
                                                 INNER JOIN orders AS x USING (order_id)
                                            WHERE x.customer_id = c.customer_id
                                              AND p.payment_date < o.shipped_date),
                                           0) > c.credit_limit);

SELECT count(*) AS shipments,
       min(o.shipped_date),
       max(o.shipped_date),
       sum(i.amount) AS invoiced
FROM orders AS o
     INNER JOIN customers AS c USING (customer_id)
     INNER JOIN invoices AS i USING (order_id)
WHERE c.customer_id = 1
  AND o.shipped_date IS NOT NULL
  AND COALESCE((SELECT sum(x.amount)
                FROM invoices AS x INNER JOIN orders AS y USING (order_id)
                WHERE y.customer_id = c.customer_id AND x.invoice_date < o.shipped_date),
               0) - COALESCE((SELECT sum(p.amount)
                              FROM payments AS p
                                   INNER JOIN invoices AS x USING (invoice_id)
                                   INNER JOIN orders AS y USING (order_id)
                              WHERE y.customer_id = c.customer_id
                                AND p.payment_date < o.shipped_date),
                             0) > c.credit_limit;

-- А8*. Если у дистрибьютора регион NULL, NOT IN не даст нужный результат.
SELECT r.*
FROM regions AS r
WHERE NOT r.region_id IN (SELECT c.region_id
                          FROM customers AS c
                          WHERE c.customer_type = 'Дистрибьютор');

SELECT r.*
FROM regions AS r
WHERE NOT EXISTS (SELECT 1
                  FROM customers AS c
                  WHERE c.customer_type = 'Дистрибьютор' AND c.region_id = r.region_id);

-- А6*. Смотрим план первого запроса.
EXPLAIN SELECT z.*, z.debt - z.credit_limit AS excess
        FROM (SELECT c.customer_id,
                     c.customer_name,
                     c.credit_limit,
                     COALESCE((SELECT sum(i.amount)
                               FROM invoices AS i INNER JOIN orders AS o USING (order_id)
                               WHERE o.customer_id = c.customer_id),
                              0) - COALESCE((SELECT sum(p.amount)
                                             FROM payments AS p
                                                  INNER JOIN invoices AS i USING (invoice_id)
                                                  INNER JOIN orders AS o USING (order_id)
                                             WHERE o.customer_id = c.customer_id),
                                            0) AS debt
              FROM customers AS c) AS z
        WHERE z.debt > z.credit_limit;

-- А6*. Смотрим план запроса с отдельным подсчётом сумм.
EXPLAIN SELECT c.customer_id,
               c.customer_name,
               c.credit_limit,
               COALESCE(i.total, 0) - COALESCE(p.total, 0) AS debt,
               COALESCE(i.total, 0) - COALESCE(p.total, 0) - c.credit_limit AS excess
        FROM customers AS c
             LEFT JOIN (SELECT o.customer_id, sum(i.amount) AS total
                        FROM invoices AS i INNER JOIN orders AS o USING (order_id)
                        GROUP BY o.customer_id) AS i USING (customer_id)
             LEFT JOIN (SELECT o.customer_id, sum(p.amount) AS total
                        FROM payments AS p
                             INNER JOIN invoices AS i USING (invoice_id)
                             INNER JOIN orders AS o USING (order_id)
                        GROUP BY o.customer_id) AS p USING (customer_id)
        WHERE COALESCE(i.total, 0) - COALESCE(p.total, 0) > c.credit_limit;
-- Первый запрос считает суммы отдельно для каждого клиента через коррелированные подзапросы.
-- Во втором суммы по счетам и оплатам группируются по клиентам один раз, затем соединяются со справочником.
-- В проверке на PostgreSQL 18 первый план показал SubPlan и стоимость 44 484,89,
-- второй показал HashAggregate и Hash Left Join со стоимостью 743,59.
-- Для расчёта прошлой маржи нужна таблица с историей себестоимости.
-- Текущая себестоимость не показывает, какой она была в 2024 году.
-- А5. На Сибирский ФО приходится 84,49% возвращённых единиц со сроком годности до 10 дней.

-- Вывод
-- У сливочного масла 82,5% и 72,5% 879 позиций с отрицательной маржой без отменённых заказов.
-- По текущей себестоимости разница за весь период составляет 10 946 804,68 руб. (отдельный пересчёт).
-- Соколов дал скидок сверх 10% на 17 206 398,67 руб.
-- Вектор получил 22 отгрузки после превышения лимита, счета по ним — около 4,11 млн руб.
-- На Сибирь приходится 84,49% возвращённых единиц со сроком хранения до 10 дней. Нужно проверить доставку йогуртов и молока.
-- Клиент без новых заказов может покупать по другой карточке с тем же ИНН. Нужно проверить дубли.
-- Для точного расчёта прошлых убытков нужна история себестоимости.
