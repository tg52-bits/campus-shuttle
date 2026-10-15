--
-- PostgreSQL database dump
--

\restrict qaGvsp2uwoqOL7bthxFHTb7HO2KjzeMEKVzh2xKyugebdNXge0mmLwFQ8HsbanD

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: delays; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delays (
    delay_id bigint NOT NULL,
    trip_id integer NOT NULL,
    stop_id integer,
    delay_duration integer NOT NULL,
    delay_type character varying(50),
    "timestamp" timestamp without time zone NOT NULL,
    CONSTRAINT delays_delay_duration_check CHECK ((delay_duration >= 0))
);


ALTER TABLE public.delays OWNER TO postgres;

--
-- Name: delays_delay_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delays_delay_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delays_delay_id_seq OWNER TO postgres;

--
-- Name: delays_delay_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delays_delay_id_seq OWNED BY public.delays.delay_id;


--
-- Name: drivers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.drivers (
    driver_id integer NOT NULL,
    name character varying(100) NOT NULL,
    license_info character varying(100)
);


ALTER TABLE public.drivers OWNER TO postgres;

--
-- Name: drivers_driver_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.drivers_driver_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.drivers_driver_id_seq OWNER TO postgres;

--
-- Name: drivers_driver_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.drivers_driver_id_seq OWNED BY public.drivers.driver_id;


--
-- Name: route_stops; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.route_stops (
    route_stop_id integer NOT NULL,
    route_id integer NOT NULL,
    stop_id integer NOT NULL,
    stop_sequence integer NOT NULL,
    CONSTRAINT route_stops_stop_sequence_check CHECK ((stop_sequence > 0))
);


ALTER TABLE public.route_stops OWNER TO postgres;

--
-- Name: route_stops_route_stop_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.route_stops_route_stop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.route_stops_route_stop_id_seq OWNER TO postgres;

--
-- Name: route_stops_route_stop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.route_stops_route_stop_id_seq OWNED BY public.route_stops.route_stop_id;


--
-- Name: routes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.routes (
    route_id integer NOT NULL,
    route_name character varying(100) NOT NULL,
    route_geometry public.geometry(LineString,4326)
);


ALTER TABLE public.routes OWNER TO postgres;

--
-- Name: routes_route_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.routes_route_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.routes_route_id_seq OWNER TO postgres;

--
-- Name: routes_route_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.routes_route_id_seq OWNED BY public.routes.route_id;


--
-- Name: stops; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stops (
    stop_id integer NOT NULL,
    stop_name character varying(100) NOT NULL,
    location public.geometry(Point,4326) NOT NULL
);


ALTER TABLE public.stops OWNER TO postgres;

--
-- Name: stops_stop_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stops_stop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stops_stop_id_seq OWNER TO postgres;

--
-- Name: stops_stop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stops_stop_id_seq OWNED BY public.stops.stop_id;


--
-- Name: trip_stop_event; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trip_stop_event (
    trip_stop_id integer NOT NULL,
    trip_id integer NOT NULL,
    stop_id integer NOT NULL,
    stop_sequence integer NOT NULL,
    scheduled_arrival timestamp without time zone,
    actual_arrival timestamp without time zone,
    scheduled_departure timestamp without time zone,
    actual_departure timestamp without time zone,
    CONSTRAINT trip_stop_event_check CHECK (((actual_departure IS NULL) OR (actual_arrival IS NULL) OR (actual_departure >= actual_arrival))),
    CONSTRAINT trip_stop_event_stop_sequence_check CHECK ((stop_sequence > 0))
);


ALTER TABLE public.trip_stop_event OWNER TO postgres;

--
-- Name: trip_stop_event_trip_stop_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trip_stop_event_trip_stop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.trip_stop_event_trip_stop_id_seq OWNER TO postgres;

--
-- Name: trip_stop_event_trip_stop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trip_stop_event_trip_stop_id_seq OWNED BY public.trip_stop_event.trip_stop_id;


