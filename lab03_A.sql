-- Лабораторная работа 3
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Соединены заказы, клиенты, менеджеры, счета и возвраты.
SET search_path TO 'pitanie', 'public';

-- Общая часть.
-- У клиента есть заказы и регион. У заказа есть менеджер, позиции, счёт и возвраты.
-- Позиция ссылается на товар, товар на категорию, оплата на счёт.
-- Руководитель сотрудника тоже хранится в employees.
-- Строки: customers 73, orders 4458, order_items 17576, products 35,
-- product_categories 10, invoices 4242, payments 4519, returns 308, regions 12, employees 35.
-- У клиента может быть много заказов, у заказа — много позиций и возвратов.
-- Товар относится к категории; у клиента могут быть NULL в region_id и manager_id.
-- У сотрудника manager_id тоже может быть NULL.
-- У менеджера тоже может быть руководитель. На заказ приходится не больше одного счёта.
-- У счёта может быть несколько оплат, поэтому после JOIN его сумма может повторяться.
SELECT count(*) AS customers_rows
FROM customers;

SELECT count(*) AS orders_rows
FROM orders;

SELECT count(*) AS order_items_rows
FROM order_items;

SELECT count(*) AS products_rows
FROM products;

SELECT count(*) AS product_categories_rows
FROM product_categories;

SELECT count(*) AS invoices_rows
FROM invoices;

SELECT count(*) AS payments_rows
FROM payments;

SELECT count(*) AS returns_rows
FROM returns;

SELECT count(*) AS regions_rows
FROM regions;

SELECT count(*) AS employees_rows
FROM employees;

-- А1
SELECT o.order_number,
       o.order_date,
       c.customer_name,
       COALESCE(r.region_name, 'не указан') AS region,
       e.full_name
FROM orders AS o
     INNER JOIN customers AS c ON c.customer_id = o.customer_id
     LEFT JOIN regions AS r ON r.region_id = c.region_id
     INNER JOIN employees AS e ON e.employee_id = o.employee_id
WHERE o.order_date >= CAST('2025-01-01' AS date)
  AND o.order_date < CAST('2026-01-01' AS date)
  AND o.status <> 'Отменён';

-- А2
SELECT o.order_number,
       o.order_date,
       e.full_name,
       m.full_name AS manager,
       p.product_name,
       oi.quantity,
       oi.unit_price,
       oi.discount_pct
FROM orders AS o
     INNER JOIN order_items AS oi ON oi.order_id = o.order_id
     INNER JOIN products AS p ON p.product_id = oi.product_id
     INNER JOIN employees AS e ON e.employee_id = o.employee_id
     LEFT JOIN employees AS m ON m.employee_id = e.manager_id
WHERE o.order_date >= CAST('2025-01-01' AS date)
  AND o.order_date < CAST('2026-01-01' AS date)
  AND o.status <> 'Отменён'
  AND oi.discount_pct > 10;

SELECT e.full_name, m.full_name AS manager, count(*) AS violations
FROM orders AS o
     INNER JOIN order_items AS oi ON oi.order_id = o.order_id
     INNER JOIN employees AS e ON e.employee_id = o.employee_id
     LEFT JOIN employees AS m ON m.employee_id = e.manager_id
WHERE oi.discount_pct > 10 AND o.status <> 'Отменён'
GROUP BY e.employee_id, e.full_name, m.full_name;

-- А3
SELECT o.order_id,
       c.customer_name,
       assigned.full_name AS assigned_manager,
       actual.full_name AS actual_manager
FROM orders AS o
     INNER JOIN customers AS c ON c.customer_id = o.customer_id
     LEFT JOIN employees AS assigned ON assigned.employee_id = c.manager_id
     INNER JOIN employees AS actual ON actual.employee_id = o.employee_id
WHERE o.employee_id <> c.manager_id;

-- А4
SELECT i.*, c.customer_name, e.full_name
FROM invoices AS i
     INNER JOIN orders AS o ON o.order_id = i.order_id
     INNER JOIN customers AS c ON c.customer_id = o.customer_id
     LEFT JOIN employees AS e ON e.employee_id = c.manager_id
     LEFT JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE p.payment_id IS NULL;

SELECT count(*), sum(i.amount)
FROM invoices AS i LEFT JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE p.payment_id IS NULL AND i.due_date < CAST('2026-01-01' AS date);

-- А5. Счета и оплаты считаем отдельно, чтобы не повторять суммы.
SELECT c.customer_id,
       c.customer_name,
       c.credit_limit,
       count(*) AS unpaid_count,
       sum(i.amount) AS unpaid
FROM customers AS c
     INNER JOIN orders AS o ON o.customer_id = c.customer_id
     INNER JOIN invoices AS i ON i.order_id = o.order_id
     LEFT JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE p.payment_id IS NULL
