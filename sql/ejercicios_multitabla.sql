-- ============================================================================
-- EJERCICIOS DE CONSULTAS MULTITABLA - copia de la base del Hub
-- Servidor en pgAdmin: "Hub companero (Supabase)"  ->  base: postgres
-- Todo es SELECT (no modifica nada). Las soluciones estan al final y fueron
-- ejecutadas contra la base el 2026-11-08; los resultados dependen de los datos.
-- Intenta cada ejercicio SIN mirar la solucion.
-- ============================================================================
--
-- MAPA DE RELACIONES (flecha = llave foranea)
--
--   projects  <-- commitments.project_id          (facturas del proyecto)
--   projects  <-- project_activities.project_id   (presupuesto / actividades)
--   projects  <-- treasury_movements.project_id   (ingresos y egresos)
--   projects  <-- blocks.project_id               (bloques/torres)
--   projects  <-- properties.project_id            (viviendas)
--   properties <-- sales.property_id               (OJO: sales NO tiene project_id;
--                                                   para llegar al proyecto: sales -> properties -> projects)
--   users     <-- commitments.user_id              (acreedor)
--   users     <-- sales.customer_id                (cliente)
--   commitments <-- treasury_movements.commitment_id   (pago de una factura)
--   sales       <-- treasury_movements.sale_id         (pago de una venta)
--   commitments <-- commitment_details.commitment_id   (items de la factura)
--   chapters / activity_catalog / units / blocks <-- project_activities
--   payment_methods <-- treasury_movements.payment_method_id
--
-- VALORES UTILES
--   projects.status:            active | completed | on_hold
--   treasury_movements.movement_type: income | expense
--   treasury_movements.sub_type:      sale_payment | commitment_payment | petty_cash_expense | contract_advance
--   sales.sale_status:          active | completed | canceled
--   commitments.commitment_type: invoice | collection_account | contract_settlement
--
-- CONSEJO: antes de cada consulta piensa "de que tabla sale lo que me piden y
-- por que columnas se conectan". Dibuja el camino de joins en papel.
-- ============================================================================


-- ============================ NIVEL 1: 2 o 3 tablas ==========================

-- E1. Las 10 facturas mas recientes con el nombre de su proyecto.
--     (commitments, projects)

-- E2. Cuantos movimientos de tesoreria hay por metodo de pago y cuanto suman.
--     Ordena del mayor al menor total.   (treasury_movements, payment_methods)

-- E3. Las 10 actividades de mayor costo presupuestado con el nombre del
--     proyecto, el nombre de la actividad y el capitulo.
--     (project_activities, projects, activity_catalog, chapters)


-- ====================== NIVEL 2: agregados y varias tablas ===================

-- E4. Total facturado y numero de facturas por ESTADO del proyecto.
--     (commitments, projects)

-- E5. Las 10 ventas mas recientes con: fecha, nombre del cliente, codigo y tipo
--     de la vivienda, nombre del proyecto, valor total y estado de la venta.
--     (sales, users, properties, projects)

-- E6. Cuanto se ha pagado a cada acreedor en pagos de facturas
--     (sub_type = 'commitment_payment'). Muestra nombre, tipo de tercero,
--     numero de pagos y total pagado; los 10 mayores.
--     (treasury_movements, commitments, users)

-- E7. Facturas con SALDO pendiente: neto a pagar - pagos de factura recibidos.
--     Muestra numero, acreedor, neto, pagado y saldo; solo las que deben algo.
--     Pista: LEFT JOIN a los pagos + GROUP BY + HAVING.
--     (commitments, users, treasury_movements)

-- E8. Por proyecto: numero de actividades y presupuesto total (suma de
--     budgeted_cost). Los 10 proyectos con mayor presupuesto.
--     (projects, project_activities)

-- E9. Cliente(s) con 2 o mas compras NO canceladas: nombre, numero de compras y
--     total comprado. Los 5 mayores.   (sales, users)

