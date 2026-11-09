-- ============================================================================
-- Hub TuCasaConstrucciones - Esquema de la copia (Supabase, proyecto base_de_datos)
-- PostgreSQL 17.11. Reconstruido en SOLO LECTURA desde el catalogo del sistema
-- (pg_class, pg_attribute, pg_constraint, pg_proc, pg_trigger) el 2026-11-08.
-- Orden de creacion respetando las llaves foraneas. Esquema: public.
-- Nota: profiles.id referencia auth.users(id), que existe en Supabase (esquema auth).
-- ============================================================================

-- ---------- Catalogos ----------
CREATE TABLE public.banks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT banks_pkey PRIMARY KEY (id),
  CONSTRAINT banks_name_key UNIQUE (name)
);

CREATE TABLE public.payment_methods (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT payment_methods_pkey PRIMARY KEY (id),
  CONSTRAINT payment_methods_name_key UNIQUE (name)
);

CREATE TABLE public.chapters (
  chapter_id uuid NOT NULL DEFAULT gen_random_uuid(),
  chapter_code character varying,
  chapter_name character varying NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT chapters_pkey PRIMARY KEY (chapter_id),
  CONSTRAINT chapters_chapter_code_key UNIQUE (chapter_code),
  CONSTRAINT chapters_chapter_name_key UNIQUE (chapter_name)
);

CREATE TABLE public.units (
  unit_id uuid NOT NULL DEFAULT gen_random_uuid(),
  unit_code character varying NOT NULL,
  unit_name character varying NOT NULL,
  CONSTRAINT units_pkey PRIMARY KEY (unit_id),
  CONSTRAINT units_unit_code_key UNIQUE (unit_code)
);

CREATE TABLE public.retention_types (
  retention_type_id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL,
  description text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT retention_types_pkey PRIMARY KEY (retention_type_id),
  CONSTRAINT retention_types_name_key UNIQUE (name)
);

CREATE TABLE public.retention_type_rates (
  retention_type_rate_id uuid NOT NULL DEFAULT gen_random_uuid(),
  retention_type_id uuid NOT NULL,
  percentage numeric NOT NULL,
  effective_from date NOT NULL,
  effective_to date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT retention_type_rates_pkey PRIMARY KEY (retention_type_rate_id),
  CONSTRAINT retention_type_rates_retention_type_id_fkey FOREIGN KEY (retention_type_id) REFERENCES public.retention_types(retention_type_id),
  CONSTRAINT retention_type_rates_percentage_check CHECK (percentage >= 0 AND percentage <= 100)
);

CREATE TABLE public.labor_types (
  labor_type_id uuid NOT NULL DEFAULT gen_random_uuid(),
  code character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name character varying NOT NULL,
  CONSTRAINT labor_types_pkey PRIMARY KEY (labor_type_id),
  CONSTRAINT labor_types_code_key UNIQUE (code),
  CONSTRAINT labor_types_code_check CHECK (code::text ~ '^[a-z][a-z0-9_]*$')
);

-- ---------- Acceso y terceros ----------
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email character varying NOT NULL,
  full_name character varying,
  role character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_email_key UNIQUE (email),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id),
  CONSTRAINT profiles_role_check CHECK (role::text = ANY (ARRAY['superadmin','admin','accountant','foreman','assistant']))
);

CREATE TABLE public.users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_type character varying NOT NULL,
  document_type character varying NOT NULL,
  document_number character varying NOT NULL,
  name character varying NOT NULL,
  phone character varying,
  email character varying,
  tax_document_url text,
  id_document_url text,
  profile_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_profile_id_key UNIQUE (profile_id),
  CONSTRAINT users_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id),
  CONSTRAINT users_user_type_check CHECK (user_type::text = ANY (ARRAY['client','provider','contractor','employee'])),
  CONSTRAINT users_document_type_check CHECK (document_type::text = ANY (ARRAY['CC','NIT','CE','PASSPORT']))
);

