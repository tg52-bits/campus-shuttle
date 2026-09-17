--
-- PostgreSQL database dump
--

\restrict LID6MrIdNmrlCs3RxJHeOm0dJcLrUi5ZJuoPtrrmyGxxHcJFB5ODoJIMORkDg8I

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
-- Name: campus_zones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campus_zones (
    zone_id integer NOT NULL,
    zone_name character varying(100) NOT NULL,
    boundary public.geometry(Polygon,4326) NOT NULL
);


ALTER TABLE public.campus_zones OWNER TO postgres;

--
-- Name: campus_zones_zone_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.campus_zones_zone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.campus_zones_zone_id_seq OWNER TO postgres;

--
-- Name: campus_zones_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.campus_zones_zone_id_seq OWNED BY public.campus_zones.zone_id;


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
-- Name: maintenance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.maintenance (
    maintenance_id integer NOT NULL,
    vehicle_id integer NOT NULL,
    maintenance_date date NOT NULL,
    type character varying(100)
);


ALTER TABLE public.maintenance OWNER TO postgres;

--
-- Name: maintenance_maintenance_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.maintenance_maintenance_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintenance_maintenance_id_seq OWNER TO postgres;

--
-- Name: maintenance_maintenance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.maintenance_maintenance_id_seq OWNED BY public.maintenance.maintenance_id;


--
-- Name: occupancy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.occupancy (
    occupancy_id bigint NOT NULL,
    trip_id integer NOT NULL,
    stop_id integer,
    "timestamp" timestamp without time zone NOT NULL,
    passenger_count integer NOT NULL,
    CONSTRAINT occupancy_passenger_count_check CHECK ((passenger_count >= 0))
);


ALTER TABLE public.occupancy OWNER TO postgres;

--
-- Name: occupancy_occupancy_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.occupancy_occupancy_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.occupancy_occupancy_id_seq OWNER TO postgres;

--
-- Name: occupancy_occupancy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.occupancy_occupancy_id_seq OWNED BY public.occupancy.occupancy_id;


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
-- Name: campus_zones zone_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campus_zones ALTER COLUMN zone_id SET DEFAULT nextval('public.campus_zones_zone_id_seq'::regclass);


--
-- Name: delays delay_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delays ALTER COLUMN delay_id SET DEFAULT nextval('public.delays_delay_id_seq'::regclass);


--
-- Name: drivers driver_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.drivers ALTER COLUMN driver_id SET DEFAULT nextval('public.drivers_driver_id_seq'::regclass);


--
-- Name: maintenance maintenance_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance ALTER COLUMN maintenance_id SET DEFAULT nextval('public.maintenance_maintenance_id_seq'::regclass);


--
-- Name: occupancy occupancy_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.occupancy ALTER COLUMN occupancy_id SET DEFAULT nextval('public.occupancy_occupancy_id_seq'::regclass);


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
-- Data for Name: campus_zones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.campus_zones (zone_id, zone_name, boundary) FROM stdin;
\.


--
-- Data for Name: delays; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delays (delay_id, trip_id, stop_id, delay_duration, delay_type, "timestamp") FROM stdin;
1	1	1	2	Traffic	2026-09-17 08:07:00
2	1	2	3	High Occupancy	2026-09-17 08:21:00
3	1	3	5	Traffic	2026-09-17 08:35:00
4	2	1	7	Previous Trip Delay	2026-09-17 08:42:00
5	2	2	8	High Occupancy	2026-09-17 08:56:00
\.


--
-- Data for Name: drivers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.drivers (driver_id, name, license_info) FROM stdin;
1	Amit Sharma	DL-001
2	Priya Singh	DL-002
3	Rahul Verma	DL-003
\.


--
-- Data for Name: maintenance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.maintenance (maintenance_id, vehicle_id, maintenance_date, type) FROM stdin;
\.


--
-- Data for Name: occupancy; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.occupancy (occupancy_id, trip_id, stop_id, "timestamp", passenger_count) FROM stdin;
1	1	1	2026-09-17 08:08:00	18
2	1	2	2026-09-17 08:22:00	31
3	1	3	2026-09-17 08:36:00	24
4	2	1	2026-09-17 08:43:00	35
5	2	2	2026-09-17 08:57:00	44
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
\.


