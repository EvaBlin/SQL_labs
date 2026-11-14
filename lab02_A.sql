-- Лабораторная работа 2
-- Товстюк Е. А. Команда А «Финансы и продажи».
-- Проверены типы данных, контакты, сроки отгрузки, оплаты и цены.
SET search_path TO 'pitanie', 'public';

-- О1. При делении integer на integer дробная часть отбрасывается.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'pitanie' AND table_name = 'order_items'
ORDER BY ordinal_position;

-- О2. Календарь декабря с названиями дней на русском.
SELECT CAST(d AS date) AS day,
       to_char(d, 'TMDay') AS weekday_server_locale,
       CASE EXTRACT(ISODOW FROM d)
         WHEN 1
           THEN 'понедельник'
         WHEN 2
           THEN 'вторник'
         WHEN 3
           THEN 'среда'
         WHEN 4
           THEN 'четверг'
         WHEN 5
           THEN 'пятница'
         WHEN 6
           THEN 'суббота'
         WHEN 7
           THEN 'воскресенье'
       END AS weekday,
       CASE
         WHEN EXTRACT(ISODOW FROM d) <= 5 THEN 'рабочий'
         ELSE 'выходной'
       END AS day_type
FROM generate_series(CAST('2025-12-01' AS date),
                     CAST('2025-12-31' AS date),
                     CAST('1 day' AS interval)) AS g (d);

-- А1. Очистка email. COUNT(email) не считает NULL.
SELECT customer_id, '[' || email || ']' AS original, lower(TRIM(email)) AS clean
FROM customers
WHERE email <> lower(TRIM(email));

SELECT count(*) AS total,
       count(email) AS has_email,
       sum(CASE WHEN email <> lower(TRIM(email)) THEN 1 ELSE 0 END) AS dirty
FROM customers;

-- А2. Приводим телефоны к одному формату.
SELECT DISTINCT regexp_replace(phone, '\d', '9', 'g') AS mask
FROM customers
ORDER BY mask;

SELECT customer_id, '+7' || "right"(regexp_replace(phone, '\D', '', 'g'), 10) AS phone
FROM customers
ORDER BY customer_id;

SELECT count(*)
FROM customers
WHERE '+7' || "right"(regexp_replace(phone, '\D', '', 'g'), 10) !~ '^\+7\d{10}$'
   OR phone IS NULL;

-- А3. Убираем лишние символы в названиях и ищем повторяющиеся ИНН.
SELECT customer_id,
       customer_name,
       inn,
       TRIM(regexp_replace(regexp_replace(upper(customer_name),
                                                      '\m(ООО|АО|ИП)\M|"|\(ДУБЛЬ\)',
                                                      '',
                                                      'g'),
                                       '\s+',
                                       ' ',
                                       'g')) AS normalized
FROM customers
ORDER BY inn, customer_id;

SELECT inn,
       count(*) AS records,
       string_agg(CAST(customer_id AS text), ', ' ORDER BY customer_id) AS ids
FROM customers
GROUP BY inn
HAVING count(*) > 1;
-- Повторяются ИНН Ромашки, Свежести и Колоса. У Колоса названия различаются даже после очистки.

-- А4. Сроки доставки. Клиенты без региона попадают в группу «остальные».
SELECT o.order_id,
       c.region_id,
       o.shipped_date - o.order_date AS shipping_days,
       CASE
         WHEN o.shipped_date - o.order_date <= 3
           THEN '1–3 дня'
         WHEN o.shipped_date - o.order_date <= 6
           THEN '4–6 дней'
         ELSE '7+ дней'
       END AS shipping_class
FROM orders AS o INNER JOIN customers AS c ON c.customer_id = o.customer_id
WHERE o.shipped_date IS NOT NULL
ORDER BY shipping_days DESC, o.order_id
LIMIT 10;

SELECT sum(CASE WHEN c.region_id IN (9, 10) THEN 1 ELSE 0 END) AS siberia,
       sum(CASE
             WHEN c.region_id IN (9, 10) AND o.shipped_date - o.order_date >= 5 THEN 1
             ELSE 0
           END) AS siberia_slow,
       sum(CASE
             WHEN c.region_id IS DISTINCT FROM 9 AND c.region_id IS DISTINCT FROM 10 THEN 1
             ELSE 0
           END) AS others,
       sum(CASE
             WHEN c.region_id IS DISTINCT FROM 9
              AND c.region_id IS DISTINCT FROM 10
              AND o.shipped_date - o.order_date >= 5
               THEN 1
             ELSE 0
           END) AS others_slow
FROM orders AS o INNER JOIN customers AS c ON c.customer_id = o.customer_id
WHERE o.shipped_date IS NOT NULL;

-- Срок хранения 7–10 дней у двух йогуртов, двух видов молока, кефира и ряженки.
-- Долгая доставка оставляет клиенту меньше времени на продажу.

-- А5. Просрочка оплат.
SELECT p.payment_id,
       o.customer_id,
       p.payment_date - i.due_date AS late_days,
       CASE
         WHEN p.payment_date <= i.due_date
           THEN 'в срок'
         WHEN p.payment_date - i.due_date <= 30
           THEN 'до 30 дней'
         ELSE 'более 30 дней'
       END AS delay_class
