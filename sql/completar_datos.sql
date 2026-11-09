-- ============================================================================
-- Hub TuCasaConstrucciones - Carga complementaria de datos sinteticos (09/11/2026)
-- Corrige los 3 hallazgos de la revision de calidad (Anexo 1, E4):
--   1) 470 compromisos sin items         -> commitment_details (+ commitment_applications vacia)
--   2) 250 proyectos sin inmuebles       -> properties
--   3) 20 proveedores/contratistas sin cuenta bancaria -> bank_accounts
-- No toca las cantidades pedidas por el profesor (projects, project_activities,
-- commitments, treasury_movements y sales quedan igual).
-- Los datos se generan de forma DETERMINISTA (hashtext) a partir de los datos existentes.
-- v_dry = true  -> prueba: valida y REVIERTE todo (termina en una excepcion informativa).
-- v_dry = false -> confirma los cambios.
-- ============================================================================
DO $$
DECLARE
  v_dry boolean := false;
  n_items int;
  n_apps int;
  n_props int;
  n_accts int;
  bad int;
BEGIN
  -- 1) Items de los compromisos que no tienen (1 a 3 por compromiso; la suma de los items = valor bruto)
  WITH c AS (
    SELECT commitment_id, project_id, gross_value,
           1 + abs(hashtext(commitment_id::text)) % 3 AS n
    FROM commitments c
    WHERE NOT EXISTS (SELECT 1 FROM commitment_details d WHERE d.commitment_id = c.commitment_id)
  ),
  act AS (
    SELECT activity_id, project_id, chapter_id,
           row_number() OVER (PARTITION BY project_id ORDER BY activity_id) AS rn,
           count(*) OVER (PARTITION BY project_id) AS k
    FROM project_activities
  ),
  it AS (
    SELECT c.commitment_id, c.project_id, c.gross_value, c.n, g.i,
           1 + abs(hashtext(c.commitment_id::text || '-' || g.i)) % 5 AS w
    FROM c
    CROSS JOIN LATERAL generate_series(1, c.n) AS g(i)
  ),
  sized AS (
    SELECT *, sum(w) OVER (PARTITION BY commitment_id) AS sw FROM it
  ),
  part AS (
    SELECT *, CASE WHEN i < n THEN floor(gross_value * w / sw / 10000) * 10000 END AS p FROM sized
  ),
  fin AS (
    SELECT *, CASE WHEN i < n THEN p
                   ELSE gross_value - COALESCE(sum(p) OVER (PARTITION BY commitment_id), 0) END AS amount
    FROM part
  ),
  pick AS (
    SELECT f.*, a.activity_id, a.chapter_id
    FROM fin f
    JOIN act a ON a.project_id = f.project_id AND a.rn = ((f.i - 1) % a.k) + 1
  )
  INSERT INTO commitment_details (commitment_id, activity_id, chapter_id, description, quantity, unit_price)
  SELECT pk.commitment_id, pk.activity_id, pk.chapter_id,
         (SELECT ch.chapter_name FROM chapters ch WHERE ch.chapter_id = pk.chapter_id) || ': ' ||
         (ARRAY['suministro de materiales', 'mano de obra', 'alquiler de equipo', 'transporte',
                'servicios tecnicos', 'obra complementaria'])[1 + abs(hashtext(pk.commitment_id::text || '/' || pk.i)) % 6],
         q.qty,
         pk.amount / q.qty
  FROM pick pk
  CROSS JOIN LATERAL (
    SELECT CASE WHEN pk.amount % (ARRAY[1, 2, 4, 5, 10])[1 + abs(hashtext(pk.commitment_id::text || '#' || pk.i)) % 5] = 0
                THEN (ARRAY[1, 2, 4, 5, 10])[1 + abs(hashtext(pk.commitment_id::text || '#' || pk.i)) % 5]
                ELSE 1 END AS qty
  ) q;
  GET DIAGNOSTICS n_items = ROW_COUNT;

  -- 1b) Aplicacion de cada pago de compromiso a su compromiso (commitment_applications estaba vacia)
  INSERT INTO commitment_applications (movement_id, commitment_id, applied_amount)
  SELECT tm.movement_id, tm.commitment_id, tm.amount
  FROM treasury_movements tm
  WHERE tm.sub_type = 'commitment_payment'
    AND tm.commitment_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM commitment_applications ca WHERE ca.movement_id = tm.movement_id);
  GET DIAGNOSTICS n_apps = ROW_COUNT;

  -- 2) Un inmueble para cada proyecto que no tiene (en su bloque de viviendas, codigo P-####-101)
  INSERT INTO properties (project_id, block_id, property_code, property_type, area_sqm, total_price, status)
  SELECT p.project_id, b.block_id,
         'P-' || lpad(substring(p.project_name from 'Proyecto ([0-9]+)'), 4, '0') || '-101',
         (ARRAY['Apartamento', 'Casa', 'Local comercial'])[1 + abs(hashtext(p.project_id::text)) % 3],
         a.area,
         a.area * (3000000 + 250000 * (abs(hashtext(p.project_id::text || 'precio')) % 10)),
         'available'
  FROM projects p
  JOIN blocks b ON b.project_id = p.project_id AND b.block_kind = 'housing'
  CROSS JOIN LATERAL (SELECT 40 + abs(hashtext(p.project_id::text || 'area')) % 81 AS area) a
  WHERE NOT EXISTS (SELECT 1 FROM properties x WHERE x.project_id = p.project_id);
  GET DIAGNOSTICS n_props = ROW_COUNT;

  -- 3) Cuenta bancaria principal para cada proveedor o contratista que no tiene
  INSERT INTO bank_accounts (user_id, bank_id, account_type, account_number, is_primary)
  SELECT u.id,
         (SELECT bk.id FROM banks bk ORDER BY bk.id OFFSET (abs(hashtext(u.id::text)) % 15) LIMIT 1),
         (ARRAY['savings', 'checking', 'digital_wallet'])[1 + abs(hashtext(u.id::text || 'tipo')) % 3],
         '70' || lpad((abs(hashtext(u.id::text || 'cuenta')) % 100000000)::text, 8, '0'),
         true
  FROM users u
  WHERE u.user_type IN ('provider', 'contractor')
    AND NOT EXISTS (SELECT 1 FROM bank_accounts b WHERE b.user_id = u.id);
  GET DIAGNOSTICS n_accts = ROW_COUNT;

  -- Validaciones: si alguna falla, la excepcion revierte TODO
  SELECT count(*) INTO bad FROM commitments c
  WHERE NOT EXISTS (SELECT 1 FROM commitment_details d WHERE d.commitment_id = c.commitment_id);
  IF bad > 0 THEN RAISE EXCEPTION 'Quedan % compromisos sin items', bad; END IF;

  SELECT count(*) INTO bad FROM (
    SELECT d.commitment_id FROM commitment_details d JOIN commitments c ON c.commitment_id = d.commitment_id
    GROUP BY d.commitment_id, c.gross_value HAVING sum(d.total_price) <> c.gross_value) x;
  IF bad > 0 THEN RAISE EXCEPTION '% compromisos con suma de items distinta del valor bruto', bad; END IF;

  SELECT count(*) INTO bad FROM (
    SELECT ca.commitment_id FROM commitment_applications ca JOIN commitments c ON c.commitment_id = ca.commitment_id
    GROUP BY ca.commitment_id, c.net_payable HAVING sum(ca.applied_amount) > c.net_payable) x;
  IF bad > 0 THEN RAISE EXCEPTION '% compromisos pagados por encima del neto a pagar', bad; END IF;

  SELECT count(*) INTO bad FROM projects p WHERE NOT EXISTS (SELECT 1 FROM properties x WHERE x.project_id = p.project_id);
  IF bad > 0 THEN RAISE EXCEPTION 'Quedan % proyectos sin inmuebles', bad; END IF;

  SELECT count(*) INTO bad FROM (SELECT property_code FROM properties GROUP BY property_code HAVING count(*) > 1) x;
  IF bad > 0 THEN RAISE EXCEPTION '% codigos de inmueble repetidos', bad; END IF;

  SELECT count(*) INTO bad FROM users u
  WHERE u.user_type IN ('provider', 'contractor') AND NOT EXISTS (SELECT 1 FROM bank_accounts b WHERE b.user_id = u.id);
  IF bad > 0 THEN RAISE EXCEPTION 'Quedan % proveedores o contratistas sin cuenta bancaria', bad; END IF;

  SELECT count(*) INTO bad FROM (SELECT account_number FROM bank_accounts GROUP BY account_number HAVING count(*) > 1) x;
  IF bad > 0 THEN RAISE EXCEPTION '% numeros de cuenta repetidos', bad; END IF;

  IF v_dry THEN
    RAISE EXCEPTION 'PRUEBA OK (se revirtio todo): items nuevos=%, aplicaciones=%, inmuebles=%, cuentas=%',
      n_items, n_apps, n_props, n_accts;
  END IF;
  RAISE NOTICE 'CARGA CONFIRMADA: items nuevos=%, aplicaciones=%, inmuebles=%, cuentas=%',
    n_items, n_apps, n_props, n_accts;
END $$;