--
-- Name: trips; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trips (
    trip_id integer NOT NULL,
    vehicle_id integer NOT NULL,
    route_id integer NOT NULL,
    driver_id integer,
    scheduled_start timestamp without time zone NOT NULL,
    scheduled_end timestamp without time zone,
    actual_start timestamp without time zone,
    actual_end timestamp without time zone,
    status character varying(30) NOT NULL,
    CONSTRAINT trips_check CHECK (((actual_end IS NULL) OR (actual_start IS NULL) OR (actual_end >= actual_start)))
);


ALTER TABLE public.trips OWNER TO postgres;

--
-- Name: trips_trip_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trips_trip_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.trips_trip_id_seq OWNER TO postgres;

--
-- Name: trips_trip_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trips_trip_id_seq OWNED BY public.trips.trip_id;


--
-- Name: vehicle_position; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicle_position (
    position_id bigint NOT NULL,
    vehicle_id integer NOT NULL,
    trip_id integer,
    "timestamp" timestamp without time zone NOT NULL,
    location public.geometry(Point,4326) NOT NULL,
    speed numeric(6,2),
    CONSTRAINT vehicle_position_speed_check CHECK (((speed IS NULL) OR (speed >= (0)::numeric)))
);


ALTER TABLE public.vehicle_position OWNER TO postgres;

--
-- Name: vehicle_position_position_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vehicle_position_position_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vehicle_position_position_id_seq OWNER TO postgres;

--
-- Name: vehicle_position_position_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vehicle_position_position_id_seq OWNED BY public.vehicle_position.position_id;


--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicles (
    vehicle_id integer NOT NULL,
    vehicle_type character varying(50) NOT NULL,
    capacity integer NOT NULL,
    status character varying(30) NOT NULL,
    CONSTRAINT vehicles_capacity_check CHECK ((capacity > 0))
);


ALTER TABLE public.vehicles OWNER TO postgres;

--
-- Name: vehicles_vehicle_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vehicles_vehicle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vehicles_vehicle_id_seq OWNER TO postgres;

--
-- Name: vehicles_vehicle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vehicles_vehicle_id_seq OWNED BY public.vehicles.vehicle_id;


--
-- Name: delays delay_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delays ALTER COLUMN delay_id SET DEFAULT nextval('public.delays_delay_id_seq'::regclass);


--
-- Name: drivers driver_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.drivers ALTER COLUMN driver_id SET DEFAULT nextval('public.drivers_driver_id_seq'::regclass);


--
-- Name: route_stops route_stop_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.route_stops ALTER COLUMN route_stop_id SET DEFAULT nextval('public.route_stops_route_stop_id_seq'::regclass);


--
-- Name: routes route_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.routes ALTER COLUMN route_id SET DEFAULT nextval('public.routes_route_id_seq'::regclass);


--
-- Name: stops stop_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stops ALTER COLUMN stop_id SET DEFAULT nextval('public.stops_stop_id_seq'::regclass);


--
-- Name: trip_stop_event trip_stop_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trip_stop_event ALTER COLUMN trip_stop_id SET DEFAULT nextval('public.trip_stop_event_trip_stop_id_seq'::regclass);


--
-- Name: trips trip_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trips ALTER COLUMN trip_id SET DEFAULT nextval('public.trips_trip_id_seq'::regclass);


--
-- Name: vehicle_position position_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_position ALTER COLUMN position_id SET DEFAULT nextval('public.vehicle_position_position_id_seq'::regclass);


--
-- Name: vehicles vehicle_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicles ALTER COLUMN vehicle_id SET DEFAULT nextval('public.vehicles_vehicle_id_seq'::regclass);


