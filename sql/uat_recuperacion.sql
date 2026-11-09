-- ============================================================================
-- Pruebas de recuperacion REC-01 y REC-02 (ejecutadas el 09/11/2026 en el SQL Editor de Supabase)
-- No dejan cambios en la base: REC-01 termina en una excepcion que lo revierte todo y
-- REC-02 solo modifica filas dentro de una transaccion que nunca se confirma.
-- ============================================================================

-- ---------- REC-01: respaldo, perdida total y restauracion ----------
DO $$
DECLARE
  t text;
  n_orig bigint;
  n_perdida bigint;
  n_rest bigint;
  h_orig text;
  h_rest text;
  res text := '';
BEGIN
  FOREACH t IN ARRAY ARRAY['projects', 'project_activities', 'commitments', 'treasury_movements', 'sales'] LOOP
    -- 1) Respaldo: copia de la tabla real
    EXECUTE format('CREATE %s public.rec_resp_%s AS SELECT * FROM public.%s', 'TABLE', t, t);
    -- 2) Copia de trabajo que sufrira la falla
    EXECUTE format('CREATE %s public.rec_trab_%s AS SELECT * FROM public.rec_resp_%s', 'TABLE', t, t);
    -- 3) Falla: perdida total de los datos de la copia de trabajo
    EXECUTE format('DELETE FROM public.rec_trab_%s', t);
    EXECUTE format('SELECT count(*) FROM public.rec_trab_%s', t) INTO n_perdida;
    -- 4) Restauracion desde el respaldo
    EXECUTE format('INSERT INTO public.rec_trab_%s SELECT * FROM public.rec_resp_%s', t, t);
    -- 5) Comparacion con la tabla real
    EXECUTE format('SELECT count(*), md5(string_agg(x::text, '''' ORDER BY x::text)) FROM public.%s x', t) INTO n_orig, h_orig;
    EXECUTE format('SELECT count(*), md5(string_agg(x::text, '''' ORDER BY x::text)) FROM public.rec_trab_%s x', t) INTO n_rest, h_rest;
    res := res || E'\n' || t || ': real=' || n_orig || ', tras la perdida=' || n_perdida || ', restauradas=' || n_rest
           || ', checksum ' || CASE WHEN h_orig = h_rest THEN 'IGUAL' ELSE 'DISTINTO' END;
  END LOOP;
  RAISE EXCEPTION E'REC-01 (se revirtio todo):%', res;
END $$;

-- Verificacion: no quedaron tablas auxiliares y los conteos no cambiaron
SELECT
  (SELECT count(*) FROM pg_tables WHERE schemaname = 'public') AS tablas_public,
  (SELECT count(*) FROM pg_tables WHERE tablename LIKE 'rec\_%') AS tablas_auxiliares,
  (SELECT count(*) FROM projects) AS projects,
  (SELECT count(*) FROM project_activities) AS project_activities,
  (SELECT count(*) FROM commitments) AS commitments,
  (SELECT count(*) FROM treasury_movements) AS treasury_movements,
  (SELECT count(*) FROM sales) AS sales,
  (SELECT count(*) FROM banks) AS banks;

-- ---------- REC-02: caida de la conexion en medio de una transaccion ----------
-- Sesion A (pestana 1 del SQL Editor): transaccion con escrituras sin confirmar
BEGIN;
INSERT INTO banks (name) VALUES ('REC02-sin-confirmar');
UPDATE projects
SET progress = 77
WHERE project_id = (SELECT project_id FROM projects ORDER BY project_id LIMIT 1);
SELECT pg_sleep(150);
COMMIT;

-- Sesion B (pestana 2), mientras A sigue ejecutando: cortar de golpe la conexion de A
SELECT
  pid,
  state,
  xact_start IS NOT NULL AS transaccion_abierta,
  left(query, 45) AS consulta,
  pg_terminate_backend(pid) AS terminada
FROM pg_stat_activity
WHERE query LIKE '%REC02-sin-confirmar%'
  AND pid <> pg_backend_pid();

-- Verificacion tras el corte (esperado: 0, 15, 0, progress sin cambio, 0)
SELECT
  (SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%sesion A%' AND pid <> pg_backend_pid()) AS sesion_a_activa,
  (SELECT count(*) FROM banks) AS banks,
  (SELECT count(*) FROM banks WHERE name = 'REC02-sin-confirmar') AS fila_sin_confirmar,
  (SELECT progress FROM projects ORDER BY project_id LIMIT 1) AS progress_primer_proyecto,
  (SELECT updated_at::date FROM projects ORDER BY project_id LIMIT 1) AS updated_at_primer_proyecto,
  (SELECT count(*) FROM commitments WHERE net_payable <> gross_value + tax_amount - retention_amount - advance_amount) AS compromisos_inconsistentes;