CREATE TABLE public.bank_accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  bank_id uuid NOT NULL,
  account_type character varying NOT NULL,
  account_number character varying NOT NULL,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT bank_accounts_pkey PRIMARY KEY (id),
  CONSTRAINT bank_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT bank_accounts_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES public.banks(id),
  CONSTRAINT bank_accounts_account_type_check CHECK (account_type::text = ANY (ARRAY['savings','checking','digital_wallet']))
);

-- ---------- Proyectos ----------
CREATE TABLE public.projects (
  project_id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_name character varying NOT NULL,
  project_location text NOT NULL,
  status character varying NOT NULL DEFAULT 'active',
  start_date date,
  end_date date,
  progress integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT projects_pkey PRIMARY KEY (project_id),
  CONSTRAINT projects_project_name_key UNIQUE (project_name),
  CONSTRAINT projects_status_check CHECK (status::text = ANY (ARRAY['active','completed','on_hold'])),
  CONSTRAINT projects_progress_check CHECK (progress >= 0 AND progress <= 100)
);

CREATE TABLE public.blocks (
  block_id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  block_name character varying NOT NULL,
  block_kind character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT blocks_pkey PRIMARY KEY (block_id),
  CONSTRAINT blocks_project_id_block_id_key UNIQUE (project_id, block_id),
  CONSTRAINT blocks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT blocks_block_kind_check CHECK (block_kind::text = ANY (ARRAY['housing','common_areas']))
);

CREATE TABLE public.activity_catalog (
  activity_catalog_id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL,
  description text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  project_id uuid NOT NULL,
  CONSTRAINT activity_catalog_pkey PRIMARY KEY (activity_catalog_id),
  CONSTRAINT activity_catalog_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id)
);

CREATE TABLE public.properties (
  property_id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  block_id uuid NOT NULL,
  property_code character varying NOT NULL,
  property_type character varying NOT NULL,
  area_sqm numeric NOT NULL,
  total_price numeric NOT NULL,
  status character varying NOT NULL DEFAULT 'available',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT properties_pkey PRIMARY KEY (property_id),
  CONSTRAINT properties_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT properties_project_id_block_id_fkey FOREIGN KEY (project_id, block_id) REFERENCES public.blocks(project_id, block_id),
  CONSTRAINT properties_area_sqm_check CHECK (area_sqm > 0),
  CONSTRAINT properties_total_price_check CHECK (total_price >= 0),
  CONSTRAINT properties_status_check CHECK (status::text = ANY (ARRAY['available','reserved','sold']))
);

-- ---------- Obras y control ----------
CREATE TABLE public.project_activities (
  activity_id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  chapter_id uuid NOT NULL,
  block_id uuid NOT NULL,
  activity_catalog_id uuid NOT NULL,
  unit_id uuid NOT NULL,
  budgeted_quantity numeric NOT NULL,
  unit_price numeric NOT NULL,
  budgeted_cost numeric GENERATED ALWAYS AS (budgeted_quantity * unit_price) STORED,
  planned_start_date date,
  planned_end_date date,
  actual_start_date date,
  actual_end_date date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  property_label character varying,
  CONSTRAINT project_activities_pkey PRIMARY KEY (activity_id),
  CONSTRAINT project_activities_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT project_activities_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(chapter_id),
  CONSTRAINT project_activities_activity_catalog_id_fkey FOREIGN KEY (activity_catalog_id) REFERENCES public.activity_catalog(activity_catalog_id),
  CONSTRAINT project_activities_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(unit_id),
  CONSTRAINT project_activities_project_id_block_id_fkey FOREIGN KEY (project_id, block_id) REFERENCES public.blocks(project_id, block_id),
  CONSTRAINT project_activities_budgeted_quantity_check CHECK (budgeted_quantity > 0),
  CONSTRAINT project_activities_unit_price_check CHECK (unit_price >= 0)
);