--
-- Data for Name: delays; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delays (delay_id, trip_id, stop_id, delay_duration, delay_type, "timestamp") FROM stdin;
1	1	1	2	Transit	2026-09-17 08:07:00
2	1	3	5	Transit	2026-09-17 08:35:00
5	3	3	4	Transit	2026-09-17 09:09:00
8	4	5	8	Transit	2026-09-17 10:08:00
10	5	1	9	Transit	2026-09-17 10:39:00
12	6	7	8	Transit	2026-09-17 11:08:00
13	7	7	5	Transit	2026-09-17 11:10:00
16	8	7	10	Transit	2026-09-17 12:10:00
19	10	8	5	Transit	2026-09-17 12:53:00
4	2	2	8	Halt Delay	2026-09-17 08:56:00
6	3	1	7	Halt Delay	2026-09-17 09:37:00
7	4	4	6	Halt Delay	2026-09-17 09:54:00
11	6	6	6	Halt Delay	2026-09-17 10:54:00
14	7	4	9	Halt Delay	2026-09-17 11:39:00
15	8	5	7	Halt Delay	2026-09-17 11:42:00
18	9	5	10	Halt Delay	2026-09-17 12:40:00
20	10	10	7	Halt Delay	2026-09-17 13:07:00
3	2	1	7	Cascading Delay	2026-09-17 08:42:00
17	9	7	7	Cascading Delay	2026-09-17 12:12:00
9	5	5	6	Cascading Delay	2026-09-17 10:11:00
\.


--
-- Data for Name: drivers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.drivers (driver_id, name, license_info) FROM stdin;
1	Amit Sharma	DL-001
2	Priya Singh	DL-002
3	Rahul Verma	DL-003
4	Neha Kapoor	DL-004
5	Vikram Rao	DL-005
6	Sneha Patel	DL-006
7	Arjun Mehta	DL-007
8	Kavya Nair	DL-008
9	Rohan Das	DL-009
10	Ananya Gupta	DL-010
\.


--
-- Data for Name: route_stops; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.route_stops (route_stop_id, route_id, stop_id, stop_sequence) FROM stdin;
1	1	1	1
2	1	2	2
3	1	3	3
4	2	3	1
5	2	2	2
6	2	1	3
7	3	1	1
8	3	4	2
9	3	5	3
10	4	5	1
11	4	4	2
12	4	1	3
13	5	4	1
14	5	6	2
15	5	7	3
16	6	7	1
17	6	6	2
18	6	4	3
19	7	5	1
20	7	3	2
21	7	7	3
22	8	7	1
23	8	3	2
24	8	5	3
25	9	9	1
26	9	8	2
27	9	10	3
28	10	10	1
29	10	8	2
30	10	9	3
\.


--
-- Data for Name: routes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.routes (route_id, route_name, route_geometry) FROM stdin;
1	Route A	0102000020E610000003000000A5BDC117269F5340C3F5285C8F623140AC1C5A643B9F5340894160E5D06231408FC2F5285C9F53403333333333633140
2	Route B	0102000020E6100000030000008FC2F5285C9F53403333333333633140AC1C5A643B9F5340894160E5D0623140A5BDC117269F5340C3F5285C8F623140
3	Route C	0102000020E610000003000000A5BDC117269F5340C3F5285C8F6231401EA7E8482E9F5340FBCBEEC9C362314025068195439F53406DE7FBA9F1623140
4	Route D	0102000020E61000000300000025068195439F53406DE7FBA9F16231401EA7E8482E9F5340FBCBEEC9C3623140A5BDC117269F5340C3F5285C8F623140
5	Route E	0102000020E6100000030000001EA7E8482E9F5340FBCBEEC9C36231408195438B6C9F534017D9CEF753633140736891ED7C9F5340DD24068195633140
6	Route F	0102000020E610000003000000736891ED7C9F5340DD240681956331408195438B6C9F534017D9CEF7536331401EA7E8482E9F5340FBCBEEC9C3623140
7	Route G	0102000020E61000000300000025068195439F53406DE7FBA9F16231408FC2F5285C9F53403333333333633140736891ED7C9F5340DD24068195633140
8	Route H	0102000020E610000003000000736891ED7C9F5340DD240681956331408FC2F5285C9F5340333333333363314025068195439F53406DE7FBA9F1623140
9	Route I	0102000020E610000003000000C976BE9F1A9F5340FA7E6ABC7463314017D9CEF7539F5340A4703D0AD7633140643BDF4F8D9F5340508D976E12633140
10	Route J	0102000020E610000003000000643BDF4F8D9F5340508D976E1263314017D9CEF7539F5340A4703D0AD7633140C976BE9F1A9F5340FA7E6ABC74633140
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: stops; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stops (stop_id, stop_name, location) FROM stdin;
1	Main Gate	0101000020E6100000A5BDC117269F5340C3F5285C8F623140
2	Library	0101000020E6100000AC1C5A643B9F5340894160E5D0623140
3	Hostel	0101000020E61000008FC2F5285C9F53403333333333633140
4	Admin Block	0101000020E61000001EA7E8482E9F5340FBCBEEC9C3623140
5	Engineering Block	0101000020E610000025068195439F53406DE7FBA9F1623140
6	Sports Complex	0101000020E61000008195438B6C9F534017D9CEF753633140
7	Cafeteria	0101000020E6100000736891ED7C9F5340DD24068195633140
8	Medical Center	0101000020E610000017D9CEF7539F5340A4703D0AD7633140
9	Auditorium	0101000020E6100000C976BE9F1A9F5340FA7E6ABC74633140
10	Research Block	0101000020E6100000643BDF4F8D9F5340508D976E12633140
\.


