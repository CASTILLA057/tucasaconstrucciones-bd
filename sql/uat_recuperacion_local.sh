#!/usr/bin/env bash
# Pruebas de recuperacion REC-01 y REC-02 (secciones 5 y Tabla de Pruebas de Recuperacion del documento).
# Se ejecutan en un PostgreSQL 17 LOCAL (Docker), no en Supabase, para no alterar la base evaluada.
# Requisitos: Docker. Ejecutar desde la carpeta sql/ (donde estan esquema_copia.sql y datos_completos.sql).
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: evita convertir las rutas /tmp
P="docker exec pgtest psql -U postgres"

docker rm -f pgtest >/dev/null 2>&1 || true
docker run -d --name pgtest -e POSTGRES_PASSWORD=localtest -p 55432:5432 postgres:17 >/dev/null
until docker exec pgtest pg_isready -U postgres >/dev/null 2>&1; do sleep 2; done

# Esquema auth minimo (en Supabase ya existe) y carga del esquema y los datos
cat > .prelude_tmp.sql <<'SQL'
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULL::uuid $$;
SQL
docker cp .prelude_tmp.sql pgtest:/tmp/prelude.sql; rm -f .prelude_tmp.sql
docker cp esquema_copia.sql pgtest:/tmp/esquema.sql
docker cp datos_completos.sql pgtest:/tmp/datos.sql
$P -q -c "CREATE DATABASE hub"
for f in prelude esquema datos; do $P -d hub -v ON_ERROR_STOP=1 -q -f /tmp/$f.sql >/dev/null; done
$P -d hub -tA -c "INSERT INTO auth.users SELECT id FROM public.profiles"   # los usuarios de autenticacion que en Supabase ya existen

snap() { docker exec pgtest psql -U postgres -d hub -tA \
  -c "SELECT c.relname||' '||(xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' ORDER BY 1" \
  -c "SELECT 'md5_sales '||md5(string_agg(s::text, '' ORDER BY s.sale_id)) FROM sales s"; }
snap > ./.antes.tmp

echo "== REC-01: respaldo, falla total y restauracion"
docker exec pgtest pg_dump -U postgres -Fc -d hub -f /tmp/hub.dump
$P -c "DROP DATABASE hub"; $P -q -c "CREATE DATABASE hub"
docker exec pgtest pg_restore -U postgres -d hub --no-owner /tmp/hub.dump
snap > ./.despues.tmp
diff ./.antes.tmp ./.despues.tmp && echo "REC-01 APROBADO: 29 tablas y checksum identicos"

echo "== REC-02: caida del servidor con una transaccion sin confirmar"
P="docker exec pgtest psql -U postgres -d hub -tA"
$P -c "INSERT INTO banks(name) VALUES ('REC02-confirmada')"
docker exec -d pgtest bash -c "psql -U postgres -d hub -c \"BEGIN; INSERT INTO banks(name) VALUES ('REC02-sin-confirmar-1'),('REC02-sin-confirmar-2'); UPDATE projects SET progress = 77; SELECT pg_sleep(120); COMMIT;\""
sleep 4
docker kill -s KILL pgtest >/dev/null     # SIGKILL: caida del servidor
docker start pgtest >/dev/null
until docker exec pgtest pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
docker logs pgtest 2>&1 | grep -E "not properly shut down|automatic recovery in progress" | tail -1
$P -c "select 'confirmada='||count(*) from banks where name='REC02-confirmada'" \
   -c "select 'sin confirmar='||count(*) from banks where name like 'REC02-sin%'" \
   -c "select 'inconsistencias neto='||count(*) from commitments where net_payable <> gross_value+tax_amount-retention_amount-advance_amount"

rm -f ./.antes.tmp ./.despues.tmp