-- E10. Ingresos, egresos y neto de tesoreria por MES. Pista: date_trunc y
--      SUM(...) FILTER (WHERE ...).   (treasury_movements)

-- E11. Facturas con sus items: numero de factura, capitulo, descripcion,
--      cantidad y total del item (solo las que tienen items; las otras no
--      deben salir). Capitulo puede ser NULL -> que el item igual aparezca.
--      (commitment_details, commitments, chapters)


-- ============== NIVEL 3: subconsultas, CTE, anti-join y ventanas =============

-- E12. Proyectos que NUNCA han tenido una venta (via properties -> sales).
--      Resuelvelo de DOS formas: NOT EXISTS, y LEFT JOIN + GROUP BY/HAVING.
--      Pregunta de examen: por que "LEFT JOIN ... WHERE s.sale_id IS NULL"
--      puede dar un resultado distinto cuando un proyecto tiene varias viviendas?
--      (projects, properties, sales)

-- E13. Por proyecto, lado a lado: presupuesto (project_activities), facturado
--      (commitments) y movimientos de tesoreria (ingresos y egresos).
--      CUIDADO con el error clasico: si haces los 3 JOIN directos y luego SUM,
--      las filas se MULTIPLICAN y los totales salen inflados. Soluciona con CTE
--      (una agregacion por tabla) y luego une.
--      (projects, project_activities, commitments, treasury_movements)

-- E14. Los 2 proyectos con mayor presupuesto DENTRO de cada estado de proyecto.
--      Pista: RANK() OVER (PARTITION BY ... ORDER BY ...) y filtra en una
--      consulta externa.   (projects, project_activities)

-- E15. Contratos: contratista, proyecto, valor estimado, lo ejecutado en actas
--      (contract_advances), los anticipos entregados (treasury_movements con
--      sub_type = 'contract_advance') y lo que falta por ejecutar.
--      (contracts, users, projects, contract_advances, treasury_movements)

-- E16. Ficha completa de actividad (6 tablas): proyecto, bloque, tipo de bloque,
--      capitulo, nombre de la actividad, unidad, cantidad y costo presupuestado.
--      Pista: project_activities enlaza a blocks por block_id Y project_id.
--      (project_activities, projects, blocks, chapters, activity_catalog, units)

-- BONUS A. Pagos de ventas (sub_type = 'sale_payment') por proyecto y cliente:
--          camino treasury_movements -> sales -> properties -> projects y
--          sales -> users.
-- BONUS B. Facturas sin NINGUN pago registrado.
-- BONUS C. Porcentaje del total facturado que representa cada tipo de factura
--          (commitment_type) usando una funcion de ventana (SUM() OVER ()).
--          (Estos tres no traen solucion: si los resuelves, compruebalos con
--           COUNT(*) o con un total que ya conozcas.)

































-- ============================================================================
-- ============================  SOLUCIONES  ==================================
-- ============================================================================
-- (Estan mas abajo a proposito. Intenta primero.)

































-- E1
SELECT c.invoice_number, c.commitment_date, c.invoice_total, p.project_name
FROM commitments c
JOIN projects p ON p.project_id = c.project_id
ORDER BY c.commitment_date DESC
LIMIT 10;

-- E2
SELECT pm.name AS metodo_pago, COUNT(*) AS movimientos, SUM(tm.amount) AS total
FROM treasury_movements tm
JOIN payment_methods pm ON pm.id = tm.payment_method_id
GROUP BY pm.name
ORDER BY total DESC;

-- E3
SELECT p.project_name, ac.name AS actividad, ch.chapter_name, pa.budgeted_cost
FROM project_activities pa
JOIN projects p ON p.project_id = pa.project_id
JOIN activity_catalog ac ON ac.activity_catalog_id = pa.activity_catalog_id
JOIN chapters ch ON ch.chapter_id = pa.chapter_id
ORDER BY pa.budgeted_cost DESC
LIMIT 10;