--
-- Data for Name: trip_stop_event; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trip_stop_event (trip_stop_id, trip_id, stop_id, stop_sequence, scheduled_arrival, actual_arrival, scheduled_departure, actual_departure) FROM stdin;
1	1	1	1	2026-09-17 08:05:00	2026-09-17 08:07:00	2026-09-17 08:06:00	2026-09-17 08:08:00
2	1	2	2	2026-09-17 08:18:00	2026-09-17 08:21:00	2026-09-17 08:19:00	2026-09-17 08:22:00
3	1	3	3	2026-09-17 08:30:00	2026-09-17 08:35:00	2026-09-17 08:31:00	2026-09-17 08:36:00
4	2	1	1	2026-09-17 08:35:00	2026-09-17 08:42:00	2026-09-17 08:36:00	2026-09-17 08:43:00
5	2	2	2	2026-09-17 08:48:00	2026-09-17 08:56:00	2026-09-17 08:49:00	2026-09-17 08:57:00
6	2	3	3	2026-09-17 09:00:00	2026-09-17 09:09:00	2026-09-17 09:01:00	2026-09-17 09:10:00
7	3	3	1	2026-09-17 09:05:00	2026-09-17 09:09:00	2026-09-17 09:06:00	2026-09-17 09:10:00
8	3	2	2	2026-09-17 09:18:00	2026-09-17 09:23:00	2026-09-17 09:19:00	2026-09-17 09:24:00
9	3	1	3	2026-09-17 09:30:00	2026-09-17 09:37:00	2026-09-17 09:31:00	2026-09-17 09:38:00
10	4	1	1	2026-09-17 09:35:00	2026-09-17 09:39:00	2026-09-17 09:36:00	2026-09-17 09:40:00
11	4	4	2	2026-09-17 09:48:00	2026-09-17 09:54:00	2026-09-17 09:49:00	2026-09-17 09:55:00
12	4	5	3	2026-09-17 10:00:00	2026-09-17 10:08:00	2026-09-17 10:01:00	2026-09-17 10:09:00
13	5	5	1	2026-09-17 10:05:00	2026-09-17 10:11:00	2026-09-17 10:06:00	2026-09-17 10:12:00
14	5	4	2	2026-09-17 10:18:00	2026-09-17 10:25:00	2026-09-17 10:19:00	2026-09-17 10:26:00
15	5	1	3	2026-09-17 10:30:00	2026-09-17 10:39:00	2026-09-17 10:31:00	2026-09-17 10:40:00
16	6	4	1	2026-09-17 10:35:00	2026-09-17 10:39:00	2026-09-17 10:36:00	2026-09-17 10:40:00
17	6	6	2	2026-09-17 10:48:00	2026-09-17 10:54:00	2026-09-17 10:49:00	2026-09-17 10:55:00
18	6	7	3	2026-09-17 11:00:00	2026-09-17 11:08:00	2026-09-17 11:01:00	2026-09-17 11:09:00
19	7	7	1	2026-09-17 11:05:00	2026-09-17 11:10:00	2026-09-17 11:06:00	2026-09-17 11:11:00
20	7	6	2	2026-09-17 11:18:00	2026-09-17 11:25:00	2026-09-17 11:19:00	2026-09-17 11:26:00
21	7	4	3	2026-09-17 11:30:00	2026-09-17 11:39:00	2026-09-17 11:31:00	2026-09-17 11:40:00
22	8	5	1	2026-09-17 11:35:00	2026-09-17 11:42:00	2026-09-17 11:36:00	2026-09-17 11:43:00
23	8	3	2	2026-09-17 11:48:00	2026-09-17 11:57:00	2026-09-17 11:49:00	2026-09-17 11:58:00
24	8	7	3	2026-09-17 12:00:00	2026-09-17 12:10:00	2026-09-17 12:01:00	2026-09-17 12:11:00
25	9	7	1	2026-09-17 12:05:00	2026-09-17 12:12:00	2026-09-17 12:06:00	2026-09-17 12:13:00
26	9	3	2	2026-09-17 12:18:00	2026-09-17 12:27:00	2026-09-17 12:19:00	2026-09-17 12:28:00
27	9	5	3	2026-09-17 12:30:00	2026-09-17 12:40:00	2026-09-17 12:31:00	2026-09-17 12:41:00
28	10	9	1	2026-09-17 12:35:00	2026-09-17 12:38:00	2026-09-17 12:36:00	2026-09-17 12:39:00
29	10	8	2	2026-09-17 12:48:00	2026-09-17 12:53:00	2026-09-17 12:49:00	2026-09-17 12:54:00
30	10	10	3	2026-09-17 13:00:00	2026-09-17 13:07:00	2026-09-17 13:01:00	2026-09-17 13:08:00
\.