CREATE TABLE public.work_progress (
  progress_id uuid NOT NULL DEFAULT gen_random_uuid(),
  activity_id uuid NOT NULL,
  record_date date NOT NULL,
  executed_quantity numeric NOT NULL,
  actual_unit_price numeric NOT NULL,
  actual_cost numeric GENERATED ALWAYS AS (executed_quantity * actual_unit_price) STORED,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT work_progress_pkey PRIMARY KEY (progress_id),
  CONSTRAINT work_progress_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.project_activities(activity_id),
  CONSTRAINT work_progress_executed_quantity_check CHECK (executed_quantity > 0),
  CONSTRAINT work_progress_actual_unit_price_check CHECK (actual_unit_price >= 0)
);

CREATE TABLE public.labor_performance (
  performance_id uuid NOT NULL DEFAULT gen_random_uuid(),
  activity_id uuid NOT NULL,
  record_date date NOT NULL,
  measurement_start_date date NOT NULL,
  measurement_end_date date NOT NULL,
  executed_quantity numeric NOT NULL,
  days_worked integer NOT NULL,
  crew_size integer NOT NULL DEFAULT 0,
  performance_rate numeric,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT labor_performance_pkey PRIMARY KEY (performance_id),
  CONSTRAINT labor_performance_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.project_activities(activity_id),
  CONSTRAINT labor_performance_executed_quantity_check CHECK (executed_quantity > 0),
  CONSTRAINT labor_performance_days_worked_check CHECK (days_worked > 0),
  CONSTRAINT labor_performance_crew_size_check CHECK (crew_size >= 0)
);

