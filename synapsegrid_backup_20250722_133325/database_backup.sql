--
-- PostgreSQL database dump
--

-- Dumped from database version 15.13
-- Dumped by pg_dump version 15.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: get_node_load(character varying); Type: FUNCTION; Schema: public; Owner: synapse
--

CREATE FUNCTION public.get_node_load(node_id_param character varying) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
DECLARE
    active_jobs_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO active_jobs_count
    FROM jobs
    WHERE node_id = node_id_param
    AND status IN ('running', 'assigned');
    
    RETURN active_jobs_count::FLOAT / 10.0; -- Normalize to 0-1 scale
END;
$$;


ALTER FUNCTION public.get_node_load(node_id_param character varying) OWNER TO synapse;

--
-- Name: update_node_heartbeat(character varying); Type: FUNCTION; Schema: public; Owner: synapse
--

CREATE FUNCTION public.update_node_heartbeat(node_id_param character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE nodes 
    SET last_heartbeat = NOW(), status = 'active'
    WHERE id = node_id_param;
END;
$$;


ALTER FUNCTION public.update_node_heartbeat(node_id_param character varying) OWNER TO synapse;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: nodes; Type: TABLE; Schema: public; Owner: synapse
--

CREATE TABLE public.nodes (
    id character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    region character varying(50),
    status character varying(20) DEFAULT 'offline'::character varying,
    gpu_model character varying(100),
    cpu_cores integer,
    memory_gb integer,
    capabilities jsonb,
    metadata jsonb,
    registered_at timestamp without time zone DEFAULT now(),
    last_heartbeat timestamp without time zone DEFAULT now(),
    total_jobs_completed integer DEFAULT 0,
    total_compute_time_seconds bigint DEFAULT 0
);


ALTER TABLE public.nodes OWNER TO synapse;

--
-- Name: active_nodes; Type: VIEW; Schema: public; Owner: synapse
--

CREATE VIEW public.active_nodes AS
 SELECT nodes.id,
    nodes.name,
    nodes.region,
    nodes.status,
    nodes.gpu_model,
    nodes.cpu_cores,
    nodes.memory_gb,
    nodes.capabilities,
    nodes.metadata,
    nodes.registered_at,
    nodes.last_heartbeat,
    nodes.total_jobs_completed,
    nodes.total_compute_time_seconds
   FROM public.nodes
  WHERE (((nodes.status)::text = 'active'::text) AND (nodes.last_heartbeat > (now() - '00:01:00'::interval)));


ALTER TABLE public.active_nodes OWNER TO synapse;

--
-- Name: clients; Type: TABLE; Schema: public; Owner: synapse
--

CREATE TABLE public.clients (
    id character varying(50) NOT NULL,
    name character varying(100),
    api_key character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.clients OWNER TO synapse;

--
-- Name: job_results; Type: TABLE; Schema: public; Owner: synapse
--

CREATE TABLE public.job_results (
    id integer NOT NULL,
    job_id character varying(50) NOT NULL,
    result_type character varying(50),
    result_data jsonb,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.job_results OWNER TO synapse;

--
-- Name: job_results_id_seq; Type: SEQUENCE; Schema: public; Owner: synapse
--

CREATE SEQUENCE public.job_results_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.job_results_id_seq OWNER TO synapse;

--
-- Name: job_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synapse
--

ALTER SEQUENCE public.job_results_id_seq OWNED BY public.job_results.id;


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: synapse
--

CREATE TABLE public.jobs (
    id character varying(50) NOT NULL,
    model_name character varying(100) NOT NULL,
    client_id character varying(100),
    node_id character varying(50),
    status character varying(20) DEFAULT 'pending'::character varying,
    priority integer DEFAULT 1,
    submitted_at timestamp without time zone DEFAULT now(),
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    input_data jsonb,
    output_data jsonb,
    error_message text,
    compute_time_ms integer,
    tokens_processed integer,
    cost_nrg numeric(20,8),
    job_id character varying(64) NOT NULL
);


ALTER TABLE public.jobs OWNER TO synapse;

--
-- Name: job_statistics; Type: VIEW; Schema: public; Owner: synapse
--

CREATE VIEW public.job_statistics AS
 SELECT date_trunc('hour'::text, jobs.submitted_at) AS hour,
    count(*) AS total_jobs,
    count(
        CASE
            WHEN ((jobs.status)::text = 'completed'::text) THEN 1
            ELSE NULL::integer
        END) AS completed_jobs,
    count(
        CASE
            WHEN ((jobs.status)::text = 'failed'::text) THEN 1
            ELSE NULL::integer
        END) AS failed_jobs,
    avg(
        CASE
            WHEN (jobs.compute_time_ms IS NOT NULL) THEN jobs.compute_time_ms
            ELSE NULL::integer
        END) AS avg_compute_time_ms
   FROM public.jobs
  GROUP BY (date_trunc('hour'::text, jobs.submitted_at));


ALTER TABLE public.job_statistics OWNER TO synapse;

--
-- Name: metrics; Type: TABLE; Schema: public; Owner: synapse
--

CREATE TABLE public.metrics (
    id integer NOT NULL,
    metric_name character varying(100) NOT NULL,
    metric_value double precision NOT NULL,
    tags jsonb,
    "timestamp" timestamp without time zone DEFAULT now()
);


ALTER TABLE public.metrics OWNER TO synapse;

--
-- Name: metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: synapse
--

CREATE SEQUENCE public.metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.metrics_id_seq OWNER TO synapse;

--
-- Name: metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synapse
--

ALTER SEQUENCE public.metrics_id_seq OWNED BY public.metrics.id;


--
-- Name: node_capabilities; Type: TABLE; Schema: public; Owner: synapse
--

CREATE TABLE public.node_capabilities (
    id integer NOT NULL,
    node_id character varying(50) NOT NULL,
    capability character varying(50) NOT NULL,
    version character varying(20),
    performance_score double precision
);


ALTER TABLE public.node_capabilities OWNER TO synapse;

--
-- Name: node_capabilities_id_seq; Type: SEQUENCE; Schema: public; Owner: synapse
--

CREATE SEQUENCE public.node_capabilities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.node_capabilities_id_seq OWNER TO synapse;

--
-- Name: node_capabilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synapse
--

ALTER SEQUENCE public.node_capabilities_id_seq OWNED BY public.node_capabilities.id;


--
-- Name: pending_jobs; Type: VIEW; Schema: public; Owner: synapse
--

CREATE VIEW public.pending_jobs AS
 SELECT jobs.id,
    jobs.model_name,
    jobs.client_id,
    jobs.node_id,
    jobs.status,
    jobs.priority,
    jobs.submitted_at,
    jobs.started_at,
    jobs.completed_at,
    jobs.input_data,
    jobs.output_data,
    jobs.error_message,
    jobs.compute_time_ms,
    jobs.tokens_processed,
    jobs.cost_nrg
   FROM public.jobs
  WHERE ((jobs.status)::text = ANY ((ARRAY['pending'::character varying, 'assigned'::character varying])::text[]))
  ORDER BY jobs.priority DESC, jobs.submitted_at;


ALTER TABLE public.pending_jobs OWNER TO synapse;

--
-- Name: job_results id; Type: DEFAULT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.job_results ALTER COLUMN id SET DEFAULT nextval('public.job_results_id_seq'::regclass);


--
-- Name: metrics id; Type: DEFAULT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_id_seq'::regclass);


--
-- Name: node_capabilities id; Type: DEFAULT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.node_capabilities ALTER COLUMN id SET DEFAULT nextval('public.node_capabilities_id_seq'::regclass);


--
-- Data for Name: clients; Type: TABLE DATA; Schema: public; Owner: synapse
--

COPY public.clients (id, name, api_key, created_at, updated_at) FROM stdin;
test-client	Test Client	test-token	2025-07-22 09:08:35.853298	2025-07-22 09:08:35.853298
dashboard	Dashboard Client	dashboard-token	2025-07-22 09:08:35.853298	2025-07-22 09:08:35.853298
\.


--
-- Data for Name: job_results; Type: TABLE DATA; Schema: public; Owner: synapse
--

COPY public.job_results (id, job_id, result_type, result_data, created_at) FROM stdin;
\.


--
-- Data for Name: jobs; Type: TABLE DATA; Schema: public; Owner: synapse
--

COPY public.jobs (id, model_name, client_id, node_id, status, priority, submitted_at, started_at, completed_at, input_data, output_data, error_message, compute_time_ms, tokens_processed, cost_nrg, job_id) FROM stdin;
\.


--
-- Data for Name: metrics; Type: TABLE DATA; Schema: public; Owner: synapse
--

COPY public.metrics (id, metric_name, metric_value, tags, "timestamp") FROM stdin;
\.


--
-- Data for Name: node_capabilities; Type: TABLE DATA; Schema: public; Owner: synapse
--

COPY public.node_capabilities (id, node_id, capability, version, performance_score) FROM stdin;
\.


--
-- Data for Name: nodes; Type: TABLE DATA; Schema: public; Owner: synapse
--

COPY public.nodes (id, name, region, status, gpu_model, cpu_cores, memory_gb, capabilities, metadata, registered_at, last_heartbeat, total_jobs_completed, total_compute_time_seconds) FROM stdin;
\.


--
-- Name: job_results_id_seq; Type: SEQUENCE SET; Schema: public; Owner: synapse
--

SELECT pg_catalog.setval('public.job_results_id_seq', 1, false);


--
-- Name: metrics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: synapse
--

SELECT pg_catalog.setval('public.metrics_id_seq', 1, false);


--
-- Name: node_capabilities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: synapse
--

SELECT pg_catalog.setval('public.node_capabilities_id_seq', 1, false);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: job_results job_results_pkey; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.job_results
    ADD CONSTRAINT job_results_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_job_id_key; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_job_id_key UNIQUE (job_id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: node_capabilities node_capabilities_node_id_capability_key; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.node_capabilities
    ADD CONSTRAINT node_capabilities_node_id_capability_key UNIQUE (node_id, capability);


--
-- Name: node_capabilities node_capabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.node_capabilities
    ADD CONSTRAINT node_capabilities_pkey PRIMARY KEY (id);


--
-- Name: nodes nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT nodes_pkey PRIMARY KEY (id);


--
-- Name: idx_jobs_client_id; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_jobs_client_id ON public.jobs USING btree (client_id);


--
-- Name: idx_jobs_node_id; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_jobs_node_id ON public.jobs USING btree (node_id);


--
-- Name: idx_jobs_status; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_jobs_status ON public.jobs USING btree (status);


--
-- Name: idx_jobs_status_priority; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_jobs_status_priority ON public.jobs USING btree (status, priority DESC);


--
-- Name: idx_jobs_submitted_at; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_jobs_submitted_at ON public.jobs USING btree (submitted_at);


--
-- Name: idx_metrics_name_timestamp; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_metrics_name_timestamp ON public.metrics USING btree (metric_name, "timestamp" DESC);


--
-- Name: idx_metrics_timestamp; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_metrics_timestamp ON public.metrics USING btree ("timestamp" DESC);


--
-- Name: idx_nodes_last_heartbeat; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_nodes_last_heartbeat ON public.nodes USING btree (last_heartbeat);


--
-- Name: idx_nodes_region; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_nodes_region ON public.nodes USING btree (region);


--
-- Name: idx_nodes_status; Type: INDEX; Schema: public; Owner: synapse
--

CREATE INDEX idx_nodes_status ON public.nodes USING btree (status);


--
-- Name: job_results job_results_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.job_results
    ADD CONSTRAINT job_results_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.jobs(id) ON DELETE CASCADE;


--
-- Name: jobs jobs_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_node_id_fkey FOREIGN KEY (node_id) REFERENCES public.nodes(id) ON DELETE SET NULL;


--
-- Name: node_capabilities node_capabilities_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synapse
--

ALTER TABLE ONLY public.node_capabilities
    ADD CONSTRAINT node_capabilities_node_id_fkey FOREIGN KEY (node_id) REFERENCES public.nodes(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

