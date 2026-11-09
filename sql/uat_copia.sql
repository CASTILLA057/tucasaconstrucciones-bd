-- ============================================================================
-- Hub TuCasaConstrucciones - Plan UAT contra la copia (Supabase, base "postgres")
-- Pensado para pgAdmin 4 (Query Tool) o el SQL Editor de Supabase.
--
-- PARTE A: pruebas que escriben (INT-01..06 y TRG-01..05). Se ejecutan como UN SOLO
--          bloque DO que SIEMPRE termina en una excepcion final: asi TODO lo que el bloque
--          haya escrito se revierte y no queda ningun dato en la base. Los resultados salen
--          en el mensaje de esa excepcion (pestana Messages / panel de errores).
-- PARTE B: consultas de solo lectura (INT-07/08, QRY-01..05, SEC-01/02, PER-01/02 y las
--          validaciones del Anexo 1, E8). Ejecutar una a la vez (seleccionar y F5).
-- ============================================================================

-- ============================ PARTE A (ejecutar completa) ====================
DO $$
DECLARE
  v    text := '';
  prof uuid;
  cli  uuid;
  proj uuid;
  prop uuid;
  blk_h record;
  blk_c record;
  sale uuid;
  mv   uuid;
  st   text;
  t1   timestamptz;
  t2   timestamptz;
