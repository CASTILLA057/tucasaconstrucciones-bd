# TuCasaConstrucciones — Entrega de Bases de Datos Relacionales (2.º parcial)

Entrega del curso **Bases de datos relacionales** (docente: Byron Cuesta Quintero) sobre el modelo de datos del Hub TuCasaConstrucciones, un ERP para constructoras (tesorería, compromisos, contratos, ventas, obras y control, proyectos, terceros y catálogos).

> Esta entrega es independiente del repositorio de la aplicación web. Aquí solo está la base de datos, su documentación, los datos de prueba. Las capturas de pantalla (Supabase y pgAdmin 4) están dentro del documento de `docs/`.

## Base de datos desplegada

- Motor: PostgreSQL 17 en Supabase (proyecto `base_de_datos`, región us-east-1).
- Contenido: 29 tablas en el esquema `public`, 5 funciones y 5 triggers. No tiene vistas ni políticas RLS (se explica en el documento, sección 4.4 y recomendaciones).
- Datos sintéticos generados con IA y validados (Anexo 1 del documento). Cantidades pedidas por el profesor:

| Tabla | Filas |
|---|---|
| `projects` | 500 |
| `project_activities` | 1000 |
| `commitments` | 500 |
| `treasury_movements` | 500 |
| `sales` | 200 |

## Contenido del repositorio

```
docs/         Documento de la entrega (.docx y .pdf, versión 1.2)
sql/          Scripts SQL (esquema, datos, carga complementaria, UAT, práctica)
data/         Excel de la carga complementaria y los CSV de las filas agregadas
```

| Archivo | Para qué sirve |
|---|---|
| `docs/Entregable-TuCasaConstrucciones-v1.2.pdf` | Documento completo (requisitos, modelo, diccionario, DDL/DML, UAT, despliegue, Anexo 1) |
| `sql/esquema_copia.sql` | DDL: 29 tablas, 5 funciones y 5 triggers |
| `sql/backup_completo.sql` | Backup completo en un solo archivo: esquema y datos (para restaurar en una base vacía) |
| `sql/datos_completos.sql` | DML: respaldo de datos de las 29 tablas (7.053 `INSERT`) |
| `sql/completar_datos.sql` | Carga complementaria del 09/11/2026 (ítems, aplicaciones de pago, inmuebles y cuentas bancarias) |
| `sql/uat_copia.sql` | Plan de pruebas UAT ejecutable |
| `sql/uat_recuperacion.sql` | Pruebas de recuperación en Supabase: REC-01 (respaldo y restauración) y REC-02 (caída de la conexión en una transacción) |
| `sql/ejercicios_multitabla.sql` | Ejercicios de `JOIN` y agregados |
| `data/datos_complementarios_2026-11-09.xlsx` | Excel con las 4 hojas de la carga complementaria |
| `data/*.csv` | Las mismas filas en CSV |

## Cómo recrear la base

1. Crear un proyecto de Supabase vacío (PostgreSQL 17). `profiles.id` referencia `auth.users(id)` y la columna `created_by` usa `auth.uid()`, que ya existen en Supabase.
2. Ejecutar `sql/esquema_copia.sql`.
3. Ejecutar `sql/datos_completos.sql`. El script activa `session_replication_role = replica` para que el trigger `trg_apply_sale_payment_fifo` no duplique `payment_applications` ni se validen las llaves foráneas durante la carga, y lo restablece al final.
4. Verificar los conteos:

```sql
SELECT relname AS tabla, n_live_tup AS filas
FROM pg_stat_user_tables
ORDER BY relname;
```

`sql/completar_datos.sql` no hace falta si se usa `datos_completos.sql`: ese respaldo ya incluye sus resultados. Se entrega como evidencia del proceso (`v_dry = true` prueba y revierte; `v_dry = false` confirma).

## Cómo correr el UAT

Ejecutar `sql/uat_copia.sql` en el SQL Editor o en pgAdmin 4. La parte A escribe datos de prueba y termina en una excepción a propósito para revertirlo todo; la parte B es de solo lectura. Los resultados esperados están en la sección 5 del documento.

## Verificación del respaldo

`sql/datos_completos.sql` es el respaldo (`pg_dump` desde pgAdmin 4) de la base desplegada: 7.053 sentencias `INSERT` y los mismos conteos por tabla que la base de Supabase. La restauración desde un respaldo se probó en la propia base de Supabase con `sql/uat_recuperacion.sql` (sección 5 del documento).