--
-- Data for Name: trips; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trips (trip_id, vehicle_id, route_id, driver_id, scheduled_start, scheduled_end, actual_start, actual_end, status) FROM stdin;
1	1	1	1	2026-09-17 08:00:00	2026-09-17 08:40:00	2026-09-17 08:03:00	2026-09-17 08:45:00	Completed
2	2	1	2	2026-09-17 08:30:00	2026-09-17 09:10:00	2026-09-17 08:37:00	2026-09-17 09:20:00	Completed
3	1	2	1	2026-09-17 09:00:00	2026-09-17 09:40:00	2026-09-17 09:04:00	2026-09-17 09:47:00	Completed
4	4	3	4	2026-09-17 09:30:00	2026-09-17 10:10:00	2026-09-17 09:34:00	2026-09-17 10:18:00	Completed
5	5	4	5	2026-09-17 10:00:00	2026-09-17 10:40:00	2026-09-17 10:06:00	2026-09-17 10:49:00	Completed
6	6	5	6	2026-09-17 10:30:00	2026-09-17 11:10:00	2026-09-17 10:34:00	2026-09-17 11:17:00	Completed
7	7	6	7	2026-09-17 11:00:00	2026-09-17 11:40:00	2026-09-17 11:05:00	2026-09-17 11:48:00	Completed
8	8	7	8	2026-09-17 11:30:00	2026-09-17 12:10:00	2026-09-17 11:36:00	2026-09-17 12:19:00	Completed
9	9	8	9	2026-09-17 12:00:00	2026-09-17 12:40:00	2026-09-17 12:07:00	2026-09-17 12:50:00	Completed
10	10	9	10	2026-09-17 12:30:00	2026-09-17 13:10:00	2026-09-17 12:33:00	2026-09-17 13:17:00	Completed
\.