BEGIN
  SELECT id INTO prof FROM profiles LIMIT 1;
  SELECT id INTO cli FROM users WHERE user_type = 'client' LIMIT 1;
  SELECT project_id, block_id INTO blk_h FROM blocks WHERE block_kind = 'housing' LIMIT 1;
  SELECT project_id, block_id INTO blk_c FROM blocks WHERE block_kind = 'common_areas' LIMIT 1;

  -- INT-01 llave foranea
  BEGIN
    INSERT INTO blocks (project_id, block_name, block_kind)
    VALUES ('00000000-0000-0000-0000-000000000000', 'X', 'housing');
    v := v || 'INT-01: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'INT-01: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- INT-02 unique
  BEGIN
    INSERT INTO banks (name) SELECT name FROM banks LIMIT 1;
    v := v || 'INT-02: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'INT-02: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- INT-03 check de area negativa (usa un bloque housing valido para pasar el trigger)
  BEGIN
    INSERT INTO properties (project_id, block_id, property_code, property_type, area_sqm, total_price)
    VALUES (blk_h.project_id, blk_h.block_id, 'T-001', 'Casa', -5, 1);
    v := v || 'INT-03: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'INT-03: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- INT-04 check de monto = 0
  BEGIN
    INSERT INTO treasury_movements (movement_type, sub_type, movement_date, amount, created_by)
    VALUES ('income', 'sale_payment', current_date, 0, prof);
    v := v || 'INT-04: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'INT-04: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- INT-05 check de dominio (estado invalido)
  BEGIN
    INSERT INTO projects (project_name, project_location, status)
    VALUES ('Prueba UAT', 'Ocana', 'invalid');
    v := v || 'INT-05: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'INT-05: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- INT-06 columna generada no editable
  BEGIN
    EXECUTE 'INSERT INTO sales (customer_id, property_id, sale_date, total_sale_value, down_payment_total, sale_status, credit_amount)
             VALUES (gen_random_uuid(), gen_random_uuid(), current_date, 100, 20, ''active'', 50)';
    v := v || 'INT-06: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'INT-06: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- TRG-01 inmueble en bloque de zonas comunes
  BEGIN
    INSERT INTO properties (project_id, block_id, property_code, property_type, area_sqm, total_price)
    VALUES (blk_c.project_id, blk_c.block_id, 'T-002', 'Casa', 50, 1);
    v := v || 'TRG-01: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'TRG-01: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- TRG-02 contratista que no es de tipo contractor
  BEGIN
    SELECT project_id INTO proj FROM projects LIMIT 1;
    INSERT INTO contracts (contractor_id, project_id, object_description, estimated_total_value, status)
    VALUES (cli, proj, 'Prueba UAT', 100, 'active');
    v := v || 'TRG-02: NO FALLO (inesperado)' || E'\n';
  EXCEPTION WHEN OTHERS THEN
    v := v || 'TRG-02: ' || SQLSTATE || ' ' || SQLERRM || E'\n';
  END;

  -- TRG-03 venta sincroniza el estado del inmueble
  SELECT property_id INTO prop FROM properties WHERE status = 'available' LIMIT 1;
  INSERT INTO sales (customer_id, property_id, sale_date, total_sale_value, down_payment_total, sale_status, created_by)
  VALUES (cli, prop, current_date, 100000000, 20000000, 'active', prof)
  RETURNING sale_id INTO sale;
  SELECT status INTO st FROM properties WHERE property_id = prop;
  v := v || 'TRG-03a: tras venta activa el inmueble queda en ' || st || E'\n';
  v := v || 'INT-06b: credit_amount calculado = ' || (SELECT credit_amount FROM sales WHERE sale_id = sale) || E'\n';

  -- TRG-04 aplicacion FIFO de un pago de 15.000.000 sobre dos cuotas de 10.000.000
  INSERT INTO payment_plans (sale_id, installment_number, due_date, expected_amount)
  VALUES (sale, 1, current_date, 10000000), (sale, 2, current_date + 30, 10000000);
  INSERT INTO treasury_movements (movement_type, sub_type, movement_date, amount, sale_id, created_by)
  VALUES ('income', 'sale_payment', current_date, 15000000, sale, prof)
  RETURNING movement_id INTO mv;
  v := v || 'TRG-04: aplicacion FIFO (cuota:monto) = ' ||
       COALESCE((SELECT string_agg(pp.installment_number || ':' || pa.applied_amount, ', ' ORDER BY pp.installment_number)
                 FROM payment_applications pa JOIN payment_plans pp ON pp.plan_id = pa.plan_id
                 WHERE pa.movement_id = mv), '(sin aplicaciones)') || E'\n';

  -- TRG-03 (cont.) al cancelar la venta el inmueble vuelve a available
  UPDATE sales SET sale_status = 'canceled' WHERE sale_id = sale;
  SELECT status INTO st FROM properties WHERE property_id = prop;
  v := v || 'TRG-03b: tras cancelar la venta el inmueble queda en ' || st || E'\n';

  -- TRG-05 updated_at de projects
  SELECT project_id, updated_at INTO proj, t1 FROM projects ORDER BY updated_at LIMIT 1;
  UPDATE projects SET progress = progress WHERE project_id = proj;
  SELECT updated_at INTO t2 FROM projects WHERE project_id = proj;
  v := v || 'TRG-05: updated_at antes=' || t1 || ' despues=' || t2 || ' cambio=' || (t2 > t1) || E'\n';

  -- Excepcion final: revierte TODO lo escrito arriba y muestra los resultados
  RAISE EXCEPTION E'RESULTADOS UAT (todo se revirtio, no queda nada en la base):\n%', v;
END $$;

-- ============================ PARTE B (una consulta a la vez) =================

-- INT-07 valores calculados consistentes (esperado: 0)
SELECT count(*) AS diferencias
FROM commitments
WHERE net_payable <> gross_value + tax_amount - retention_amount - advance_amount;

-- INT-08 documentos de tercero duplicados (la base no tiene UNIQUE; esperado: sin filas)
SELECT document_type, document_number, count(*)
FROM users GROUP BY 1, 2 HAVING count(*) > 1;

-- QRY-01 clientes con mas de una compra
SELECT customer_id, COUNT(*) FROM sales GROUP BY customer_id HAVING COUNT(*) > 1;

-- QRY-02 ventas por mes
SELECT date_trunc('month', sale_date) AS mes, SUM(total_sale_value)
FROM sales WHERE sale_status <> 'canceled' GROUP BY 1 ORDER BY 1;