--
-- Data for Name: routes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.routes (route_id, route_name, route_geometry) FROM stdin;
1	Route A	0102000020E610000003000000A5BDC117269F5340C3F5285C8F623140AC1C5A643B9F5340894160E5D06231408FC2F5285C9F53403333333333633140
2	Route B	0102000020E6100000030000008FC2F5285C9F53403333333333633140AC1C5A643B9F5340894160E5D0623140A5BDC117269F5340C3F5285C8F623140
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
\.


--
-- Data for Name: trips; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trips (trip_id, vehicle_id, route_id, driver_id, scheduled_start, scheduled_end, actual_start, actual_end, status) FROM stdin;
1	1	1	1	2026-09-17 08:00:00	2026-09-17 08:40:00	2026-09-17 08:03:00	2026-09-17 08:45:00	Completed
2	2	1	2	2026-09-17 08:30:00	2026-09-17 09:10:00	2026-09-17 08:37:00	2026-09-17 09:20:00	Completed
3	1	2	1	2026-09-17 09:30:00	2026-09-17 10:10:00	2026-09-17 09:32:00	\N	In Progress
\.


--
-- Data for Name: vehicle_position; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vehicle_position (position_id, vehicle_id, trip_id, "timestamp", location, speed) FROM stdin;
1	1	1	2026-09-17 08:10:00	0101000020E61000001EA7E8482E9F5340DFE00B93A9623140	18.50
2	1	1	2026-09-17 08:20:00	0101000020E6100000AC1C5A643B9F5340894160E5D0623140	15.20
3	1	1	2026-09-17 08:30:00	0101000020E61000009EEFA7C64B9F5340C217265305633140	12.70
4	2	2	2026-09-17 08:45:00	0101000020E610000033333333339F53406D567DAEB6623140	16.40
5	2	2	2026-09-17 08:55:00	0101000020E6100000107A36AB3E9F534017B7D100DE623140	11.80
\.


--
-- Data for Name: vehicles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vehicles (vehicle_id, vehicle_type, capacity, status) FROM stdin;
1	Electric Bus	40	Active
2	Electric Bus	50	Active
3	Mini Bus	25	Maintenance
\.


--
-- Name: campus_zones_zone_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.campus_zones_zone_id_seq', 1, false);


--
-- Name: delays_delay_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delays_delay_id_seq', 5, true);


--
-- Name: drivers_driver_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.drivers_driver_id_seq', 3, true);


--
-- Name: maintenance_maintenance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.maintenance_maintenance_id_seq', 1, false);


--
-- Name: occupancy_occupancy_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.occupancy_occupancy_id_seq', 5, true);


--
-- Name: route_stops_route_stop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.route_stops_route_stop_id_seq', 6, true);


--
-- Name: routes_route_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.routes_route_id_seq', 2, true);


--
-- Name: stops_stop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stops_stop_id_seq', 3, true);


--
-- Name: trip_stop_event_trip_stop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trip_stop_event_trip_stop_id_seq', 5, true);


--
-- Name: trips_trip_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trips_trip_id_seq', 3, true);


--
-- Name: vehicle_position_position_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vehicle_position_position_id_seq', 5, true);


--
-- Name: vehicles_vehicle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vehicles_vehicle_id_seq', 3, true);


--
-- Name: campus_zones campus_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campus_zones
    ADD CONSTRAINT campus_zones_pkey PRIMARY KEY (zone_id);


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
-- Name: maintenance maintenance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance
    ADD CONSTRAINT maintenance_pkey PRIMARY KEY (maintenance_id);


--
-- Name: occupancy occupancy_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.occupancy
    ADD CONSTRAINT occupancy_pkey PRIMARY KEY (occupancy_id);


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
-- Name: maintenance maintenance_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance
    ADD CONSTRAINT maintenance_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(vehicle_id);


--
-- Name: occupancy occupancy_stop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.occupancy
    ADD CONSTRAINT occupancy_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES public.stops(stop_id);


--
-- Name: occupancy occupancy_trip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.occupancy
    ADD CONSTRAINT occupancy_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.trips(trip_id);


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

\unrestrict LID6MrIdNmrlCs3RxJHeOm0dJcLrUi5ZJuoPtrrmyGxxHcJFB5ODoJIMORkDg8I