--
-- Data for Name: vehicle_position; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vehicle_position (position_id, vehicle_id, trip_id, "timestamp", location, speed) FROM stdin;
1	1	1	2026-09-17 08:10:00	0101000020E6100000091B9E5E299F5340516B9A779C623140	18.50
2	1	1	2026-09-17 08:20:00	0101000020E6100000AC1C5A643B9F5340894160E5D0623140	15.20
3	1	1	2026-09-17 08:30:00	0101000020E61000009EEFA7C64B9F5340C217265305633140	12.70
4	2	2	2026-09-17 08:40:00	0101000020E6100000091B9E5E299F5340516B9A779C623140	16.40
5	2	2	2026-09-17 08:50:00	0101000020E6100000107A36AB3E9F534017B7D100DE623140	13.10
6	2	2	2026-09-17 09:00:00	0101000020E61000007A36AB3E579F5340DE02098A1F633140	10.80
7	1	3	2026-09-17 09:10:00	0101000020E61000007A36AB3E579F5340DE02098A1F633140	17.00
8	1	3	2026-09-17 09:20:00	0101000020E6100000AC1C5A643B9F5340894160E5D0623140	14.50
9	1	3	2026-09-17 09:30:00	0101000020E6100000BA490C022B9F5340516B9A779C623140	12.00
10	4	4	2026-09-17 09:40:00	0101000020E610000057EC2FBB279F53408AB0E1E995623140	18.00
11	4	4	2026-09-17 09:50:00	0101000020E61000001EA7E8482E9F5340FBCBEEC9C3623140	15.50
12	4	4	2026-09-17 10:00:00	0101000020E610000073D712F2419F5340A52C431CEB623140	12.20
13	5	5	2026-09-17 10:10:00	0101000020E610000073D712F2419F5340A52C431CEB623140	17.40
14	5	5	2026-09-17 10:20:00	0101000020E61000001EA7E8482E9F5340FBCBEEC9C3623140	13.80
15	5	5	2026-09-17 10:30:00	0101000020E610000057EC2FBB279F53408AB0E1E995623140	11.40
16	6	6	2026-09-17 10:40:00	0101000020E6100000D0D556EC2F9F5340C286A757CA623140	18.10
17	6	6	2026-09-17 10:50:00	0101000020E61000008195438B6C9F534017D9CEF753633140	13.60
18	6	6	2026-09-17 11:00:00	0101000020E6100000736891ED7C9F5340DD24068195633140	10.50
19	7	7	2026-09-17 11:10:00	0101000020E61000000F0BB5A6799F53404FAF946588633140	17.50
20	7	7	2026-09-17 11:20:00	0101000020E61000008195438B6C9F534017D9CEF753633140	14.00
21	7	7	2026-09-17 11:30:00	0101000020E6100000D0D556EC2F9F5340C286A757CA623140	11.20
22	8	8	2026-09-17 11:40:00	0101000020E610000025068195439F53406DE7FBA9F1623140	18.20
23	8	8	2026-09-17 11:50:00	0101000020E61000008FC2F5285C9F53403333333333633140	14.60
24	8	8	2026-09-17 12:00:00	0101000020E6100000736891ED7C9F5340DD24068195633140	11.00
25	9	9	2026-09-17 12:10:00	0101000020E61000000F0BB5A6799F53404FAF946588633140	17.00
26	9	9	2026-09-17 12:20:00	0101000020E61000008FC2F5285C9F53403333333333633140	13.80
27	9	9	2026-09-17 12:30:00	0101000020E610000025068195439F53406DE7FBA9F1623140	10.90
28	10	10	2026-09-17 12:40:00	0101000020E6100000C976BE9F1A9F5340FA7E6ABC74633140	18.40
29	10	10	2026-09-17 12:50:00	0101000020E610000017D9CEF7539F5340A4703D0AD7633140	14.20
30	10	10	2026-09-17 13:00:00	0101000020E6100000643BDF4F8D9F5340508D976E12633140	11.60
\.


--
-- Data for Name: vehicles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vehicles (vehicle_id, vehicle_type, capacity, status) FROM stdin;
1	Electric Bus	40	Active
2	Electric Bus	50	Active
4	Electric Bus	40	Active
5	Electric Bus	50	Active
6	Mini Bus	25	Active
7	Electric Bus	40	Active
8	Mini Bus	25	Active
9	Electric Bus	50	Active
3	Mini Bus	25	Not Active
10	Mini Bus	25	Not Active
\.


--
-- Name: delays_delay_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delays_delay_id_seq', 20, true);