-- QRY-03 facturas con saldo pendiente
SELECT c.invoice_number, u.name, c.net_payable, COALESCE(SUM(tm.amount), 0) AS pagado
FROM commitments c
JOIN users u ON u.id = c.user_id
LEFT JOIN treasury_movements tm ON tm.commitment_id = c.commitment_id AND tm.sub_type = 'commitment_payment'
GROUP BY c.commitment_id, u.name
HAVING c.net_payable - COALESCE(SUM(tm.amount), 0) > 0;

-- QRY-04 total pagado por acreedor (10 mayores)
SELECT u.name, u.user_type, COUNT(*) AS pagos, SUM(tm.amount) AS total
FROM treasury_movements tm
JOIN commitments c ON c.commitment_id = tm.commitment_id
JOIN users u ON u.id = c.user_id
WHERE tm.sub_type = 'commitment_payment'
GROUP BY u.id, u.name, u.user_type
ORDER BY total DESC LIMIT 10;

-- QRY-05 cantidad de filas de las tablas principales (esperado 500, 1000, 500, 500, 200)
SELECT 'projects' AS tabla, count(*) FROM projects
UNION ALL SELECT 'project_activities', count(*) FROM project_activities
UNION ALL SELECT 'commitments', count(*) FROM commitments
UNION ALL SELECT 'treasury_movements', count(*) FROM treasury_movements
UNION ALL SELECT 'sales', count(*) FROM sales;

-- SEC-01 RLS y politicas (la copia debe mostrar 0 y 0: hallazgo de seguridad)
SELECT count(*) FILTER (WHERE relrowsecurity) AS tablas_con_rls,
       (SELECT count(*) FROM pg_policies WHERE schemaname = 'public') AS politicas
FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r';

-- SEC-02 privilegios del rol anonimo (esperado false)
SELECT has_table_privilege('anon', 'public.users', 'SELECT') AS anon_lee_users;

-- PER-01 tiempo de una consulta de varias tablas (ver "Execution Time")
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.invoice_number, u.name, c.net_payable, COALESCE(SUM(tm.amount), 0) AS pagado
FROM commitments c
JOIN users u ON u.id = c.user_id
LEFT JOIN treasury_movements tm ON tm.commitment_id = c.commitment_id AND tm.sub_type = 'commitment_payment'
GROUP BY c.commitment_id, u.name;

-- PER-02 busqueda por llave foranea sin indice (ver si usa Seq Scan)
EXPLAIN (ANALYZE)
SELECT * FROM treasury_movements
WHERE commitment_id = (SELECT commitment_id FROM commitments LIMIT 1);

-- ---------- Validaciones del Anexo 1 (E8) ----------
-- Ventas vigentes cuyo inmueble no esta en estado sold
SELECT s.sale_id FROM sales s JOIN properties p ON p.property_id = s.property_id
WHERE s.sale_status <> 'canceled' AND p.status <> 'sold';

-- Inmuebles con mas de una venta vigente
SELECT property_id, count(*) FROM sales WHERE sale_status <> 'canceled' GROUP BY 1 HAVING count(*) > 1;

-- Proyectos con fecha de fin anterior a la de inicio
SELECT project_id FROM projects WHERE end_date < start_date;

-- Facturas pagadas por encima de su neto
SELECT c.commitment_id, c.net_payable, SUM(tm.amount) AS pagado
FROM commitments c
JOIN treasury_movements tm ON tm.commitment_id = c.commitment_id AND tm.sub_type = 'commitment_payment'
GROUP BY c.commitment_id, c.net_payable
HAVING SUM(tm.amount) > c.net_payable;

-- Suma de cuotas distinta del valor de la venta
SELECT s.sale_id, s.total_sale_value, SUM(pp.expected_amount) AS suma_cuotas
FROM sales s JOIN payment_plans pp ON pp.sale_id = s.sale_id
GROUP BY s.sale_id, s.total_sale_value
HAVING SUM(pp.expected_amount) <> s.total_sale_value;