GROUP BY c.customer_id
ORDER BY unpaid DESC;

SELECT sum(i.amount) AS invoiced
FROM invoices AS i INNER JOIN orders AS o ON o.order_id = i.order_id
WHERE o.customer_id = 1;

SELECT sum(p.amount) AS paid
FROM payments AS p
     INNER JOIN invoices AS i ON i.invoice_id = p.invoice_id
     INNER JOIN orders AS o ON o.order_id = i.order_id
WHERE o.customer_id = 1;

SELECT i.*, o.shipped_date
FROM invoices AS i
     INNER JOIN orders AS o ON o.order_id = i.order_id
     LEFT JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE o.customer_id = 1 AND p.payment_id IS NULL
ORDER BY i.invoice_date;

-- А6
SELECT rt.return_id,
       p.product_name,
       p.shelf_life_days,
       pc.category_name,
       c.customer_name,
       COALESCE(r.region_name, 'не указан') AS region,
       r.federal_district,
       rt.reason,
       o.shipped_date - o.order_date AS delivery_days
FROM returns AS rt
     INNER JOIN products AS p ON p.product_id = rt.product_id
     INNER JOIN product_categories AS pc ON pc.category_id = p.category_id
     INNER JOIN orders AS o ON o.order_id = rt.order_id
     INNER JOIN customers AS c ON c.customer_id = o.customer_id
     LEFT JOIN regions AS r ON r.region_id = c.region_id;

SELECT count(*)
FROM returns AS rt
     INNER JOIN orders AS o ON o.order_id = rt.order_id
     INNER JOIN customers AS c ON c.customer_id = o.customer_id
     INNER JOIN regions AS r ON r.region_id = c.region_id
WHERE r.federal_district = 'Сибирский' AND rt.reason = 'Истёк срок годности';

-- А7. Даты указаны в ON, чтобы оставить клиентов без заказов.
SELECT c.customer_id, o.order_id
FROM customers AS c
     LEFT JOIN orders AS o ON o.customer_id = c.customer_id
                          AND o.order_date >= CAST('2025-12-01' AS date)
                          AND o.order_date < CAST('2026-01-01' AS date);

SELECT c.customer_id, c.customer_name
FROM customers AS c
     LEFT JOIN orders AS o ON o.customer_id = c.customer_id
                          AND o.order_date >= CAST('2025-12-01' AS date)
                          AND o.order_date < CAST('2026-01-01' AS date)
WHERE o.order_id IS NULL;

-- А8
SELECT a.customer_id AS first_id, b.customer_id AS second_id, a.inn
FROM customers AS a
     INNER JOIN customers AS b ON a.inn = b.inn AND a.customer_id < b.customer_id
ORDER BY first_id, second_id;

-- А9*: Попов не имеет заказов 2025 года, так как уволен в 2024.
SELECT e.employee_id, e.full_name, ch.channel
FROM employees AS e
     CROSS JOIN ((VALUES ('Прямые продажи'),
                         ('Дистрибуция'),
                         ('Маркетплейс'),
                         ('Тендер'))) AS ch (channel)
     LEFT JOIN orders AS o ON o.employee_id = e.employee_id
                          AND o.channel = ch.channel
                          AND o.order_date >= CAST('2025-01-01' AS date)
                          AND o.order_date < CAST('2026-01-01' AS date)
WHERE e.position = 'Менеджер по продажам' AND o.order_id IS NULL;

-- А10*
SELECT o.*
FROM orders AS o
WHERE o.customer_id = 1
  AND o.shipped_date > (SELECT min(i.due_date)
                        FROM invoices AS i
                             INNER JOIN orders AS x ON x.order_id = i.order_id
                             LEFT JOIN payments AS p ON p.invoice_id = i.invoice_id
                        WHERE x.customer_id = 1 AND p.payment_id IS NULL);
-- А2. За весь период скидки выше 10% давали Соколов И. А. и Попов С. И.
-- Руководитель обоих — Ершова Т. Ю.

-- Вывод
-- Больше всего проблем со скидками у Соколова И. А., его руководитель — Ершова Т. Ю.
-- У Вектора выставлено счетов на 14 716 047,93 руб., оплачено 7 808 447,48 руб.
-- Долг — 6 907 600,45 руб. при лимите 3 млн руб., но отгрузки продолжались.
-- В Сибирском ФО 171 из 181 возврата связан с истёкшим сроком годности.
-- Также найдены пять пар карточек с одинаковым ИНН и 35 заказов клиентов другого менеджера.
-- Из-за дублей выручка и долг клиента разбиваются по карточкам. Нужно сверить ИНН и назначение менеджеров.
-- Для возвратов стоит проверить сроки доставки йогуртов и молока со сроком хранения 7–10 дней.
