-- Лабораторная работа 1
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Посчитаны заказы и скидки, найдены просрочки, проверены контакты и цены.
SET search_path TO 'pitanie', 'public';

-- О1–О3
SELECT count(*) AS orders_total
FROM orders;

SELECT count(*) AS cancelled
FROM orders
WHERE status = 'Отменён';

SELECT *
FROM products
WHERE shelf_life_days <= 14
ORDER BY shelf_life_days, product_name;

SELECT *
FROM employees
WHERE (email IS NULL OR phone IS NULL)
ORDER BY department, full_name;

-- А1
SELECT *
FROM order_items
WHERE discount_pct > 10
ORDER BY discount_pct DESC, order_item_id;

SELECT count(*)
FROM order_items
WHERE discount_pct > 10;

SELECT count(*)
FROM order_items
WHERE discount_pct >= 20;

-- А2. Сортируем только по сумме, чтобы WITH TIES сохранил равные значения.
SELECT order_item_id,
       order_id,
       round(quantity * unit_price * (discount_pct - 10) / 100, 2) AS excess_rub
FROM order_items
WHERE discount_pct > 10
ORDER BY excess_rub DESC
FETCH FIRST 20 ROWS WITH TIES;

-- А3. Номера заказов взяты из результата А2.
-- Сначала выписываем первые десять заказов.
SELECT order_id
FROM order_items
WHERE discount_pct > 10
ORDER BY round(quantity * unit_price * (discount_pct - 10) / 100, 2) DESC, order_item_id
LIMIT 10;

SELECT *
FROM orders
WHERE order_id IN (2467, 4385, 3425, 3425, 3339, 1561, 2165, 1326, 2349, 2201)
ORDER BY order_id;

SELECT *
FROM employees
WHERE employee_id = 10;

-- Один и тот же менеджер ещё не означает нарушение.
-- Нужно проверить согласование скидок и сравнить продажи с другими менеджерами.
-- А4
SELECT *
FROM orders
WHERE shipped_date IS NULL AND status <> 'Отменён'
ORDER BY required_date, order_id;

SELECT *
FROM orders
WHERE shipped_date IS NULL
  AND required_date < DATE '2025-12-31'
  AND status IN ('Новый', 'В работе')
ORDER BY required_date, order_id;

SELECT count(*)
FROM orders
WHERE status IN ('Отгружен', 'Доставлен') AND shipped_date IS NULL;

SELECT count(*)
FROM orders
WHERE shipped_date > required_date;

-- NULL > дата даёт UNKNOWN и не проходит WHERE.
-- А5
SELECT customer_id, customer_name, '[' || COALESCE(email, 'NULL') || ']' AS email_visible
FROM customers
WHERE (email IS NULL OR email LIKE ' %' OR email LIKE '% ' OR email ~ '[[:upper:]]')
ORDER BY customer_id;

SELECT *
FROM customers
WHERE region_id IS NULL
ORDER BY customer_id;

-- А6. Из-за дублей выручка и долг одного клиента попадают в разные карточки.
SELECT *
FROM customers
WHERE (customer_name ILIKE '%ромашк%'
    OR customer_name ILIKE '%свежест%'
    OR customer_name ILIKE '%колос%')
ORDER BY inn, customer_id;

-- А7: себестоимость и идентификаторы взяты из первого запроса вручную.
SELECT product_id, product_name, base_price, standard_cost
FROM products
WHERE product_name ILIKE 'масло%';

SELECT count(*) AS sold
FROM order_items
WHERE product_id = 13;

SELECT count(*) AS below_cost
FROM order_items
WHERE product_id = 13 AND unit_price * (1 - discount_pct / 100) < 205;

SELECT count(*) AS sold
FROM order_items
WHERE product_id = 14;

SELECT count(*) AS below_cost
FROM order_items
WHERE product_id = 14 AND unit_price * (1 - discount_pct / 100) < 151;

-- А8
SELECT *
FROM invoices
ORDER BY amount DESC, invoice_id DESC
LIMIT 10;

SELECT *
FROM invoices
ORDER BY amount DESC, invoice_id DESC
OFFSET 10 ROWS
FETCH NEXT 10 ROWS ONLY;

-- А9*. Оба поля отсортированы по убыванию, поэтому используем <.
SELECT *
FROM invoices
WHERE (amount, invoice_id) < (875376.40, 2881)
ORDER BY amount DESC, invoice_id DESC
LIMIT 10;

-- А10*
SELECT count(*) AS items,
       round(sum(quantity * unit_price * discount_pct / 100), 2) AS discount_total_rub,
       round(sum(quantity * unit_price * (discount_pct - 10) / 100), 2) AS over_policy_rub
FROM order_items
WHERE discount_pct > 10;
-- Вывод
-- Скидка выше 10% есть у 4 365 позиций, а сумма скидки сверх этого порога — 17 979 376,44 руб.
-- Первые десять самых больших отклонений относятся к девяти заказам Соколова И. А.
-- Это повод проверить скидки, но само по себе ещё не говорит о нарушении.
-- У масла 82,5% ниже себестоимости проданы все 552 позиции (100%), у масла 72,5% — 365 из 524 (69,7%).
-- Самая большая найденная сумма — скидки сверх 10%; сначала нужно проверить их согласование.
-- Пропущенный email мешает отправить счёт, а пропущенный регион искажает отчёт по регионам.