-- E4
SELECT p.status AS estado_proyecto, COUNT(*) AS facturas, SUM(c.invoice_total) AS total_facturado
FROM commitments c
JOIN projects p ON p.project_id = c.project_id
GROUP BY p.status
ORDER BY total_facturado DESC;

-- E5
SELECT s.sale_date, u.name AS cliente, pr.property_code, pr.property_type,
       p.project_name, s.total_sale_value, s.sale_status
FROM sales s
JOIN users u ON u.id = s.customer_id
JOIN properties pr ON pr.property_id = s.property_id
JOIN projects p ON p.project_id = pr.project_id
ORDER BY s.sale_date DESC
LIMIT 10;

-- E6
SELECT u.name AS acreedor, u.user_type, COUNT(*) AS pagos, SUM(tm.amount) AS total_pagado
FROM treasury_movements tm
JOIN commitments c ON c.commitment_id = tm.commitment_id
JOIN users u ON u.id = c.user_id
WHERE tm.sub_type = 'commitment_payment'
GROUP BY u.name, u.user_type
ORDER BY total_pagado DESC
LIMIT 10;

-- E7  (simplificacion: la app calcula el saldo con la vista v_commitment_balance,
--      que ademas considera commitment_applications; aqui solo los pagos directos)
SELECT c.invoice_number, u.name AS acreedor, c.net_payable,
       COALESCE(SUM(tm.amount), 0) AS pagado,
       c.net_payable - COALESCE(SUM(tm.amount), 0) AS saldo
FROM commitments c
JOIN users u ON u.id = c.user_id
LEFT JOIN treasury_movements tm
       ON tm.commitment_id = c.commitment_id AND tm.sub_type = 'commitment_payment'
GROUP BY c.commitment_id, c.invoice_number, u.name, c.net_payable
HAVING c.net_payable - COALESCE(SUM(tm.amount), 0) > 0
ORDER BY saldo DESC
LIMIT 20;

-- E8
SELECT p.project_name, COUNT(*) AS actividades, SUM(pa.budgeted_cost) AS presupuesto
FROM projects p
JOIN project_activities pa ON pa.project_id = p.project_id
GROUP BY p.project_id, p.project_name
ORDER BY presupuesto DESC
LIMIT 10;

-- E9
SELECT u.name AS cliente, COUNT(*) AS compras, SUM(s.total_sale_value) AS total_comprado
FROM sales s
JOIN users u ON u.id = s.customer_id
WHERE s.sale_status <> 'canceled'
GROUP BY u.id, u.name
HAVING COUNT(*) >= 2
ORDER BY total_comprado DESC
LIMIT 5;

-- E10
SELECT date_trunc('month', tm.movement_date)::date AS mes,
       SUM(tm.amount) FILTER (WHERE tm.movement_type = 'income')  AS ingresos,
       SUM(tm.amount) FILTER (WHERE tm.movement_type = 'expense') AS egresos,
       SUM(CASE tm.movement_type WHEN 'income' THEN tm.amount ELSE -tm.amount END) AS neto
FROM treasury_movements tm
GROUP BY 1
ORDER BY 1 DESC;

-- E11
SELECT c.invoice_number, ch.chapter_name, cd.description, cd.quantity, cd.total_price
FROM commitment_details cd
JOIN commitments c ON c.commitment_id = cd.commitment_id
LEFT JOIN chapters ch ON ch.chapter_id = cd.chapter_id
ORDER BY cd.total_price DESC;