CREATE TABLE public.labor_performance_contractors (
  performance_id uuid NOT NULL,
  user_id uuid NOT NULL,
  CONSTRAINT labor_performance_contractors_pkey PRIMARY KEY (performance_id, user_id),
  CONSTRAINT labor_performance_contractors_performance_id_fkey FOREIGN KEY (performance_id) REFERENCES public.labor_performance(performance_id),
  CONSTRAINT labor_performance_contractors_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE public.labor_performance_crew (
  performance_id uuid NOT NULL,
  labor_type_id uuid NOT NULL,
  worker_count integer NOT NULL,
  CONSTRAINT labor_performance_crew_pkey PRIMARY KEY (performance_id, labor_type_id),
  CONSTRAINT labor_performance_crew_performance_id_fkey FOREIGN KEY (performance_id) REFERENCES public.labor_performance(performance_id),
  CONSTRAINT labor_performance_crew_labor_type_id_fkey FOREIGN KEY (labor_type_id) REFERENCES public.labor_types(labor_type_id),
  CONSTRAINT labor_performance_crew_worker_count_check CHECK (worker_count > 0)
);

-- ---------- Contratos y compromisos ----------
CREATE TABLE public.contracts (
  contract_id uuid NOT NULL DEFAULT gen_random_uuid(),
  contractor_id uuid NOT NULL,
  project_id uuid NOT NULL,
  chapter_id uuid,
  object_description text NOT NULL,
  estimated_total_value numeric NOT NULL,
  status character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT contracts_pkey PRIMARY KEY (contract_id),
  CONSTRAINT contracts_contractor_id_fkey FOREIGN KEY (contractor_id) REFERENCES public.users(id),
  CONSTRAINT contracts_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT contracts_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(chapter_id),
  CONSTRAINT contracts_estimated_total_value_check CHECK (estimated_total_value > 0),
  CONSTRAINT contracts_status_check CHECK (status::text = ANY (ARRAY['active','suspended','pending_closure','closed']))
);

CREATE TABLE public.contract_advances (
  advance_id uuid NOT NULL DEFAULT gen_random_uuid(),
  contract_id uuid NOT NULL,
  execution_value numeric NOT NULL,
  advance_date date NOT NULL,
  supporting_doc_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT contract_advances_pkey PRIMARY KEY (advance_id),
  CONSTRAINT contract_advances_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(contract_id),
  CONSTRAINT contract_advances_execution_value_check CHECK (execution_value >= 0)
);

CREATE TABLE public.commitments (
  commitment_id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_id uuid,
  user_id uuid NOT NULL,
  contract_id uuid,
  commitment_type character varying NOT NULL,
  invoice_format character varying,
  invoice_number character varying,
  commitment_date date NOT NULL,
  gross_value numeric NOT NULL,
  tax_amount numeric NOT NULL DEFAULT 0.00,
  retention_amount numeric NOT NULL DEFAULT 0.00,
  retention_type_rate_id uuid,
  advance_amount numeric NOT NULL DEFAULT 0,
  invoice_total numeric GENERATED ALWAYS AS (gross_value + tax_amount) STORED,
  net_payable numeric GENERATED ALWAYS AS (((gross_value + tax_amount) - retention_amount) - advance_amount) STORED,
  accounting_number character varying,
  supporting_doc_url text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid NOT NULL DEFAULT auth.uid(),
  CONSTRAINT commitments_pkey PRIMARY KEY (commitment_id),
  CONSTRAINT commitments_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT commitments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT commitments_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(contract_id),
  CONSTRAINT commitments_retention_type_rate_id_fkey FOREIGN KEY (retention_type_rate_id) REFERENCES public.retention_type_rates(retention_type_rate_id),
  CONSTRAINT commitments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT commitments_commitment_type_check CHECK (commitment_type::text = ANY (ARRAY['invoice','collection_account','contract_settlement'])),
  CONSTRAINT commitments_invoice_format_check CHECK (invoice_format::text = ANY (ARRAY['physical','electronic'])),
  CONSTRAINT commitments_gross_value_check CHECK (gross_value >= 0),
  CONSTRAINT commitments_tax_amount_check CHECK (tax_amount >= 0),
  CONSTRAINT commitments_retention_amount_check CHECK (retention_amount >= 0),
  CONSTRAINT commitments_advance_amount_check CHECK (advance_amount >= 0)
);

CREATE TABLE public.commitment_details (
  detail_id uuid NOT NULL DEFAULT gen_random_uuid(),
  commitment_id uuid NOT NULL,
  activity_id uuid,
  chapter_id uuid,
  description text NOT NULL,
  quantity numeric NOT NULL,
  unit_price numeric NOT NULL,
  total_price numeric GENERATED ALWAYS AS (quantity * unit_price) STORED,
  retention_type_rate_id uuid,
  CONSTRAINT commitment_details_pkey PRIMARY KEY (detail_id),
  CONSTRAINT commitment_details_commitment_id_fkey FOREIGN KEY (commitment_id) REFERENCES public.commitments(commitment_id),
  CONSTRAINT commitment_details_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.project_activities(activity_id),
  CONSTRAINT commitment_details_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(chapter_id),
  CONSTRAINT commitment_details_retention_type_rate_id_fkey FOREIGN KEY (retention_type_rate_id) REFERENCES public.retention_type_rates(retention_type_rate_id),
  CONSTRAINT commitment_details_quantity_check CHECK (quantity > 0),
  CONSTRAINT commitment_details_unit_price_check CHECK (unit_price >= 0)
);

-- ---------- Ventas ----------
CREATE TABLE public.sales (
  sale_id uuid NOT NULL DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  property_id uuid NOT NULL,
  sale_date date NOT NULL,
  separation_amount numeric NOT NULL DEFAULT 0.00,
  total_sale_value numeric NOT NULL,
  down_payment_total numeric NOT NULL,
  credit_amount numeric GENERATED ALWAYS AS (total_sale_value - down_payment_total) STORED,
  sale_status character varying NOT NULL,
  sale_folder_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid NOT NULL DEFAULT auth.uid(),
  CONSTRAINT sales_pkey PRIMARY KEY (sale_id),
  CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.users(id),
  CONSTRAINT sales_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(property_id),
  CONSTRAINT sales_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT sales_sale_status_check CHECK (sale_status::text = ANY (ARRAY['active','completed','canceled'])),
  CONSTRAINT sales_separation_amount_check CHECK (separation_amount >= 0),
  CONSTRAINT sales_total_sale_value_check CHECK (total_sale_value > 0)
);

CREATE TABLE public.payment_plans (
  plan_id uuid NOT NULL DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL,
  installment_number integer NOT NULL,
  due_date date NOT NULL,
  expected_amount numeric NOT NULL,
  installment_type character varying NOT NULL DEFAULT 'down_payment_installment',
  CONSTRAINT payment_plans_pkey PRIMARY KEY (plan_id),
  CONSTRAINT payment_plans_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(sale_id),
  CONSTRAINT payment_plans_installment_number_check CHECK (installment_number > 0),
  CONSTRAINT payment_plans_expected_amount_check CHECK (expected_amount > 0),
  CONSTRAINT payment_plans_installment_type_check CHECK (installment_type::text = ANY (ARRAY['down_payment_installment','mortgage_credit','subsidy','extra']))
);

-- ---------- Tesoreria ----------
CREATE TABLE public.company_accounts (
  account_id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_name character varying NOT NULL,
  account_kind character varying NOT NULL,
  bank_id uuid,
  account_type character varying,
  account_number character varying,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT company_accounts_pkey PRIMARY KEY (account_id),
  CONSTRAINT company_accounts_account_name_key UNIQUE (account_name),
  CONSTRAINT company_accounts_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES public.banks(id),
  CONSTRAINT company_accounts_account_kind_check CHECK (account_kind::text = ANY (ARRAY['bank','petty_cash','cash','investment'])),
  CONSTRAINT company_accounts_account_type_check CHECK (account_type::text = ANY (ARRAY['savings','checking','digital_wallet']))
);

CREATE TABLE public.treasury_movements (
  movement_id uuid NOT NULL DEFAULT gen_random_uuid(),
  movement_type character varying NOT NULL,
  sub_type character varying NOT NULL,
  movement_date date NOT NULL,
  amount numeric NOT NULL,
  project_id uuid,
  user_id uuid,
  commitment_id uuid,
  sale_id uuid,
  contract_id uuid,
  payment_method_id uuid,
  source_account_id uuid,
  dest_account_id uuid,
  dest_bank_account_id uuid,
  supporting_doc_url text,
  notes text,
  created_by uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT treasury_movements_pkey PRIMARY KEY (movement_id),
  CONSTRAINT treasury_movements_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT treasury_movements_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT treasury_movements_commitment_id_fkey FOREIGN KEY (commitment_id) REFERENCES public.commitments(commitment_id),
  CONSTRAINT treasury_movements_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(sale_id),
  CONSTRAINT treasury_movements_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(contract_id),
  CONSTRAINT treasury_movements_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(id),
  CONSTRAINT treasury_movements_source_account_id_fkey FOREIGN KEY (source_account_id) REFERENCES public.company_accounts(account_id),
  CONSTRAINT treasury_movements_dest_account_id_fkey FOREIGN KEY (dest_account_id) REFERENCES public.company_accounts(account_id),
  CONSTRAINT treasury_movements_dest_bank_account_id_fkey FOREIGN KEY (dest_bank_account_id) REFERENCES public.bank_accounts(id),
  CONSTRAINT treasury_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT treasury_movements_amount_check CHECK (amount > 0),
  CONSTRAINT treasury_movements_movement_type_check CHECK (movement_type::text = ANY (ARRAY['income','expense','transfer','investment'])),
  CONSTRAINT treasury_movements_sub_type_check CHECK (sub_type::text = ANY (ARRAY['sale_payment','sale_refund','contract_advance','commitment_payment','petty_cash_funding','petty_cash_expense','internal_transfer','cdt','loan']))
);

CREATE TABLE public.commitment_applications (
  application_id uuid NOT NULL DEFAULT gen_random_uuid(),
  movement_id uuid NOT NULL,
  commitment_id uuid NOT NULL,
  applied_amount numeric NOT NULL,
  CONSTRAINT commitment_applications_pkey PRIMARY KEY (application_id),
  CONSTRAINT commitment_applications_movement_id_fkey FOREIGN KEY (movement_id) REFERENCES public.treasury_movements(movement_id),
  CONSTRAINT commitment_applications_commitment_id_fkey FOREIGN KEY (commitment_id) REFERENCES public.commitments(commitment_id),
  CONSTRAINT commitment_applications_applied_amount_check CHECK (applied_amount > 0)
);

CREATE TABLE public.payment_applications (
  application_id uuid NOT NULL DEFAULT gen_random_uuid(),
  movement_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  applied_amount numeric NOT NULL,
  CONSTRAINT payment_applications_pkey PRIMARY KEY (application_id),
  CONSTRAINT payment_applications_movement_id_fkey FOREIGN KEY (movement_id) REFERENCES public.treasury_movements(movement_id),
  CONSTRAINT payment_applications_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.payment_plans(plan_id),
  CONSTRAINT payment_applications_applied_amount_check CHECK (applied_amount > 0)
);

-- ============================================================================
-- Funciones y triggers (5 + 5) tal como existen en la copia
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE OR REPLACE FUNCTION public.fn_property_block_must_be_housing() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_block_kind VARCHAR(20);
BEGIN
  SELECT block_kind INTO v_block_kind FROM blocks WHERE block_id = NEW.block_id AND project_id = NEW.project_id;
  IF v_block_kind IS DISTINCT FROM 'housing' THEN
    RAISE EXCEPTION 'Property % can only be assigned to a block of type housing (block received: %)', NEW.property_id, v_block_kind;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.fn_contract_contractor_must_be_contractor() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_user_type VARCHAR(20);
BEGIN
  SELECT user_type INTO v_user_type FROM users WHERE id = NEW.contractor_id;
  IF v_user_type IS DISTINCT FROM 'contractor' THEN
    RAISE EXCEPTION 'contractor_id % must have user_type = contractor (has: %)', NEW.contractor_id, v_user_type;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.fn_sync_property_status_with_sale() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  IF NEW.sale_status IN ('active','completed') THEN
    UPDATE properties SET status = 'sold' WHERE property_id = NEW.property_id;
  ELSIF NEW.sale_status = 'canceled' THEN
    UPDATE properties SET status = 'available' WHERE property_id = NEW.property_id;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.fn_apply_sale_payment_fifo() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_remaining DECIMAL(15,2); v_plan RECORD; v_already_applied DECIMAL(15,2); v_to_apply DECIMAL(15,2);
BEGIN
  IF NEW.movement_type <> 'income' OR NEW.sub_type <> 'sale_payment' OR NEW.sale_id IS NULL THEN
    RETURN NEW;
  END IF;
  v_remaining := NEW.amount;
  FOR v_plan IN SELECT plan_id, expected_amount FROM payment_plans
                WHERE sale_id = NEW.sale_id ORDER BY installment_number FOR UPDATE
  LOOP
    EXIT WHEN v_remaining <= 0;
    SELECT COALESCE(SUM(applied_amount), 0) INTO v_already_applied
      FROM payment_applications WHERE plan_id = v_plan.plan_id;
    IF v_already_applied >= v_plan.expected_amount THEN CONTINUE; END IF;
    v_to_apply := LEAST(v_remaining, v_plan.expected_amount - v_already_applied);
    INSERT INTO payment_applications (movement_id, plan_id, applied_amount)
      VALUES (NEW.movement_id, v_plan.plan_id, v_to_apply);
    v_remaining := v_remaining - v_to_apply;
  END LOOP;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_projects_set_updated_at BEFORE UPDATE ON public.projects
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_property_block_must_be_housing BEFORE INSERT OR UPDATE OF block_id, project_id ON public.properties
  FOR EACH ROW EXECUTE FUNCTION fn_property_block_must_be_housing();
CREATE TRIGGER trg_contract_contractor_must_be_contractor BEFORE INSERT OR UPDATE OF contractor_id ON public.contracts
  FOR EACH ROW EXECUTE FUNCTION fn_contract_contractor_must_be_contractor();
CREATE TRIGGER trg_sync_property_status_with_sale AFTER INSERT OR UPDATE OF sale_status ON public.sales
  FOR EACH ROW EXECUTE FUNCTION fn_sync_property_status_with_sale();
CREATE TRIGGER trg_apply_sale_payment_fifo AFTER INSERT ON public.treasury_movements
  FOR EACH ROW EXECUTE FUNCTION fn_apply_sale_payment_fifo();