--
-- Name: drivers_driver_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.drivers_driver_id_seq', 20, true);


--
-- Name: route_stops_route_stop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.route_stops_route_stop_id_seq', 31, true);


--
-- Name: routes_route_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.routes_route_id_seq', 20, true);


--
-- Name: stops_stop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stops_stop_id_seq', 20, true);


--
-- Name: trip_stop_event_trip_stop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trip_stop_event_trip_stop_id_seq', 30, true);


--
-- Name: trips_trip_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trips_trip_id_seq', 10, true);


--
-- Name: vehicle_position_position_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vehicle_position_position_id_seq', 30, true);


--
-- Name: vehicles_vehicle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vehicles_vehicle_id_seq', 20, true);


--
-- Name: delays delays_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delays
    ADD CONSTRAINT delays_pkey PRIMARY KEY (delay_id);


--
-- Name: drivers drivers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_pkey PRIMARY KEY (driver_id);


--
-- Name: route_stops route_stops_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.route_stops
    ADD CONSTRAINT route_stops_pkey PRIMARY KEY (route_stop_id);


--
-- Name: route_stops route_stops_route_id_stop_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.route_stops
    ADD CONSTRAINT route_stops_route_id_stop_id_key UNIQUE (route_id, stop_id);


--
-- Name: route_stops route_stops_route_id_stop_sequence_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.route_stops
    ADD CONSTRAINT route_stops_route_id_stop_sequence_key UNIQUE (route_id, stop_sequence);


--
-- Name: routes routes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.routes
    ADD CONSTRAINT routes_pkey PRIMARY KEY (route_id);


--
-- Name: stops stops_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stops
    ADD CONSTRAINT stops_pkey PRIMARY KEY (stop_id);


--
-- Name: trip_stop_event trip_stop_event_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trip_stop_event
    ADD CONSTRAINT trip_stop_event_pkey PRIMARY KEY (trip_stop_id);


--
-- Name: trip_stop_event trip_stop_event_trip_id_stop_sequence_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trip_stop_event
    ADD CONSTRAINT trip_stop_event_trip_id_stop_sequence_key UNIQUE (trip_id, stop_sequence);


--
-- Name: trips trips_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trips
    ADD CONSTRAINT trips_pkey PRIMARY KEY (trip_id);


--
-- Name: vehicle_position vehicle_position_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_position
    ADD CONSTRAINT vehicle_position_pkey PRIMARY KEY (position_id);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (vehicle_id);


--
-- Name: delays delays_stop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delays
    ADD CONSTRAINT delays_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES public.stops(stop_id);


--
-- Name: delays delays_trip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delays
    ADD CONSTRAINT delays_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(trip_id);


--
-- Name: route_stops route_stops_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.route_stops
    ADD CONSTRAINT route_stops_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.routes(route_id);


--
-- Name: route_stops route_stops_stop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.route_stops
    ADD CONSTRAINT route_stops_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES public.stops(stop_id);


--
-- Name: trip_stop_event trip_stop_event_stop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trip_stop_event
    ADD CONSTRAINT trip_stop_event_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES public.stops(stop_id);


--
-- Name: trip_stop_event trip_stop_event_trip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trip_stop_event
    ADD CONSTRAINT trip_stop_event_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(trip_id);


--
-- Name: trips trips_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trips
    ADD CONSTRAINT trips_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(driver_id);


--
-- Name: trips trips_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trips
    ADD CONSTRAINT trips_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.routes(route_id);


--
-- Name: trips trips_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trips
    ADD CONSTRAINT trips_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(vehicle_id);


--
-- Name: vehicle_position vehicle_position_trip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_position
    ADD CONSTRAINT vehicle_position_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(trip_id);


--
-- Name: vehicle_position vehicle_position_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_position
    ADD CONSTRAINT vehicle_position_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(vehicle_id);


--
-- PostgreSQL database dump complete
--

\unrestrict qaGvsp2uwoqOL7bthxFHTb7HO2KjzeMEKVzh2xKyugebdNXge0mmLwFQ8HsbanD