-- E12 (a) NOT EXISTS
SELECT p.project_id, p.project_name
FROM projects p
WHERE NOT EXISTS (
  SELECT 1
  FROM properties pr
  JOIN sales s ON s.property_id = pr.property_id
  WHERE pr.project_id = p.project_id
);
-- E12 (b) LEFT JOIN + GROUP BY/HAVING (COUNT de la columna del lado derecho)
SELECT p.project_id, p.project_name
FROM projects p
LEFT JOIN properties pr ON pr.project_id = p.project_id
LEFT JOIN sales s ON s.property_id = pr.property_id
GROUP BY p.project_id, p.project_name
HAVING COUNT(s.sale_id) = 0;
-- Respuesta a la pregunta: con "LEFT JOIN ... WHERE s.sale_id IS NULL" un proyecto
-- con una vivienda vendida y otra sin vender SI aparece (por la fila de la
-- vivienda sin venta) aunque tenga ventas. Con los datos actuales cada proyecto
-- tiene como maximo 1 vivienda, asi que las tres formas dan 300 y el error no se
-- nota; con varias viviendas por proyecto si.

-- E13  (una agregacion por tabla en un CTE para no multiplicar filas)
WITH presupuesto AS (
  SELECT project_id, SUM(budgeted_cost) AS total
  FROM project_activities GROUP BY project_id
), facturado AS (
  SELECT project_id, SUM(invoice_total) AS total
  FROM commitments GROUP BY project_id
), movido AS (
  SELECT project_id,
         SUM(amount) FILTER (WHERE movement_type = 'income')  AS ingresos,
         SUM(amount) FILTER (WHERE movement_type = 'expense') AS egresos
  FROM treasury_movements GROUP BY project_id
)
SELECT p.project_name,
       COALESCE(pr.total, 0)    AS presupuesto,
       COALESCE(f.total, 0)     AS facturado,
       COALESCE(m.ingresos, 0)  AS ingresos,
       COALESCE(m.egresos, 0)   AS egresos
FROM projects p
LEFT JOIN presupuesto pr ON pr.project_id = p.project_id
LEFT JOIN facturado   f  ON f.project_id  = p.project_id
LEFT JOIN movido      m  ON m.project_id  = p.project_id
ORDER BY presupuesto DESC
LIMIT 20;

-- E14
SELECT *
FROM (
  SELECT p.status, p.project_name, SUM(pa.budgeted_cost) AS presupuesto,
         RANK() OVER (PARTITION BY p.status ORDER BY SUM(pa.budgeted_cost) DESC) AS puesto
  FROM projects p
  JOIN project_activities pa ON pa.project_id = p.project_id
  GROUP BY p.project_id, p.status, p.project_name
) t
WHERE puesto <= 2
ORDER BY status, puesto;

-- E15
WITH anticipos AS (
  SELECT contract_id, SUM(amount) AS total
  FROM treasury_movements WHERE sub_type = 'contract_advance' GROUP BY contract_id
), ejecutado AS (
  SELECT contract_id, SUM(execution_value) AS total
  FROM contract_advances GROUP BY contract_id
)
SELECT u.name AS contratista, p.project_name, c.estimated_total_value,
       COALESCE(e.total, 0) AS ejecutado,
       COALESCE(a.total, 0) AS anticipos,
       c.estimated_total_value - COALESCE(e.total, 0) AS por_ejecutar
FROM contracts c
JOIN users u ON u.id = c.contractor_id
JOIN projects p ON p.project_id = c.project_id
LEFT JOIN ejecutado e ON e.contract_id = c.contract_id
LEFT JOIN anticipos a ON a.contract_id = c.contract_id
ORDER BY por_ejecutar DESC;

-- E16
SELECT p.project_name, b.block_name, b.block_kind, ch.chapter_name,
       ac.name AS actividad, un.unit_name, pa.budgeted_quantity, pa.budgeted_cost
FROM project_activities pa
JOIN projects p ON p.project_id = pa.project_id
JOIN blocks b ON b.block_id = pa.block_id AND b.project_id = pa.project_id
JOIN chapters ch ON ch.chapter_id = pa.chapter_id
JOIN activity_catalog ac ON ac.activity_catalog_id = pa.activity_catalog_id
JOIN units un ON un.unit_id = pa.unit_id
ORDER BY pa.budgeted_cost DESC
LIMIT 20;