-- Aplicaciones de pago por encima del valor de la cuota
SELECT pp.plan_id, pp.expected_amount, SUM(pa.applied_amount) AS aplicado
FROM payment_plans pp JOIN payment_applications pa ON pa.plan_id = pp.plan_id
GROUP BY pp.plan_id, pp.expected_amount
HAVING SUM(pa.applied_amount) > pp.expected_amount;

-- ============================ PARTE C (SEC-03, PER-03 y concurrencia) ===========
-- Cada bloque DO termina en una excepcion: no deja datos en la base.

-- SEC-03 SQL injection: parametrizada (esperado 0) vs concatenada (devuelve todos los usuarios)
DO $$ DECLARE inj text := chr(39) || ' OR 1=1 --'; a int; b int;
BEGIN
  EXECUTE 'SELECT count(*) FROM users WHERE email = $1' INTO a USING inj;
  EXECUTE 'SELECT count(*) FROM users WHERE email = ' || chr(39) || inj || chr(39) INTO b;
  RAISE EXCEPTION 'SEC-03 resultado: parametrizada=% concatenada=%', a, b;
END $$;

-- PER-03 un millon de filas en una tabla temporal (se descarta al terminar)
DO $$ DECLARE t0 timestamptz; t1 numeric; t2 numeric; t3 numeric;
BEGIN
  CREATE TEMP TABLE t_big AS SELECT g AS id, g % 1000 AS k, random() AS v FROM generate_series(1, 1000000) g;
  t0 := clock_timestamp(); PERFORM count(*) FROM (SELECT k, count(*), sum(v) FROM t_big GROUP BY k) x;
  t1 := extract(epoch FROM clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp(); PERFORM id FROM t_big WHERE id = 777777;
  t2 := extract(epoch FROM clock_timestamp() - t0) * 1000;
  CREATE INDEX ON t_big (id); ANALYZE t_big;
  t0 := clock_timestamp(); PERFORM id FROM t_big WHERE id = 777777;
  t3 := extract(epoch FROM clock_timestamp() - t0) * 1000;
  RAISE EXCEPTION 'PER-03 con 1000000 filas: group by = % ms; busqueda sin indice = % ms; busqueda con indice = % ms', round(t1, 1), round(t2, 2), round(t3, 3);
END $$;

-- CON-01 / CON-02 concurrencia: se necesitan DOS ventanas (sesiones) del Query Tool o del SQL Editor.
-- Sesion A (ejecutar primero; mantiene la fila bloqueada 120 s y luego revierte):
DO $$ BEGIN
  UPDATE projects SET progress = 99 WHERE project_id = (SELECT project_id FROM projects ORDER BY project_name LIMIT 1);
  PERFORM pg_sleep(120);
  RAISE EXCEPTION 'sesion A termino: rollback';
END $$;

-- Sesion B, CON-02 (lectura mientras A escribe; ejecutar en los primeros segundos): no espera y ve el valor confirmado
DO $$ DECLARE t0 timestamptz := clock_timestamp(); p int; a int;
BEGIN
  SELECT count(*) INTO a FROM pg_stat_activity WHERE state = 'active' AND query LIKE '%pg_sleep(120)%' AND pid <> pg_backend_pid();
  SELECT progress INTO p FROM projects WHERE project_id = (SELECT project_id FROM projects ORDER BY project_name LIMIT 1);
  RAISE EXCEPTION 'CON-02 sesion B lectura: progress=% obtenido en % ms; sesiones A activas=%', p, round(extract(epoch FROM clock_timestamp() - t0) * 1000), a;
END $$;

-- Sesion B, CON-01 (escritura sobre la misma fila): espera hasta que A termine
DO $$ DECLARE t0 timestamptz := clock_timestamp();
BEGIN
  UPDATE projects SET progress = 98 WHERE project_id = (SELECT project_id FROM projects ORDER BY project_name LIMIT 1);
  RAISE EXCEPTION 'CON-01 sesion B actualizo la misma fila despues de esperar % segundos', round(extract(epoch FROM clock_timestamp() - t0)::numeric, 1);
END $$;