FROM payments AS p
     INNER JOIN invoices AS i ON i.invoice_id = p.invoice_id
     INNER JOIN orders AS o ON o.order_id = i.order_id
ORDER BY late_days DESC, p.payment_id
LIMIT 10;

SELECT count(*) AS overdue_30,
       sum(CASE WHEN o.customer_id = 1 THEN 1 ELSE 0 END) AS vector_count
FROM payments AS p
     INNER JOIN invoices AS i ON i.invoice_id = p.invoice_id
     INNER JOIN orders AS o ON o.order_id = i.order_id
WHERE p.payment_date - i.due_date > 30;

SELECT customer_id, customer_name, credit_limit
FROM customers
WHERE customer_id = 1;
-- Лимит Вектора — 3 млн руб. Для оценки риска нужны остатки по счетам и сроки просрочки.

-- А6. Продажи ниже себестоимости. Считаем процент от затрат и от выручки.
SELECT oi.order_item_id,
       p.sku,
       round(oi.unit_price * (1 - oi.discount_pct / 100), 2) AS net_price,
       round(oi.unit_price * (1 - oi.discount_pct / 100) - p.standard_cost, 2) AS unit_margin,
       round(100 * (oi.unit_price * (1 - oi.discount_pct / 100) - p.standard_cost) / NULLIF(p.standard_cost, 0),
             1) AS margin_pct_of_cost,
       round(100 * (oi.unit_price * (1 - oi.discount_pct / 100) - p.standard_cost) / NULLIF(oi.unit_price * (1 - oi.discount_pct / 100),
                                                                                            0),
             1) AS margin_pct_of_revenue
FROM order_items AS oi
     INNER JOIN orders AS o ON o.order_id = oi.order_id
     INNER JOIN products AS p ON p.product_id = oi.product_id
WHERE o.order_date >= CAST('2025-03-01' AS date)
  AND o.status <> 'Отменён'
  AND oi.unit_price * (1 - oi.discount_pct / 100) < p.standard_cost
ORDER BY unit_margin, oi.order_item_id;

-- ★ А6.3. Суммарная потеря.
SELECT count(*) AS lines,
       round(sum(oi.quantity * (p.standard_cost - oi.unit_price * (1 - oi.discount_pct / 100))),
             2) AS loss
FROM order_items AS oi
     INNER JOIN orders AS o ON o.order_id = oi.order_id
     INNER JOIN products AS p ON p.product_id = oi.product_id
WHERE o.order_date >= CAST('2025-03-01' AS date)
  AND o.status <> 'Отменён'
  AND oi.unit_price * (1 - oi.discount_pct / 100) < p.standard_cost;

-- А7. Собираем строку для отчёта.
SELECT format('Счёт %s от %s %s %s на сумму %s руб., оплатить до %s',
              invoice_number,
              to_char(invoice_date, 'DD'),
              CASE EXTRACT(MONTH FROM invoice_date)
                WHEN 1
                  THEN 'Января'
                WHEN 2
                  THEN 'Февраля'
                WHEN 3
                  THEN 'Марта'
                WHEN 4
                  THEN 'Апреля'
                WHEN 5
                  THEN 'Мая'
                WHEN 6
                  THEN 'Июня'
                WHEN 7
                  THEN 'Июля'
                WHEN 8
                  THEN 'Августа'
                WHEN 9
                  THEN 'Сентября'
                WHEN 10
                  THEN 'Октября'
                WHEN 11
                  THEN 'Ноября'
                WHEN 12
                  THEN 'Декабря'
              END,
              to_char(invoice_date, 'YYYY'),
              regexp_replace(regexp_replace(to_char(amount, 'FM999,999,990.00'), ',', ' ', 'g'),
                             '\.', ',', 'g'),
              to_char(due_date, 'DD.MM.YYYY')) AS report_line
FROM invoices
ORDER BY amount DESC, invoice_id DESC
LIMIT 3;

-- ★ А8. Сверка с историей прайса.
SELECT count(*) AS mismatches
FROM order_items AS oi
     INNER JOIN orders AS o ON o.order_id = oi.order_id
     INNER JOIN price_history AS ph ON ph.product_id = oi.product_id
                                   AND o.order_date BETWEEN ph.valid_from AND COALESCE(ph.valid_to,
                                                                                       CAST('9999-12-31' AS date))
WHERE oi.unit_price <> ph.price;
-- А8*. Расхождений с прайсом нет. Причину убытка ищем в скидках и себестоимости.

-- Вывод
-- У 52 из 73 клиентов указан email, но 32 адреса нужно исправить.
-- Телефоны записаны в четырёх форматах; три повторяющихся ИНН объединяют семь карточек.
-- В Новосибирской области и Красноярском крае 869 из 932 отгрузок занимают не меньше пяти дней.
-- Для продуктов со сроком годности 7–10 дней это может быть проблемой.
-- Оплат с задержкой больше 30 дней — 231, из них 13 у Вектора.
-- У двух видов масла с марта 2025 года убыток по 314 позициям составил 3 661 609 руб.; нужно проверить
-- цены с коммерческим отделом и себестоимость с закупками.
