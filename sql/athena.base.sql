--
-- PostgreSQL database dump
--

-- Dumped from database version 13.0
-- Dumped by pg_dump version 13.0

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
-- Name: edta; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA edta;


ALTER SCHEMA edta OWNER TO edulog;

--
-- Name: geo_master; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA geo_master;


ALTER SCHEMA geo_master OWNER TO edulog;

--
-- Name: geo_plan; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA geo_plan;


ALTER SCHEMA geo_plan OWNER TO edulog;

--
-- Name: ivin; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA ivin;


ALTER SCHEMA ivin OWNER TO edulog;

--
-- Name: rp_master; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA rp_master;


ALTER SCHEMA rp_master OWNER TO edulog;

--
-- Name: rp_plan; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA rp_plan;


ALTER SCHEMA rp_plan OWNER TO edulog;

--
-- Name: settings; Type: SCHEMA; Schema: -; Owner: edulog
--

CREATE SCHEMA settings;


ALTER SCHEMA settings OWNER TO edulog;

--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: edulog_intersects(public.geography, public.geography); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.edulog_intersects(geog1 public.geography, geog2 public.geography) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN public.st_intersects(geog1, geog2);
END
$$;


ALTER FUNCTION public.edulog_intersects(geog1 public.geography, geog2 public.geography) OWNER TO edulog;

--
-- Name: id_order_table(bigint[]); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.id_order_table(ordered_ids bigint[]) RETURNS TABLE(order_seq integer, order_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
	ordered_id_index INTEGER := 1;
BEGIN

	LOOP
	EXIT WHEN ordered_id_index = array_length(ordered_ids, 1) + 1;
		order_seq := ordered_id_index;
		order_id := ordered_ids[ordered_id_index];
		ordered_id_index := ordered_id_index + 1;
		RETURN NEXT;
	END LOOP;

END
$$;


ALTER FUNCTION public.id_order_table(ordered_ids bigint[]) OWNER TO edulog;

--
-- Name: report_bus_pass(bigint[]); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.report_bus_pass(ordered_ids bigint[]) RETURNS TABLE(last_name text, firstname text, district_id text, school_name text, stop_service_id bigint, stop_id bigint, stop_desc text, time_at_stop time without time zone, vehicle_name text)
    LANGUAGE sql
    AS $$

SELECT student.last_name, student.first_name, student.district_id, school.name_of AS school_name,
wm.id as stop_service_id, stop.id AS stop_id, stop.description AS stop_desc, wc.time_at AS time_at_stop, route.bus_number AS vehicle_name

FROM student

INNER JOIN id_order_table(ordered_ids) ON order_id = student.id

LEFT JOIN school_operation_master AS schopmaster ON schopmaster.id = student.school_operation_master_id
LEFT JOIN trip_master as tmaster ON student.id = tmaster.student_id
LEFT JOIN trip_cover as tcover ON tcover.trip_master_id = tmaster.id

INNER JOIN trip_leg ON trip_leg.trip_cover_id = tcover.id
INNER JOIN trip_leg_waypoint_master AS tlwm ON trip_leg.id = tlwm.trip_leg_id
INNER JOIN school ON schopmaster.school_id = school.id

LEFT JOIN belltime AS trip_origin_bell ON tcover.belltime_id_origin = trip_origin_bell.id
LEFT JOIN belltime AS trip_dest_bell ON tcover.belltime_id_destination = trip_dest_bell.id

INNER JOIN waypoint_master AS wm
	ON ((tlwm.waypoint_master_id_origin = wm.id AND trip_dest_bell.id IS NOT NULL) OR
		(tlwm.waypoint_master_id_destination = wm.id AND trip_origin_bell.id IS NOT NULL))
LEFT JOIN route_run AS rr ON wm.route_run_id = rr.id
LEFT JOIN run ON rr.run_id = run.id
LEFT JOIN route ON rr.route_id = route.id
LEFT JOIN stop ON wm.location_id = stop.location_id
LEFT JOIN waypoint_cover AS wc ON wm.id = wc.waypoint_master_id

WHERE trip_leg.type_of = 'SCHOOL_BUS_RIDE'

ORDER BY order_seq, time_at_stop

$$;


ALTER FUNCTION public.report_bus_pass(ordered_ids bigint[]) OWNER TO edulog;

--
-- Name: report_dirs_w_run_stop_stu_info(bigint[]); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.report_dirs_w_run_stop_stu_info(ordered_ids bigint[]) RETURNS TABLE(order_seq integer, route_code text, route_bus_num text, route_cap integer, route_desc text, run_code text, run_desc text, leg_partition bigint, running_dist_route bigint, last_leg_min bigint, running_dist_leg bigint, dir_seq integer, dir_instructions text, dir_dist integer, service_time time without time zone, stop_desc text, service_id bigint, last_name text, first_name text, district_id text, school text, grade text)
    LANGUAGE sql
    AS $$

SELECT

  order_seq,

  --Route info
  route_code, route_bus_num, route_cap, route_desc,
  
  --Run info
  FIRST_VALUE(run_code) OVER (PARTITION BY run_partition ORDER BY dir_seq) AS run_code,
  FIRST_VALUE(run_desc) OVER (PARTITION BY run_partition ORDER BY dir_seq) AS run_desc,
  
  --Include leg ID, to be used for grouping in report
  leg_partition,

  --Calculate a running distance, only summing when the record is not a direction step repeat.
  --This also uses last_dist so that the sum will be up to but not including the current step.
  SUM
  (
    CASE
    WHEN repeat_dir IS TRUE OR last_dist < 0
	THEN 0
	ELSE last_dist
	END
  )
  OVER (PARTITION BY path_cover_id ORDER BY dir_seq)
  AS running_dist_route,
  
  last_leg_min,
  
  SUM
  (
    CASE
    WHEN repeat_dir IS TRUE OR last_dist < 0
	THEN 0
	ELSE last_dist
	END
  )
  OVER (PARTITION BY last_leg_min ORDER BY dir_seq)
  AS running_dist_leg,
  
  --Direction info
  dir_seq, dir_instructions, dir_dist,
  
  --Service info
  service_time, stop_desc, service_id,
  
  --Student info
  last_name, first_name, district_id, school, grade

FROM
(
	SELECT
	order_seq,
	dir_seq,
	path_cover_id,
	route_code, route_bus_num, route_cap, route_desc,
	run_code, run_desc,
	service_time, stop_desc, service_id,
	last_name, first_name, district_id,
	school, grade,
	dir_instructions, dir_dist,
	run_partition, leg_partition, repeat_dir, last_dist,
	last_leg,
	MIN(last_leg) OVER (PARTITION BY path_cover_id, dir_seq) AS last_leg_min

	FROM
	(
		SELECT
		order_seq,
		dir_seq,
		path_cover_id,
		route_code, route_bus_num, route_cap, route_desc,
		run_code, run_desc,
		service_time, stop_desc, service_id,
		last_name, first_name, district_id,
		school, grade,
		dir_instructions, dir_dist,
		run_partition, leg_partition, repeat_dir, last_dist,
		COALESCE(LAG(leg_partition) OVER (PARTITION BY path_cover_id ORDER BY dir_seq), 0) AS last_leg

		FROM
		(
			SELECT
			order_seq,
			ds.seq_number AS dir_seq,
			path_cover.id as path_cover_id,
			route.code AS route_code, route.bus_number AS route_bus_num, route.capacity AS route_cap, route.description AS route_desc,
			run.code AS run_code, run.description AS run_desc,
			wc.time_at AS service_time, stop.description AS stop_desc, wm.id AS service_id,
			stu.last_name, stu.first_name, stu.district_id,
			sch.code AS school, grade.code AS grade,
			ds.instructions AS dir_instructions, ds.distance as dir_dist,

			--Generated partition ID for runs (reset at each waypoint which is attached to a run, which will create multiple
			--partitions per run but it doesn't matter since we are just using these to create partition windows to get the run info)
			SUM(CASE WHEN run.id IS null THEN 0 ELSE 1 END) OVER (ORDER BY path_cover.id, ds.seq_number) AS run_partition,

			--Generated partition ID for legs (reset at each waypoint)
			SUM(CASE WHEN wc.id IS null THEN 0 ELSE 1 END) OVER (ORDER BY path_cover.id, ds.seq_number) AS leg_partition,

			--Set one record per direction step to repeat_dir = false (for outer query)
			COALESCE(LAG(ds.seq_number) OVER (PARTITION BY path_cover.id ORDER BY ds.seq_number) = ds.seq_number, false) AS repeat_dir,

			--Offset distances with lag so we get distance up to but not including the current direction step
			COALESCE(LAG(ds.distance) OVER (PARTITION BY path_cover.id ORDER BY ds.seq_number), 0) AS last_dist

			FROM route

			INNER JOIN id_order_table(ordered_ids) ON order_id = route.id
			
			INNER JOIN path_master ON route.path_master_id = path_master.id
			INNER JOIN path_cover ON path_master.id = path_cover.path_master_id
			INNER JOIN direction_step AS ds ON path_cover.id = ds.path_cover_id

			LEFT JOIN waypoint_cover AS wc ON wc.id = ds.waypoint_cover_id
			LEFT JOIN waypoint_master AS wm ON wc.waypoint_master_id = wm.id
			LEFT JOIN stop ON stop.location_id = wm.location_id

			LEFT JOIN trip_leg_waypoint_master AS tlwm ON
			  (tlwm.waypoint_master_id_origin = wm.id OR tlwm.waypoint_master_id_destination = wm.id)
			  AND wm.type_of <> 'SCHOOL'
			LEFT JOIN trip_leg AS tl ON tl.id = tlwm.trip_leg_id

			LEFT JOIN trip_cover as tcover ON tcover.id = tl.trip_cover_id
			--LEFT JOIN trip AS trip ON trip.id = tl.trip_id
			LEFT JOIN trip_master as tmaster ON tmaster.id = tcover.trip_master_id

			--LEFT JOIN student AS stu ON trip.student_id = stu.id
			LEFT JOIN student as stu ON tmaster.student_id = stu.id

			LEFT JOIN route_run ON route_run.route_id = route.id AND wm.route_run_id = route_run.id
			LEFT JOIN run ON route_run.run_id = run.id

			--LEFT JOIN school_operation AS schop ON schop.id = stu.school_operation_id
			LEFT JOIN school_operation_master AS schopmaster ON schopmaster.id = stu.school_operation_master_id
			--LEFT JOIN school AS sch ON schop.school_id = sch.id
			LEFT JOIN school AS sch ON schopmaster.school_id = sch.id
			--LEFT JOIN grade ON schop.grade_id = grade.id
			LEFT JOIN grade ON schopmaster.grade_id = grade.id

			WHERE route.proxy IS false
		
		) AS route_dir_sub
	) AS route_dir_sub_leg_lag
) AS route_dir_sub_min_leg_lag
ORDER BY order_seq, dir_seq, last_name, first_name

$$;


ALTER FUNCTION public.report_dirs_w_run_stop_stu_info(ordered_ids bigint[]) OWNER TO edulog;

--
-- Name: report_run_with_stops(bigint[]); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.report_run_with_stops(ordered_ids bigint[]) RETURNS TABLE(order_seq integer, run_code text, run_desc text, dir_seq integer, pc_freq text, route_code text, wc_time_at time without time zone, wm_type text, stop_desc text, stop_code text, last_dist integer, runnint_dist_route bigint, running_dist_leg bigint, stu_load bigint, stu_acc bigint)
    LANGUAGE sql
    AS $$

SELECT distinct
order_seq,
run_code, run_desc, dir_seq, pc_freq, route_code,
wc_time_at, wm_type,
stop_desc, stop_code, last_dist,
running_dist_route, running_dist_leg,
CASE
	WHEN wm_type = 'SCHOOL'
	THEN 0
	ELSE stu_on + stu_off
END
AS stu_load,
stu_on_acc - stu_off_acc AS stu_acc

FROM
(
	SELECT
	order_seq,
	dir_seq, pc_id, run_code, run_desc, pc_freq, route_code,
	wc_time_at,
	wm.id AS wm_id, wm.type_of AS wm_type,
	stop.description AS stop_desc, stop.code AS stop_code,
	last_dist,
	COUNT(stuo.id) OVER (PARTITION BY wm_id ORDER BY dir_seq) AS stu_on,
	COUNT(stud.id) OVER (PARTITION BY wm_id ORDER BY dir_seq) AS stu_off,
	COUNT(stuo.id) OVER (PARTITION BY pc_id ORDER BY dir_seq) AS stu_on_acc,
	COUNT(stud.id) OVER (PARTITION BY pc_id ORDER BY dir_seq) AS stu_off_acc,
	SUM(last_dist) OVER (PARTITION BY run_code ORDER BY dir_seq) AS running_dist_route,
	SUM(last_dist) OVER (PARTITION BY leg_partition_lag ORDER BY dir_seq) AS running_dist_leg
	FROM
	(
		SELECT
		order_seq,
		dir_seq, run_code, run_desc, pc_id, pc_freq, route_code, wc_time_at,
		last_dist, wm_id,

		COALESCE(LAG(leg_partition) OVER (PARTITION BY pc_id ORDER BY dir_seq), 0) AS leg_partition_lag

		FROM
		(
			SELECT
			order_seq,
			pc_id, wc.id AS wc_id, wc.waypoint_master_id AS wm_id, wc.time_at as wc_time_at, ds.seq_number AS dir_seq,

			--Generated partition ID for legs (reset at each waypoint)
			SUM(CASE WHEN waypoint_cover_id IS null THEN 0 ELSE 1 END) OVER (ORDER BY pc_id, ds.seq_number) AS leg_partition,

			--Offset distances with lag so we get distance up to but not including the current direction step
			COALESCE(LAG(ds.distance) OVER (PARTITION BY pc_id ORDER BY ds.seq_number), 0) AS last_dist,

			run_code, run_desc, route_code, pc_freq

			FROM 
			(
				SELECT
				order_seq,
			-- 	waypoint_master.id as wm_id, waypoint_master.seq_number as wm_seq,
			-- 	waypoint_cover.id as wc_id, waypoint_cover.seq_number as wc_seq,
			-- 	direction_step.id as ds_id, direction_step.seq_number as ds_seq
				path_cover.id AS pc_id,

				MIN(direction_step.seq_number) AS min_ds_seq,
				MAX(direction_step.seq_number) AS max_ds_seq,

				run.code AS run_code, run.description AS run_desc,
				route.code AS route_code,
				path_cover.cover AS pc_freq

				FROM run
				INNER JOIN id_order_table(ordered_ids) ON order_id = run.id
				INNER JOIN route_run ON route_run.run_id = run.id
				INNER JOIN route on route_run.route_id = route.id
				INNER JOIN waypoint_master ON waypoint_master.route_run_id = route_run.id
				INNER JOIN waypoint_cover ON waypoint_master.id = waypoint_cover.waypoint_master_id
				INNER JOIN path_cover ON path_cover.id = waypoint_cover.path_cover_id
				INNER JOIN direction_step ON direction_step.waypoint_cover_id = waypoint_cover.id
					
				GROUP BY order_seq, run.code, run.description, route.code, path_cover.id, path_cover.cover
			) AS sub_run_dir_seq_bounds
			LEFT JOIN direction_step AS ds
				ON ds.path_cover_id = pc_id
				AND ds.seq_number >= min_ds_seq
				AND ds.seq_number <= max_ds_seq
			LEFT JOIN waypoint_cover AS wc ON wc.id = ds.waypoint_cover_id
		) AS sub_run_dir

	) AS sub_run_dir_stu_count
	
	LEFT JOIN waypoint_master AS wm ON wm.id = sub_run_dir_stu_count.wm_id

	LEFT JOIN stop ON stop.location_id = wm.location_id

	LEFT JOIN trip_leg_waypoint_master AS tlwmo ON tlwmo.waypoint_master_id_origin = wm.id
	LEFT JOIN trip_leg_waypoint_master AS tlwmd ON tlwmd.waypoint_master_id_destination = wm.id
	LEFT JOIN trip_leg AS tlo ON tlo.id = tlwmo.trip_leg_id
	LEFT JOIN trip_leg AS tld ON tld.id = tlwmd.trip_leg_id
	LEFT JOIN trip_cover as tripcovero ON tripcovero.id = tlo.trip_cover_id
	LEFT JOIN trip_master as tripmastero ON tripmastero.id = tripcovero.trip_master_id
	LEFT JOIN trip_cover as tripcoverd ON tripcoverd.id = tlo.trip_cover_id
	LEFT JOIN trip_master as tripmasterd ON tripmasterd.id = tripcoverd.trip_master_id
	LEFT JOIN student AS stuo ON tripmastero.student_id = stuo.id
	LEFT JOIN student AS stud ON tripmasterd.student_id = stud.id

) AS sub_run_dir_dist

WHERE wm_id IS NOT NULL

ORDER BY order_seq, pc_freq, dir_seq

$$;


ALTER FUNCTION public.report_run_with_stops(ordered_ids bigint[]) OWNER TO edulog;

--
-- Name: report_run_with_students(bigint[]); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.report_run_with_students(ordered_ids bigint[]) RETURNS TABLE(order_seq integer, run_code text, run_desc text, pc_freq text, dir_seq integer, route_code text, route_desc text, wc_time_at time without time zone, wm_type text, stop_desc text, stop_code text, last_dist integer, runnint_dist_route bigint, running_dist_leg bigint, stuo_last_name text, stuo_first_name text, stuo_district_id text, stuo_school_id bigint, stuo_grade_code text, stud_last_name text, stud_first_name text, stud_district_id text, stud_school_id bigint, stud_grade_code text, stuo_dob date, stud_dob date, stuo_sis_address text, stud_sis_address text, stuo_phone text, stud_phone text, stuo_school_code text, stuo_school_name text, stud_school_code text, stud_school_name text)
    LANGUAGE sql
    AS $$

SELECT DISTINCT
order_seq,
run_code, run_desc, pc_freq, dir_seq, route_code, route_desc,
wc_time_at, wm_type,
stop_desc, stop_code, last_dist,
running_dist_route, running_dist_leg,

--Student info
stu_origin.last_name as studento_last_name, stu_origin.first_name AS studento_first_name, stu_origin.district_id as districto_id,
schopmastero.school_id as schoolo_id, gradeo.code as gradeo_code,
stu_dest.last_name as studentd_last_name, stu_dest.first_name AS studentd_first_name, stu_dest.district_id as districtd_id,
schopmasterd.school_id as schoold_id, graded.code as graded_code,
stu_origin.date_of_birth as studento_dob, stu_dest.date_of_birth as studentd_dob,
stu_origin.sis_address as studento_addr, stu_dest.sis_address as studentd_addr,
stu_origin.phone as studento_phone, stu_dest.phone as studentd_phone,

--School info
schoolo.code AS schoolo_code, schoolo.name_of AS schoolo_name,
schoold.code AS schoold_code, schoold.name_of AS schoold_name

FROM
(
	SELECT
	order_seq,
	dir_seq, pc_id, run_code, run_desc, pc_freq, route_code, route_desc,
	wc_time_at,
	wm.id AS wm_id, wm.type_of AS wm_type,
	stop.description AS stop_desc, stop.code AS stop_code,
	last_dist,
	
	CASE
		WHEN wm.type_of = 'SCHOOL'
		THEN NULL
		ELSE stuo.id
	END
	AS stuo_id,
	
	CASE
		WHEN wm.type_of = 'SCHOOL'
		THEN NULL
		ELSE stud.id
	END
	AS stud_id,
	
-- 	stuo.id as stuo_id, stud.id as stud_id,
	SUM(last_dist) OVER (PARTITION BY pc_id ORDER BY dir_seq) AS running_dist_route,
	SUM(last_dist) OVER (PARTITION BY leg_partition_lag ORDER BY dir_seq) AS running_dist_leg
	FROM
	(
		SELECT
		order_seq,
		dir_seq, run_code, run_desc, pc_id, pc_freq, route_code, route_desc, wc_time_at,
		last_dist, wm_id,

		COALESCE(LAG(leg_partition) OVER (PARTITION BY pc_id ORDER BY dir_seq), 0) AS leg_partition_lag

		FROM
		(
			SELECT
			order_seq,
			pc_id, wc.id AS wc_id, wc.waypoint_master_id AS wm_id, wc.time_at as wc_time_at, ds.seq_number AS dir_seq,

			--Generated partition ID for legs (reset at each waypoint)
			SUM(CASE WHEN waypoint_cover_id IS null THEN 0 ELSE 1 END) OVER (ORDER BY pc_id, ds.seq_number) AS leg_partition,

			--Offset distances with lag so we get distance up to but not including the current direction step
			COALESCE(LAG(ds.distance) OVER (PARTITION BY pc_id ORDER BY ds.seq_number), 0) AS last_dist,

			run_code, run_desc, route_code, route_desc, pc_freq

			FROM 
			(
				SELECT
				order_seq,
			-- 	waypoint_master.id as wm_id, waypoint_master.seq_number as wm_seq,
			-- 	waypoint_cover.id as wc_id, waypoint_cover.seq_number as wc_seq,
			-- 	direction_step.id as ds_id, direction_step.seq_number as ds_seq
				path_cover.id AS pc_id,

				MIN(direction_step.seq_number) AS min_ds_seq,
				MAX(direction_step.seq_number) AS max_ds_seq,

				run.code AS run_code, run.description AS run_desc,
				route.code AS route_code, route.description as route_desc,
				path_cover.cover AS pc_freq

				FROM run
				INNER JOIN id_order_table(ordered_ids) ON order_id = run.id
				INNER JOIN route_run ON route_run.run_id = run.id
				INNER JOIN route on route_run.route_id = route.id
				INNER JOIN waypoint_master ON waypoint_master.route_run_id = route_run.id
				INNER JOIN waypoint_cover ON waypoint_master.id = waypoint_cover.waypoint_master_id
				INNER JOIN path_cover ON path_cover.id = waypoint_cover.path_cover_id
				INNER JOIN direction_step ON direction_step.waypoint_cover_id = waypoint_cover.id

				GROUP BY order_seq, run.code, run.description, route.code, route.description, path_cover.id, path_cover.cover
			) AS sub_run_dir_seq_bounds
			LEFT JOIN direction_step AS ds
				ON ds.path_cover_id = pc_id
				AND ds.seq_number >= min_ds_seq
				AND ds.seq_number <= max_ds_seq
			LEFT JOIN waypoint_cover AS wc ON wc.id = ds.waypoint_cover_id
		) AS sub_run_dir

	) AS sub_run_dir_stu_count
	
	LEFT JOIN waypoint_master AS wm ON wm.id = sub_run_dir_stu_count.wm_id

	LEFT JOIN stop ON stop.location_id = wm.location_id

	LEFT JOIN trip_leg_waypoint_master AS tlwmo ON tlwmo.waypoint_master_id_origin = wm.id
	LEFT JOIN trip_leg_waypoint_master AS tlwmd ON tlwmd.waypoint_master_id_destination = wm.id
	LEFT JOIN trip_leg AS tlo ON tlo.id = tlwmo.trip_leg_id
	LEFT JOIN trip_leg AS tld ON tld.id = tlwmd.trip_leg_id

  LEFT JOIN trip_cover as tripcovero ON tripcovero.id = tlo.trip_cover_id
  LEFT JOIN trip_master as tripmastero ON tripmastero.id = tripcovero.trip_master_id
  LEFT JOIN trip_cover as tripcoverd ON tripcoverd.id = tlo.trip_cover_id
  LEFT JOIN trip_master as tripmasterd ON tripmasterd.id = tripcoverd.trip_master_id
  
	--LEFT JOIN trip AS tripo ON tripo.id = tlo.trip_id
	--LEFT JOIN trip AS tripd ON tripd.id = tld.trip_id
	LEFT JOIN student AS stuo ON tripmastero.student_id = stuo.id
	LEFT JOIN student AS stud ON tripmasterd.student_id = stud.id

) AS sub_run_dir_dist

LEFT JOIN student AS stu_origin ON stu_origin.id = stuo_id
LEFT JOIN student AS stu_dest ON stu_dest.id = stud_id

LEFT JOIN school_operation_master AS schopmastero ON schopmastero.id = stu_origin.school_operation_master_id
LEFT JOIN school_operation_master AS schopmasterd ON schopmasterd.id = stu_dest.school_operation_master_id

LEFT JOIN grade AS gradeo ON schopmastero.grade_id = gradeo.id
LEFT JOIN grade AS graded ON schopmasterd.grade_id = graded.id
LEFT JOIN school AS schoolo ON schoolo.id = schopmastero.school_id
LEFT JOIN school AS schoold ON schoold.id = schopmasterd.school_id

WHERE wm_id IS NOT NULL
AND (stu_origin.id > 0 OR stu_dest.id > 0)
	
ORDER BY order_seq, pc_freq, dir_seq, gradeo_code, graded_code, studento_last_name, studentd_last_name, studento_first_name, studentd_first_name  ASC

$$;


ALTER FUNCTION public.report_run_with_students(ordered_ids bigint[]) OWNER TO edulog;

--
-- Name: report_student_trans(bigint[]); Type: FUNCTION; Schema: public; Owner: edulog
--

CREATE FUNCTION public.report_student_trans(ordered_ids bigint[]) RETURNS TABLE(order_seq integer, stu_fname text, stu_mname text, stu_lname text, stu_nick text, stu_dob date, stu_edulog_id text, stu_gov_id text, stu_district_id text, stu_apt_number text, stu_address text, stu_phone text, stu_email text, sch_code text, sch_name text, gra_code text, gra_desc text, pro_code text, pro_desc text, origin_rr_id bigint, origin_route_id bigint, origin_run_id bigint, origin_route_code text, origin_route_desc text, origin_run_code text, origin_run_desc text, origin_stop_code text, origin_stop_desc text, origin_loc_addr text, origin_stop_time time without time zone, dest_rr_id bigint, dest_route_id bigint, dest_run_id bigint, dest_route_code text, dest_route_desc text, dest_run_code text, dest_run_desc text, dest_stop_code text, dest_stop_desc text, dest_loc_addr text, dest_stop_time time without time zone)
    LANGUAGE sql
    AS $$

SELECT DISTINCT
	order_seq,
	-- student
	stu.first_name AS stu_fname, stu.middle_name AS stu_mname, stu.last_name AS stu_lname, stu.nick_name as stu_nick, stu.date_of_birth AS stu_dob,
	stu.edulog_id as stu_edulog_id, stu.government_id AS stu_gov_id, stu.district_id AS stu_district_id, 
	stu.sis_apt_number AS stu_apt_number, stu.sis_address AS stu_address, stu.phone as stu_phone, stu.email as stu_email,
	-- school, grade, program
	sch.code as sch_code, sch.name_of as sch_name, 
	gra.code AS gra_code, gra.description AS gra_desc, 
	pro.code AS pro_code, pro.description AS pro_desc,
	-- contacts
	--con.title as con_title, con.first_name as con_fname, con.last_name as con_lname, con.primary_phone as con_pphone, 
  	--con.primary_type as con_ptype, con.secondary_phone as con_sphone, con.secondary_type as con_stype, con.alternate_phone as con_aphone, 
  	--con.alternate_type as con_atype, con.email as con_email, con.mailing_address as con_address,
	-- origin stop, run, route info
	origin_wm.route_run_id AS origin_rr_id,
	origin_rr.route_id AS origin_route_id, origin_rr.run_id AS origin_run_id, 
	origin_route.code AS origin_route_code, origin_route.description AS origin_route_desc,
	origin_run.code AS origin_run_code, origin_run.description AS origin_run_desc,
	origin_stop.code AS origin_stop_code, origin_stop.description AS origin_stop_desc,
	origin_loc.address AS origin_loc_addr, origin_wc.time_at as origin_stop_time,
	-- dest stop, run, route info
  dest_wm.route_run_id AS dest_rr_id,
	dest_rr.route_id AS dest_route_id, dest_rr.run_id AS dest_run_id, 
	dest_route.code AS dest_route_code, dest_route.description AS dest_route_desc,
	dest_run.code AS dest_run_code, dest_run.description AS dest_run_desc,
	dest_stop.code AS dest_stop_code, dest_stop.description AS dest_stop_desc,
	dest_loc.address AS dest_loc_addr, dest_wc.time_at as dest_stop_time
    
FROM student AS stu

INNER JOIN id_order_table(ordered_ids) ON order_id = stu.id

LEFT JOIN school_operation_master AS schopmaster ON schopmaster.id = stu.school_operation_master_id
LEFT JOIN school AS sch ON sch.id = schopmaster.school_id
LEFT JOIN "program" AS pro ON pro.id = schopmaster.program_id
LEFT JOIN grade AS gra ON gra.id = schopmaster.grade_id
LEFT JOIN student_contact AS stucon ON stucon.student_id = stu.id
LEFT JOIN contact AS con ON stucon.contact_id = con.id

--LEFT JOIN trip ON trip.student_id = stu.id
--LEFT JOIN trip_leg AS tleg ON tleg.trip_id = trip.id
--LEFT JOIN trip_leg_waypoint_master AS tlegwm ON tlegwm.trip_leg_id = tleg.id

LEFT JOIN trip_master AS tmaster ON tmaster.student_id = stu.id
LEFT JOIN trip_cover AS tcover ON tcover.trip_master_id = tmaster.id
LEFT JOIN trip_leg AS tleg ON tleg.trip_cover_id = tcover.id
LEFT JOIN trip_leg_waypoint_master AS tlegwm ON tlegwm.trip_leg_id = tleg.id


LEFT JOIN waypoint_master AS origin_wm ON origin_wm.id = tlegwm.waypoint_master_id_origin
LEFT JOIN route_run AS origin_rr ON origin_rr.id = origin_wm.route_run_id
LEFT JOIN route AS origin_route ON origin_route.id = origin_rr.route_id
LEFT JOIN run AS origin_run ON origin_run.id = origin_rr.run_id
LEFT JOIN location AS origin_loc ON origin_loc.id = origin_wm.location_id
LEFT JOIN stop AS origin_stop ON origin_stop.location_id = origin_loc.id
LEFT JOIN waypoint_cover AS origin_wc ON origin_wc.waypoint_master_id = origin_wm.id

LEFT JOIN waypoint_master AS dest_wm ON dest_wm.id = tlegwm.waypoint_master_id_destination
LEFT JOIN route_run AS dest_rr ON dest_rr.id = dest_wm.route_run_id
LEFT JOIN route AS dest_route ON dest_route.id = dest_rr.route_id
LEFT JOIN run AS dest_run ON dest_run.id = dest_rr.run_id
LEFT JOIN location AS dest_loc ON dest_loc.id = dest_wm.location_id
LEFT JOIN stop AS dest_stop ON dest_stop.location_id = dest_loc.id
LEFT JOIN waypoint_cover AS dest_wc ON dest_wc.waypoint_master_id = dest_wm.id

WHERE origin_rr.id > 0 AND dest_rr.id > 0

ORDER BY order_seq, origin_stop_time, dest_stop_time

$$;


ALTER FUNCTION public.report_student_trans(ordered_ids bigint[]) OWNER TO edulog;

--
-- Name: add_free_data_area(text, text, text, text, text, bigint); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.add_free_data_area(area_name text, area_description text, rp_schema text, geo_schema text, user_id text, clone_from_data_area_id bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	schema_name_list TEXT[];
	new_data_area_id BIGINT;
BEGIN

	SELECT rp_schema_name, geo_schema_name INTO rp_schema, geo_schema FROM rp_master.validate_data_area_schemas(rp_schema, geo_schema);

	--Insert new data area record
	INSERT INTO rp_master.data_area (name_of, description, rp_schema, geo_schema, rolling_seq, user_id, time_changed)
		VALUES (area_name, area_description, rp_schema, geo_schema, null, user_id, current_timestamp)
		RETURNING currval('rp_master.data_area_id_seq') INTO new_data_area_id;
	--Clone from source data area into new data area
	PERFORM rp_master.clone_data_area(clone_from_data_area_id, new_data_area_id);
	
	RETURN true;
END
$$;


ALTER FUNCTION rp_master.add_free_data_area(area_name text, area_description text, rp_schema text, geo_schema text, user_id text, clone_from_data_area_id bigint) OWNER TO edulog;

--
-- Name: add_rolling_data_area(text, text, text, text, integer, text, boolean); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.add_rolling_data_area(area_name text, area_description text, rp_schema text, geo_schema text, area_rolling_seq integer, user_id text, offset_duplication_to_end boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	schema_name_list TEXT[];
	data_area_total INTEGER;
	previous_data_area_id BIGINT;
	new_data_area_id BIGINT;
	data_area_offset_list BIGINT[];
BEGIN

	SELECT rp_schema_name, geo_schema_name INTO rp_schema, geo_schema FROM rp_master.validate_data_area_schemas(rp_schema, geo_schema);

	EXECUTE 'SELECT COUNT(*) FROM rp_master.data_area WHERE rolling_seq IS NOT NULL;' INTO data_area_total;

	--Check that we are putting the new data area after the first (default) data area and
	--that the data area name is not in use as a schema name already.
	IF area_rolling_seq <= 1 OR area_rolling_seq > data_area_total + 1 THEN
		RAISE EXCEPTION 'Invalid sequence number: %', area_rolling_seq;
	ELSE
		--Update existing data areas to make room where needed for the new one
		EXECUTE format('UPDATE rp_master.data_area SET rolling_seq = rolling_seq + 1 WHERE rolling_seq >= %s;', area_rolling_seq);
		
		--Insert new data area record
		INSERT INTO rp_master.data_area (name_of, description, rp_schema, geo_schema, rolling_seq, user_id, time_changed)
			VALUES (area_name, area_description, rp_schema, geo_schema, area_rolling_seq, user_id, current_timestamp)
			RETURNING currval('rp_master.data_area_id_seq') INTO new_data_area_id;
		
		--Find previous data area for initial clone
		EXECUTE format('SELECT id FROM rp_master.data_area WHERE rolling_seq = %s - 1;', area_rolling_seq) INTO previous_data_area_id;

		IF offset_duplication_to_end AND area_rolling_seq < (SELECT MAX(rolling_seq) FROM rp_master.data_area) THEN
			--Create empty schemas as placeholder
			PERFORM rp_master.create_new_data_area_schemas(new_data_area_id);
			--Roll in reverse to offset duplication to the end
			data_area_offset_list := ARRAY(SELECT id FROM rp_master.data_area WHERE rolling_seq >= area_rolling_seq ORDER BY rolling_seq DESC);
			PERFORM rp_master.rollover_data_areas(data_area_offset_list, true);
		ELSE
			--Clone previous data area into new data area
			PERFORM rp_master.clone_data_area(previous_data_area_id, new_data_area_id);
		END IF;
	END IF;

	RETURN true;
END
$$;


ALTER FUNCTION rp_master.add_rolling_data_area(area_name text, area_description text, rp_schema text, geo_schema text, area_rolling_seq integer, user_id text, offset_duplication_to_end boolean) OWNER TO edulog;

--
-- Name: clone_data_area(bigint, bigint); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.clone_data_area(source_data_area_id bigint, dest_data_area_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	source_data_area_schemas TEXT[];
	dest_data_area_schemas TEXT[];
	source_schema TEXT;
	dest_schema TEXT;
	schema_index INTEGER;
BEGIN
	source_data_area_schemas = rp_master.get_schemas_for_data_area(source_data_area_id);
	dest_data_area_schemas = rp_master.get_schemas_for_data_area(dest_data_area_id);
	
	RAISE NOTICE 'Cloning from % into %', source_data_area_schemas, dest_data_area_schemas;
	
	schema_index = array_lower(source_data_area_schemas, 1);

	LOOP
	EXIT WHEN schema_index > array_upper(source_data_area_schemas, 1);
		source_schema = source_data_area_schemas[schema_index];
		dest_schema = dest_data_area_schemas[schema_index];
		PERFORM rp_master.clone_schema(source_schema, dest_schema);
		schema_index = schema_index + 1;
	END LOOP;
END
$$;


ALTER FUNCTION rp_master.clone_data_area(source_data_area_id bigint, dest_data_area_id bigint) OWNER TO edulog;

--
-- Name: clone_schema(text, text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.clone_schema(source_schema text, dest_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	PERFORM rp_master.create_empty_schema(dest_schema);
	PERFORM rp_master.copy_to_schema(source_schema, dest_schema);
END
$$;


ALTER FUNCTION rp_master.clone_schema(source_schema text, dest_schema text) OWNER TO edulog;

--
-- Name: copy_to_schema(text, text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.copy_to_schema(source_schema text, dest_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
	sequences_query TEXT :=
		'SELECT quote_ident(pgcs.relname) AS sequence_name,
				quote_ident(pgct.relname) AS table_name,
				quote_ident(pga.attname) AS column_name
		 FROM pg_class AS pgcs
		 INNER JOIN pg_depend AS pgd ON pgcs.oid = pgd.objid
		 INNER JOIN pg_class AS pgct ON pgd.refobjid = pgct.oid
		 INNER JOIN pg_namespace AS pgns ON pgns.oid = pgct.relnamespace
		 INNER JOIN pg_attribute AS pga ON pgd.refobjid = pga.attrelid AND pgd.refobjsubid = pga.attnum
		 WHERE pgcs.relkind = ''S'' AND pgns.nspname = $1
		 ORDER BY sequence_name;';
	tables_query TEXT:=
		'SELECT relfilenode, relname as table_name
         FROM pg_class pgc
		 INNER JOIN pg_namespace AS pgns ON pgns.oid = pgc.relnamespace
         WHERE pgns.nspname = $1 AND pgc.relkind = ''r'';';
	sequence_columns_query TEXT:=
		'SELECT table_name, column_name, column_default
         FROM information_schema.columns
		 WHERE table_schema = $1
		 AND column_default like ''nextval%'';';
	constraints_query TEXT:=
		'SELECT pgct.relname AS table_name,
         		con.conname AS constraint_name,
            	pg_catalog.pg_get_constraintdef(con.oid) AS constraint_definition,
				con.contype
         FROM pg_catalog.pg_constraint AS con
         INNER JOIN pg_class AS pgct ON pgct.relnamespace = con.connamespace AND pgct.oid = con.conrelid
		 INNER JOIN pg_namespace AS pgns ON pgns.oid = pgct.relnamespace
         WHERE pgns.nspname = $1 AND con.contype = $2;';
	index_query TEXT:=
        'SELECT pgct.relname AS table_name,
		 		pg_catalog.pg_get_indexdef(pgi.indexrelid) AS index_definition
         FROM pg_index pgi
         JOIN pg_class AS pgci ON pgci.oid = pgi.indexrelid
         JOIN pg_class AS pgct ON pgct.oid = pgi.indrelid
		 INNER JOIN pg_namespace AS pgns ON pgns.oid = pgci.relnamespace
         WHERE pgns.nspname = $1 AND pgi.indisprimary = false;';
	views_query TEXT:=
		'SELECT table_name, view_definition
		 FROM information_schema.views
		 WHERE table_schema = $1';
	seq_parts TEXT[];
	seq_name TEXT;
	seq_prefix TEXT;
	seq_suffix TEXT;
	seq_old_schema_name TEXT;
	seq_update TEXT;
	seq_update_query TEXT;
	index_parts TEXT[];
	index_prefix TEXT;
	index_suffix TEXT;
	index_update TEXT;
	constraint_def_parts TEXT[];
	constraint_def_prefix TEXT;
	constraint_def_suffix TEXT;
	constraint_schema_name TEXT;
	seq_identifier TEXT;
	rec RECORD;
	original_set_schema TEXT;
	view_def TEXT;
BEGIN

	--Set the schema to public to avoid information_schema results from being inconsistent based
	--on the current schema.  Track the currently set schema to reset at the end of the method.
	original_set_schema = current_schema();
	SET SCHEMA 'public';

	--Copy sequences
	RAISE NOTICE 'Copy sequences';
	FOR rec IN EXECUTE sequences_query USING source_schema
	LOOP
		--RAISE NOTICE '%', rec.sequence_name;
		EXECUTE format('CREATE SEQUENCE %I.%I', dest_schema, rec.sequence_name);
	END LOOP;
	
	--Copy tables
	RAISE NOTICE 'Copy tables';
	FOR rec IN EXECUTE tables_query USING source_schema
	LOOP
		--RAISE NOTICE '%', rec.table_name;
		EXECUTE format('CREATE TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS)', dest_schema, rec.table_name, source_schema, rec.table_name);
	END LOOP;
	
	--Update sequences to reference dest_schema
	RAISE NOTICE 'Update sequence schema references';
	FOR rec IN EXECUTE sequence_columns_query USING source_schema
	LOOP
		--RAISE NOTICE '%', rec.column_default;
		
		seq_parts = (regexp_split_to_array(rec.column_default, E'[\'\.]')); --Close single quote for bad Netbeans SQL parser '
		seq_old_schema_name = seq_parts[2];
		seq_name = seq_parts[3];
		
		IF seq_name IS NOT NULL AND seq_old_schema_name <> '' THEN
			seq_prefix = seq_parts[1];
			seq_suffix = seq_parts[4];
			seq_update = seq_prefix || '''%I.' || seq_name || '''' || seq_suffix;
			seq_update_query = 'ALTER TABLE ONLY %I.%I ALTER COLUMN %I SET DEFAULT ' || seq_update || ';';
			EXECUTE format('ALTER SEQUENCE %I.%I OWNED BY %I.%I.%I;', dest_schema, seq_name, dest_schema, rec.table_name, rec.column_name);
			EXECUTE format(seq_update_query, dest_schema, rec.table_name, rec.column_name, dest_schema);
		END IF;
	END LOOP;
	
	--Copy data into tables
	RAISE NOTICE 'Copy data into tables';
	FOR rec IN EXECUTE tables_query USING source_schema
	LOOP
		--RAISE NOTICE '%', rec.table_name;
		EXECUTE format('INSERT INTO %I.%I SELECT * FROM %I.%I;', dest_schema, rec.table_name, source_schema, rec.table_name);
	END LOOP;
	
	--Copy primary keys
	RAISE NOTICE 'Copy primary keys';
	FOR rec IN EXECUTE constraints_query USING source_schema, 'p'
	LOOP
		--RAISE NOTICE '%', rec.constraint_name;
		EXECUTE format('ALTER TABLE ONLY %I.%I ADD CONSTRAINT %I %s;', dest_schema, rec.table_name, rec.constraint_name, rec.constraint_definition);
	END LOOP;

	--Copy indexes
	RAISE NOTICE 'Copy indexes';
	FOR rec IN EXECUTE index_query USING source_schema
	LOOP
		index_parts = regexp_split_to_array(rec.index_definition, E'(\\sON\\s)|\\.');
		index_prefix = index_parts[1] || ' ON ';
		index_suffix = '.' || index_parts[3];
		index_update = index_prefix || '%I' || index_suffix;
		EXECUTE format(index_update, dest_schema);
	END LOOP;

	--Copy foreign keys
	RAISE NOTICE 'Copy foreign keys';
	FOR rec IN EXECUTE constraints_query USING source_schema, 'f'
	LOOP
		--RAISE NOTICE '%', rec.constraint_name;

		constraint_def_parts = regexp_split_to_array(rec.constraint_definition, E'(\\sREFERENCES\\s)|\\.');
		constraint_schema_name = constraint_def_parts[2];

		IF constraint_schema_name = source_schema THEN
			--Create foreign key referencing new data area schema
			constraint_def_prefix = constraint_def_parts[1] || ' REFERENCES ';
			constraint_def_suffix = '.' || constraint_def_parts[3];
			EXECUTE format('ALTER TABLE ONLY %I.%I ADD CONSTRAINT %I %s%I%s;', dest_schema, rec.table_name, rec.constraint_name, constraint_def_prefix, dest_schema, constraint_def_suffix);
		ELSE
			--Create foreign key referencing outside schema (unchanged between data areas)
			EXECUTE format('ALTER TABLE ONLY %I.%I ADD CONSTRAINT %I %s', dest_schema, rec.table_name, rec.constraint_name, rec.constraint_definition);
		END IF;
	END LOOP;
	
	--Fix sequences that were previously inserted
	FOR rec IN EXECUTE sequences_query USING source_schema
	LOOP
		--RAISE NOTICE '%', rec.sequence_name;
		seq_identifier = dest_schema || '.' || rec.sequence_name;
		EXECUTE format('SELECT setval(''%s'', (SELECT COALESCE(MAX(%I), 1) FROM %I.%I), true);', seq_identifier, rec.column_name, dest_schema, rec.table_name);
	END LOOP;
	
	--Copy views
	RAISE NOTICE 'Copy views';
	FOR rec IN EXECUTE views_query USING source_schema
	LOOP
-- 		RAISE NOTICE 'Copying view % to schema %', rec.table_name, dest_schema;
		view_def = REPLACE(rec.view_definition, source_schema, dest_schema);
		EXECUTE FORMAT('CREATE OR REPLACE VIEW %I.%I AS %s', dest_schema, rec.table_name, view_def);
	END LOOP;
	
	EXECUTE format('SET SCHEMA ''%I''', original_set_schema);
END
$_$;


ALTER FUNCTION rp_master.copy_to_schema(source_schema text, dest_schema text) OWNER TO edulog;

--
-- Name: create_empty_schema(text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.create_empty_schema(empty_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	RAISE NOTICE 'Creating schema %', empty_schema;
	EXECUTE format('CREATE SCHEMA %I', empty_schema);
END
$$;


ALTER FUNCTION rp_master.create_empty_schema(empty_schema text) OWNER TO edulog;

--
-- Name: create_new_data_area_schemas(bigint); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.create_new_data_area_schemas(data_area_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
   data_area_schema_list TEXT[];
   data_area_schema TEXT;
BEGIN

	RAISE NOTICE 'Creating schemas for data area ID: %', data_area_id;
	EXECUTE format('SELECT rp_master.get_schemas_for_data_area(''%s'');', data_area_id) INTO data_area_schema_list;
	
	FOREACH data_area_schema IN ARRAY data_area_schema_list
	LOOP 
	   RAISE NOTICE 'Creating schema %', data_area_schema;
	   PERFORM rp_master.create_empty_schema(data_area_schema);
	END LOOP;

END
$$;


ALTER FUNCTION rp_master.create_new_data_area_schemas(data_area_id bigint) OWNER TO edulog;

--
-- Name: drop_data_area_schemas(bigint); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.drop_data_area_schemas(data_area_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
   data_area_schema_list TEXT[];
   data_area_schema TEXT;
BEGIN

	EXECUTE format('SELECT rp_master.get_schemas_for_data_area(''%s'');', data_area_id) INTO data_area_schema_list;
	
	FOREACH data_area_schema IN ARRAY data_area_schema_list
	LOOP 
	   RAISE NOTICE 'Dropping schema %', data_area_schema;
	   EXECUTE format('DROP SCHEMA IF EXISTS %I CASCADE', data_area_schema);
	END LOOP;

END
$$;


ALTER FUNCTION rp_master.drop_data_area_schemas(data_area_id bigint) OWNER TO edulog;

--
-- Name: get_schemas_for_data_area(bigint); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.get_schemas_for_data_area(data_area_id bigint) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
	rp_schema TEXT;
	geo_schema TEXT;
	data_area_schemas TEXT[];
BEGIN
	EXECUTE format('SELECT rp_schema FROM rp_master.data_area WHERE id = ''%s'';', data_area_id) INTO rp_schema;
	EXECUTE format('SELECT geo_schema FROM rp_master.data_area WHERE id = ''%s'';', data_area_id) INTO geo_schema;
	RAISE NOTICE 'Found RP schema: %', rp_schema;
	RAISE NOTICE 'Found Geo schema: %', geo_schema;
	data_area_schemas := ARRAY[rp_schema, geo_schema];
	RETURN data_area_schemas;
END
$$;


ALTER FUNCTION rp_master.get_schemas_for_data_area(data_area_id bigint) OWNER TO edulog;

--
-- Name: get_schemas_for_data_area_list(bigint[]); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.get_schemas_for_data_area_list(data_area_id_list bigint[]) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
	data_area_schemas_list TEXT[][] = ARRAY[]::BIGINT[];
BEGIN
	EXECUTE format('SELECT ARRAY_AGG(data_area_schemas) AS data_area_schema_lists
					FROM
					(
						SELECT ARRAY[rp_schema, geo_schema] AS data_area_schemas
						FROM rp_master.data_area
						INNER JOIN public.id_order_table(''%s'') ON order_id = data_area.id
				   		ORDER BY order_seq
					) AS dim1;', data_area_id_list) INTO data_area_schemas_list;
	RETURN data_area_schemas_list;
END
$$;


ALTER FUNCTION rp_master.get_schemas_for_data_area_list(data_area_id_list bigint[]) OWNER TO edulog;

--
-- Name: remove_free_data_area(bigint); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.remove_free_data_area(data_area_id bigint) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	data_area_id_list BIGINT[];
	area_rolling_seq INTEGER;
BEGIN
	data_area_id_list := ARRAY(SELECT id FROM rp_master.data_area);
	EXECUTE format('SELECT rolling_seq FROM rp_master.data_area WHERE id = ''%s'';', data_area_id) INTO area_rolling_seq;
	
	--Check that the data area actually exists and that it is not part of the rolling
	--data areas (those must be removed through the remove_rolling_data_area function).
	IF NOT (data_area_id = ANY(data_area_id_list)) THEN
		RAISE EXCEPTION 'Data Area ID does not exist: %', data_area_id;
	ELSIF area_rolling_seq IS NOT null THEN
		RAISE EXCEPTION 'Data Area ID is not a free data area: %', data_area_id;
	ELSE
		--Delete the schemas
		PERFORM rp_master.drop_data_area_schemas(data_area_id);
		--Delete the corresponding data area record
		EXECUTE format('DELETE FROM rp_master.data_area WHERE id = ''%s'';', data_area_id);
	END IF;
	
	RETURN true;
END
$$;


ALTER FUNCTION rp_master.remove_free_data_area(data_area_id bigint) OWNER TO edulog;

--
-- Name: remove_rolling_data_area(bigint, boolean); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.remove_rolling_data_area(data_area_id bigint, retract_rolling_schemas boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	data_area_id_list BIGINT[];
	area_rolling_seq INTEGER;
	data_area_retraction_list BIGINT[];
BEGIN
	data_area_id_list := ARRAY(SELECT id FROM rp_master.data_area);
	EXECUTE format('SELECT rolling_seq FROM rp_master.data_area WHERE id = ''%s'';', data_area_id) INTO area_rolling_seq;
	
	--Check that the data area actually exists and that it is not the default data area
	--which we are not allowed to delete and that it is actually part of the rolling
	--schemas.
	IF NOT (data_area_id = ANY(data_area_id_list)) THEN
		RAISE EXCEPTION 'Data Area ID does not exist: %', data_area_id;
	ELSIF area_rolling_seq IS null THEN
		RAISE EXCEPTION 'Data Area ID is not a rolling data area: %', data_area_id;
	ELSIF area_rolling_seq = 1 THEN
		RAISE EXCEPTION 'Cannot delete default data area (rolling sequence 1): %', data_area_id;
	ELSE
		data_area_retraction_list := ARRAY(SELECT id FROM rp_master.data_area WHERE rolling_seq >= area_rolling_seq ORDER BY rolling_seq);
		IF retract_rolling_schemas AND COALESCE(array_length(data_area_retraction_list, 1), 0) > 1 THEN
			--Roll schemas from deleted data area on without restoring, causing the schema to be removed.
			PERFORM rp_master.rollover_data_areas(data_area_retraction_list, false);
		ELSE
			--Delete the schemas
			PERFORM rp_master.drop_data_area_schemas(data_area_id);
		END IF;

		--Delete the corresponding data area record
		EXECUTE format('DELETE FROM rp_master.data_area WHERE id = ''%s'';', data_area_id);
		--Update rolling schema sequence
		EXECUTE format('UPDATE rp_master.data_area SET rolling_seq = rolling_seq - 1 WHERE rolling_seq >= ''%s'';', area_rolling_seq);
	END IF;	
	
	RETURN true;
END
$$;


ALTER FUNCTION rp_master.remove_rolling_data_area(data_area_id bigint, retract_rolling_schemas boolean) OWNER TO edulog;

--
-- Name: rename_data_area_schemas(bigint, text, text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.rename_data_area_schemas(data_area_id bigint, rp_schema text, geo_schema text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
 	schema_name_list TEXT[];
	source_rp_schema TEXT;
	source_geo_schema TEXT;
BEGIN

	SELECT rp_schema_name, geo_schema_name INTO rp_schema, geo_schema FROM rp_master.validate_data_area_schemas(rp_schema, geo_schema);

	EXECUTE format('SELECT rp_master.rp_schema WHERE id = ''%s'';', data_area_id) INTO source_rp_schema;
	EXECUTE format('SELECT rp_master.geo_schema WHERE id = ''%s'';', data_area_id) INTO source_geo_schema;

	RAISE NOTICE 'Renaming data area % to %', from_area_id, to_area_id;
	PERFORM rp_master.rename_schema(source_rp_schema, rp_schema);
	PERFORM rp_master.rename_schema(source_geo_schema, geo_schema);

	--Update the data area record to match
	EXECUTE format('UPDATE rp_master.data_area SET rp_schema = ''%s'', geo_schema = ''%s'' WHERE id = ''%s'';', rp_schema, geo_schema, data_area_id);
	
	RETURN true;
END
$$;


ALTER FUNCTION rp_master.rename_data_area_schemas(data_area_id bigint, rp_schema text, geo_schema text) OWNER TO edulog;

--
-- Name: rename_schema(text, text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.rename_schema(current_schema_name text, new_schema_name text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	schema_name_list TEXT[];
BEGIN
	schema_name_list := ARRAY(SELECT nspname::TEXT FROM pg_catalog.pg_namespace);
	
	--Check that the new schema name is not in use already and that the existing
  --schema name actually exists
	IF (new_schema_name = ANY(schema_name_list)) OR NOT (current_schema_name = ANY(schema_name_list)) THEN
		RETURN false;
	ELSE
		RAISE NOTICE 'Renaming schema % to %', current_schema_name, new_schema_name;
		EXECUTE format('ALTER SCHEMA %I RENAME TO %I;', current_schema_name, new_schema_name);
	END IF;
END
$$;


ALTER FUNCTION rp_master.rename_schema(current_schema_name text, new_schema_name text) OWNER TO edulog;

--
-- Name: replace_schema(text, text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.replace_schema(source_schema text, dest_schema text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	EXECUTE format('DROP SCHEMA IF EXISTS %I CASCADE', dest_schema);
	PERFORM rp_master.clone_schema(source_schema, dest_schema);
END
$$;


ALTER FUNCTION rp_master.replace_schema(source_schema text, dest_schema text) OWNER TO edulog;

--
-- Name: rolling_rename_data_area_schemas(bigint[]); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.rolling_rename_data_area_schemas(data_area_ids bigint[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	data_area_schema_lists TEXT[][];
	from_data_area_index INTEGER;
	to_data_area_index INTEGER;
	schema_index INTEGER;
	from_schema TEXT;
	to_schema TEXT;
BEGIN

	data_area_schema_lists = rp_master.get_schemas_for_data_area_list(data_area_ids);
	RAISE NOTICE 'Rolling data area schemas: %', data_area_schema_lists;

	from_data_area_index = array_upper(data_area_schema_lists, 1);
	LOOP
	EXIT WHEN from_data_area_index <= array_lower(data_area_schema_lists, 1);
		to_data_area_index := from_data_area_index;
		from_data_area_index := from_data_area_index - 1;
		
		schema_index = array_lower(data_area_schema_lists, 2);
		LOOP
		EXIT WHEN schema_index > array_upper(data_area_schema_lists, 2);
			from_schema = data_area_schema_lists[from_data_area_index][schema_index];
			to_schema = data_area_schema_lists[to_data_area_index][schema_index];
			RAISE NOTICE 'Renaming schema % to %', from_schema, to_schema;
			EXECUTE format('ALTER SCHEMA %I RENAME TO %I;', from_schema, to_schema);
			schema_index = schema_index + 1;
		END LOOP;
	END LOOP;

END
$$;


ALTER FUNCTION rp_master.rolling_rename_data_area_schemas(data_area_ids bigint[]) OWNER TO edulog;

--
-- Name: rollover_data_areas(); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.rollover_data_areas() RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
   data_area_ids BIGINT[];
   first_data_area TEXT;
   second_data_area TEXT;
   last_data_area TEXT;
BEGIN
	data_area_ids := ARRAY(SELECT id FROM rp_master.data_area WHERE rolling_seq IS NOT NULL ORDER BY rolling_seq);
	PERFORM rp_master.rollover_data_areas(data_area_ids, true);
	RETURN true;
END
$$;


ALTER FUNCTION rp_master.rollover_data_areas() OWNER TO edulog;

--
-- Name: rollover_data_areas(bigint[], boolean); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.rollover_data_areas(data_area_ids bigint[], recreate_initial_area boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
   first_data_area_id BIGINT;
   second_data_area_id BIGINT;
   last_data_area_id BIGINT;
BEGIN

	IF COALESCE(array_length(data_area_ids, 1), 0) > 1 THEN
	
		first_data_area_id = data_area_ids[array_lower(data_area_ids, 1)];
		second_data_area_id = data_area_ids[array_lower(data_area_ids, 1) + 1];
		last_data_area_id = data_area_ids[array_upper(data_area_ids, 1)];
		
		PERFORM rp_master.drop_data_area_schemas(last_data_area_id);
		PERFORM rp_master.rolling_rename_data_area_schemas(data_area_ids);
		
		IF recreate_initial_area THEN
			PERFORM rp_master.clone_data_area(second_data_area_id, first_data_area_id);
		END IF;
		
	END IF;
END
$$;


ALTER FUNCTION rp_master.rollover_data_areas(data_area_ids bigint[], recreate_initial_area boolean) OWNER TO edulog;

--
-- Name: validate_data_area_schema(text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.validate_data_area_schema(data_area_schema_name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	validated_data_area_schema_name TEXT;
	all_data_area_schemas TEXT[];
	all_schema_names TEXT[];
BEGIN

	--Data area schema name must be transformed to lower case
	validated_data_area_schema_name = LOWER(data_area_schema_name);
	--Load all schemas used by data areas
	all_data_area_schemas := ARRAY(
		SELECT rp_schema AS data_area_schema FROM rp_master.data_area
		UNION
		SELECT geo_schema AS data_area_schema FROM rp_master.data_area);
	--Load all schemas in the database
	all_schema_names := ARRAY(SELECT nspname::TEXT FROM pg_catalog.pg_namespace);

	IF validated_data_area_schema_name = '' THEN
		RAISE EXCEPTION 'Data Area schema name cannot be empty.';
	ELSIF validated_data_area_schema_name ~ '^(pg_).+' THEN
		RAISE EXCEPTION 'Data Area schema name cannot start with "pg_" (system reserved): %', validated_data_area_schema_name;
	ELSIF NOT validated_data_area_schema_name ~ '[a-z0-9_]+' THEN
		RAISE EXCEPTION 'Data Area schema name contains invalid characters (may only contain alphanumeric characters and underscores): %', validated_data_area_schema_name;
	ELSIF validated_data_area_schema_name = ANY(all_data_area_schemas) THEN
		RAISE EXCEPTION 'Schema name already in use by another data area: %', validated_data_area_schema_name;
	ELSIF validated_data_area_schema_name = ANY(all_schema_names) THEN
		RAISE EXCEPTION 'Schema name already in use by system: %', validated_data_area_schema_name;
	END IF;
	
	RETURN validated_data_area_schema_name;
	
END
$$;


ALTER FUNCTION rp_master.validate_data_area_schema(data_area_schema_name text) OWNER TO edulog;

--
-- Name: validate_data_area_schemas(text, text); Type: FUNCTION; Schema: rp_master; Owner: edulog
--

CREATE FUNCTION rp_master.validate_data_area_schemas(INOUT rp_schema_name text, INOUT geo_schema_name text) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
	
	SELECT rp_master.validate_data_area_schema(rp_schema_name) INTO rp_schema_name;
	SELECT rp_master.validate_data_area_schema(geo_schema_name) INTO geo_schema_name;

	IF rp_schema_name = geo_schema_name THEN
		RAISE EXCEPTION 'Input schema names must be unique: %', rp_schema;
	END IF;

END
$$;


ALTER FUNCTION rp_master.validate_data_area_schemas(INOUT rp_schema_name text, INOUT geo_schema_name text) OWNER TO edulog;

--
-- Name: array_cat_agg(anyarray); Type: AGGREGATE; Schema: edta; Owner: edulog
--

CREATE AGGREGATE edta.array_cat_agg(anyarray) (
    SFUNC = array_cat,
    STYPE = anyarray
);


ALTER AGGREGATE edta.array_cat_agg(anyarray) OWNER TO edulog;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.activity (
    id bigint NOT NULL,
    code integer NOT NULL,
    name_of character varying(50) NOT NULL
);


ALTER TABLE edta.activity OWNER TO edulog;

--
-- Name: activity_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.activity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.activity_id_seq OWNER TO edulog;

--
-- Name: activity_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.activity_id_seq OWNED BY edta.activity.id;


--
-- Name: billing_type; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.billing_type (
    id bigint NOT NULL,
    code character varying(15) NOT NULL,
    name_of character varying(50) NOT NULL
);


ALTER TABLE edta.billing_type OWNER TO edulog;

--
-- Name: billing_type_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.billing_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.billing_type_id_seq OWNER TO edulog;

--
-- Name: billing_type_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.billing_type_id_seq OWNED BY edta.billing_type.id;


--
-- Name: certification; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.certification (
    id bigint NOT NULL,
    type_of character varying(40) NOT NULL,
    no_of character varying(10) NOT NULL,
    description character varying(60),
    iss_date date NOT NULL,
    exp_date date,
    comment character varying(500),
    driver_info_id bigint
);


ALTER TABLE edta.certification OWNER TO edulog;

--
-- Name: certification_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.certification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.certification_id_seq OWNER TO edulog;

--
-- Name: certification_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.certification_id_seq OWNED BY edta.certification.id;


--
-- Name: department; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.department (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL
);


ALTER TABLE edta.department OWNER TO edulog;

--
-- Name: department_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.department_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.department_id_seq OWNER TO edulog;

--
-- Name: department_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.department_id_seq OWNED BY edta.department.id;


--
-- Name: district; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.district (
    id bigint NOT NULL,
    name_of character varying(6) NOT NULL
);


ALTER TABLE edta.district OWNER TO edulog;

--
-- Name: district_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.district_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.district_id_seq OWNER TO edulog;

--
-- Name: district_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.district_id_seq OWNED BY edta.district.id;


--
-- Name: driver_class; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.driver_class (
    id bigint NOT NULL,
    name_of character varying(20) NOT NULL
);


ALTER TABLE edta.driver_class OWNER TO edulog;

--
-- Name: driver_class_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.driver_class_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.driver_class_id_seq OWNER TO edulog;

--
-- Name: driver_class_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.driver_class_id_seq OWNED BY edta.driver_class.id;


--
-- Name: driver_info; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.driver_info (
    id bigint NOT NULL,
    employee_id character varying(20) NOT NULL,
    initial character varying(25),
    first_name character varying(25) NOT NULL,
    last_name character varying(25) NOT NULL,
    birth_day date,
    is_temporary boolean,
    work_phone character varying(25),
    home_phone character varying(25),
    email character varying(50),
    description character varying(50),
    note character varying(500),
    is_active boolean,
    no_of character varying(20),
    state_code_license character varying(2),
    expire date,
    driver_district_id character varying(20),
    fuel_card character varying(10),
    call_board character varying(10),
    retriction character varying(500),
    address character varying(50),
    state_code_contact character varying(2),
    city character varying(30),
    zip character varying(21),
    employer character varying(15),
    supervisor character varying(25),
    date_hire date,
    date_terminated date,
    sequence_number character varying(12),
    type_of character varying(10),
    frequency character varying(10),
    rate numeric,
    per character varying(10),
    leave_rate numeric,
    emergency_contact_name character varying(50),
    emergency_address character varying(50),
    relation character varying(50),
    license_class_id bigint,
    driver_class_id bigint,
    union_id bigint,
    seniority_id bigint,
    district_id bigint,
    emp_class_id bigint,
    grade_id bigint,
    level_id bigint,
    emp_group_id bigint,
    scale_hour_id bigint,
    billing_type_id bigint,
    department_id bigint,
    work_group_id bigint
);


ALTER TABLE edta.driver_info OWNER TO edulog;

--
-- Name: driver_info_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.driver_info_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.driver_info_id_seq OWNER TO edulog;

--
-- Name: driver_info_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.driver_info_id_seq OWNED BY edta.driver_info.id;


--
-- Name: driver_skill; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.driver_skill (
    driver_info_id bigint NOT NULL,
    skill_id integer NOT NULL
);


ALTER TABLE edta.driver_skill OWNER TO edulog;

--
-- Name: emp_class; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.emp_class (
    id bigint NOT NULL,
    name_of character varying(15) NOT NULL
);


ALTER TABLE edta.emp_class OWNER TO edulog;

--
-- Name: emp_class_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.emp_class_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.emp_class_id_seq OWNER TO edulog;

--
-- Name: emp_class_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.emp_class_id_seq OWNED BY edta.emp_class.id;


--
-- Name: emp_group; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.emp_group (
    id bigint NOT NULL,
    name_of character varying(30) NOT NULL
);


ALTER TABLE edta.emp_group OWNER TO edulog;

--
-- Name: emp_group_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.emp_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.emp_group_id_seq OWNER TO edulog;

--
-- Name: emp_group_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.emp_group_id_seq OWNED BY edta.emp_group.id;


--
-- Name: grade; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.grade (
    id bigint NOT NULL,
    name_of character varying(10) NOT NULL
);


ALTER TABLE edta.grade OWNER TO edulog;

--
-- Name: grade_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.grade_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.grade_id_seq OWNER TO edulog;

--
-- Name: grade_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.grade_id_seq OWNED BY edta.grade.id;


--
-- Name: image; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.image (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL,
    type_of character varying(50) NOT NULL,
    data bytea NOT NULL,
    driver_info_id bigint NOT NULL
);


ALTER TABLE edta.image OWNER TO edulog;

--
-- Name: image_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.image_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.image_id_seq OWNER TO edulog;

--
-- Name: image_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.image_id_seq OWNED BY edta.image.id;


--
-- Name: level; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.level (
    id bigint NOT NULL,
    name_of character varying(10) NOT NULL
);


ALTER TABLE edta.level OWNER TO edulog;

--
-- Name: level_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.level_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.level_id_seq OWNER TO edulog;

--
-- Name: level_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.level_id_seq OWNED BY edta.level.id;


--
-- Name: license_class; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.license_class (
    id bigint NOT NULL,
    name_of character varying(10) NOT NULL
);


ALTER TABLE edta.license_class OWNER TO edulog;

--
-- Name: license_class_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.license_class_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.license_class_id_seq OWNER TO edulog;

--
-- Name: license_class_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.license_class_id_seq OWNED BY edta.license_class.id;


--
-- Name: ridership; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.ridership (
    id bigint NOT NULL,
    log_date date,
    edulog_id integer,
    route character varying(10),
    run character varying(10),
    ts_pu_ac_bus character varying(10),
    ts_pu_ac_driver character varying(50),
    ts_pu_ac_stopid character varying(10),
    ts_pu_ac_stoptime timestamp without time zone,
    ts_pu_ac_desc character varying(100),
    ts_pu_ac_status character varying(20),
    ts_pu_ac_latlong character varying(50),
    ts_pu_pl_bus character varying(10),
    ts_pu_pl_stopid character varying(10),
    ts_pu_pl_stoptime timestamp without time zone,
    ts_pu_pl_desc character varying(100),
    ts_do_ac_schoolname character varying(100),
    ts_do_ac_arrivaltime timestamp without time zone,
    ts_do_ac_status character varying(20),
    ts_do_ac_latlong character varying(50),
    ts_do_pl_schoolname character varying(100),
    ts_do_pl_arrivaltime timestamp without time zone,
    fs_pu_ac_bus character varying(10),
    fs_pu_ac_driver character varying(50),
    fs_pu_ac_schoolcode character varying(50),
    fs_pu_ac_departtime timestamp without time zone,
    fs_pu_ac_schoolname character varying(100),
    fs_pu_ac_status character varying(20),
    fs_pu_ac_latlong character varying(50),
    fs_pu_pl_schoolcode character varying(50),
    fs_pu_pl_departtime timestamp without time zone,
    fs_pu_pl_schoolname character varying(100),
    fs_do_ac_stopid character varying(50),
    fs_do_ac_stoptime timestamp without time zone,
    fs_do_ac_desc character varying(100),
    fs_do_ac_status character varying(20),
    fs_do_ac_latlong character varying(50),
    fs_do_pl_stopid character varying(50),
    fs_do_pl_stoptime timestamp without time zone,
    fs_do_pl_desc character varying(100)
);


ALTER TABLE edta.ridership OWNER TO edulog;

--
-- Name: ridership_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.ridership_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.ridership_id_seq OWNER TO edulog;

--
-- Name: ridership_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.ridership_id_seq OWNED BY edta.ridership.id;


--
-- Name: scale_hour; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.scale_hour (
    id bigint NOT NULL,
    value_of numeric NOT NULL
);


ALTER TABLE edta.scale_hour OWNER TO edulog;

--
-- Name: scale_hour_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.scale_hour_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.scale_hour_id_seq OWNER TO edulog;

--
-- Name: scale_hour_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.scale_hour_id_seq OWNED BY edta.scale_hour.id;


--
-- Name: search; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.search (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL,
    is_last boolean,
    is_append boolean,
    search_json character varying(5000) NOT NULL,
    driver_info_id bigint
);


ALTER TABLE edta.search OWNER TO edulog;

--
-- Name: search_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.search_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.search_id_seq OWNER TO edulog;

--
-- Name: search_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.search_id_seq OWNED BY edta.search.id;


--
-- Name: seniority; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.seniority (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL
);


ALTER TABLE edta.seniority OWNER TO edulog;

--
-- Name: seniority_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.seniority_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.seniority_id_seq OWNER TO edulog;

--
-- Name: seniority_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.seniority_id_seq OWNED BY edta.seniority.id;


--
-- Name: skill; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.skill (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL
);


ALTER TABLE edta.skill OWNER TO edulog;

--
-- Name: skill_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.skill_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.skill_id_seq OWNER TO edulog;

--
-- Name: skill_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.skill_id_seq OWNED BY edta.skill.id;


--
-- Name: state; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.state (
    code character varying(2) NOT NULL,
    description character varying(50) NOT NULL
);


ALTER TABLE edta.state OWNER TO edulog;

--
-- Name: student; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.student (
    id integer NOT NULL,
    edulogid integer,
    firstname character varying(25) NOT NULL,
    lastname character varying(25) NOT NULL,
    school character varying(8),
    grade character varying(4),
    program character varying(50),
    district character varying(32),
    rfid character varying(10)
);


ALTER TABLE edta.student OWNER TO edulog;

--
-- Name: student_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

ALTER TABLE edta.student ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME edta.student_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: training; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.training (
    id bigint NOT NULL,
    type_of character varying(15) NOT NULL,
    class_of character varying(40),
    start_date date NOT NULL,
    end_date date NOT NULL,
    repeat character varying(1),
    frequency integer,
    driver_info_id bigint
);


ALTER TABLE edta.training OWNER TO edulog;

--
-- Name: training_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.training_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.training_id_seq OWNER TO edulog;

--
-- Name: training_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.training_id_seq OWNED BY edta.training.id;


--
-- Name: transaction; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.transaction (
    id bigint NOT NULL,
    date_of timestamp without time zone NOT NULL,
    login timestamp without time zone,
    logout timestamp without time zone,
    pay_period character varying(50),
    supervisor character varying(50),
    status character varying(50) NOT NULL,
    comment character varying(500),
    record_time timestamp without time zone NOT NULL,
    created_by character varying(100),
    vehicle_id character varying(10),
    source_type character varying(20),
    parent_id bigint,
    driver_info_id bigint NOT NULL,
    billing_type_id bigint,
    activity_id bigint
);


ALTER TABLE edta.transaction OWNER TO edulog;

--
-- Name: transaction_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.transaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.transaction_id_seq OWNER TO edulog;

--
-- Name: transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.transaction_id_seq OWNED BY edta.transaction.id;


--
-- Name: union; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta."union" (
    id bigint NOT NULL,
    name_of character varying(30) NOT NULL
);


ALTER TABLE edta."union" OWNER TO edulog;

--
-- Name: union_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.union_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.union_id_seq OWNER TO edulog;

--
-- Name: union_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.union_id_seq OWNED BY edta."union".id;


--
-- Name: v_transaction; Type: VIEW; Schema: edta; Owner: edulog
--

CREATE VIEW edta.v_transaction AS
 SELECT round(((date_part('epoch'::text, (date_trunc('minute'::text, t.logout) - date_trunc('minute'::text, t.login))) / (3600)::double precision))::numeric, 2) AS work_time,
    to_char((date_trunc('minute'::text, t.logout) - date_trunc('minute'::text, t.login)), 'HH24:MI'::text) AS duration,
    t.id,
    t.date_of,
    t.login,
    t.logout,
    t.pay_period,
    t.supervisor,
    t.status,
    t.comment,
    t.record_time,
    t.created_by,
    t.vehicle_id,
    t.source_type,
    t.parent_id,
    t.driver_info_id,
    t.billing_type_id,
    t.activity_id
   FROM edta.transaction t
  ORDER BY t.id;


ALTER TABLE edta.v_transaction OWNER TO edulog;

--
-- Name: v_current_trecord; Type: VIEW; Schema: edta; Owner: edulog
--

CREATE VIEW edta.v_current_trecord AS
 WITH max_id AS (
         SELECT max(transaction.id) AS max_id,
            count(*) AS total_record
           FROM edta.transaction
          GROUP BY COALESCE(transaction.parent_id, transaction.id)
        )
 SELECT t.work_time,
    t.duration,
    t.id,
    t.date_of,
    t.login,
    t.logout,
    t.pay_period,
    t.supervisor,
    t.status,
    t.comment,
    t.record_time,
    t.created_by,
    t.vehicle_id,
    t.source_type,
    t.parent_id,
    t.driver_info_id,
    t.billing_type_id,
    t.activity_id,
    m.max_id,
    m.total_record
   FROM (edta.v_transaction t
     JOIN max_id m ON ((t.id = m.max_id)))
  ORDER BY t.id;


ALTER TABLE edta.v_current_trecord OWNER TO edulog;

--
-- Name: v_current_trecord_for_driver; Type: VIEW; Schema: edta; Owner: edulog
--

CREATE VIEW edta.v_current_trecord_for_driver AS
 WITH max_id AS (
         SELECT max(transaction.id) AS max_id,
            count(*) AS total_record
           FROM edta.transaction
          WHERE (lower((transaction.status)::text) = ANY (ARRAY['initial'::text, 'driver change request'::text, 'driver approved'::text, 'for driver approval'::text, 'supervisor approved'::text]))
          GROUP BY COALESCE(transaction.parent_id, transaction.id)
        )
 SELECT t.work_time,
    t.duration,
    t.id,
    t.date_of,
    t.login,
    t.logout,
    t.pay_period,
    t.supervisor,
    t.status,
    t.comment,
    t.record_time,
    t.created_by,
    t.vehicle_id,
    t.source_type,
    t.parent_id,
    t.driver_info_id,
    t.billing_type_id,
    t.activity_id,
    m.max_id,
    m.total_record
   FROM (edta.v_transaction t
     JOIN max_id m ON ((t.id = m.max_id)))
  ORDER BY t.id;


ALTER TABLE edta.v_current_trecord_for_driver OWNER TO edulog;

--
-- Name: v_daily_summary_on_current_trecord; Type: VIEW; Schema: edta; Owner: edulog
--

CREATE VIEW edta.v_daily_summary_on_current_trecord AS
 SELECT
        CASE
            WHEN ("position"(string_agg(DISTINCT (v_current_trecord.status)::text, ', '::text), ','::text) = 0) THEN string_agg(DISTINCT (v_current_trecord.status)::text, ''::text)
            ELSE 'Mixed'::text
        END AS status,
    v_current_trecord.driver_info_id,
    v_current_trecord.date_of,
    v_current_trecord.billing_type_id,
    v_current_trecord.activity_id,
    v_current_trecord.pay_period,
    v_current_trecord.supervisor,
    count(*) AS total_record,
    sum(v_current_trecord.work_time) AS work_time,
    array_agg(v_current_trecord.max_id) AS group_id,
    md5(((((((v_current_trecord.driver_info_id)::text || (v_current_trecord.date_of)::text) || (v_current_trecord.billing_type_id)::text) || (v_current_trecord.activity_id)::text) || (v_current_trecord.pay_period)::text) || (COALESCE(v_current_trecord.supervisor, ''::character varying))::text)) AS group_key,
    md5((((v_current_trecord.driver_info_id)::text || (v_current_trecord.date_of)::text) || (row_number() OVER (PARTITION BY v_current_trecord.driver_info_id, v_current_trecord.date_of ORDER BY v_current_trecord.driver_info_id, v_current_trecord.date_of))::text)) AS group_order
   FROM edta.v_current_trecord
  GROUP BY v_current_trecord.driver_info_id, v_current_trecord.date_of, v_current_trecord.billing_type_id, v_current_trecord.activity_id, v_current_trecord.pay_period, v_current_trecord.supervisor;


ALTER TABLE edta.v_daily_summary_on_current_trecord OWNER TO edulog;

--
-- Name: v_daily_total_on_daily_summary; Type: VIEW; Schema: edta; Owner: edulog
--

CREATE VIEW edta.v_daily_total_on_daily_summary AS
 SELECT
        CASE
            WHEN ("position"(string_agg(DISTINCT v_daily_summary_on_current_trecord.status, ', '::text), ','::text) = 0) THEN string_agg(DISTINCT v_daily_summary_on_current_trecord.status, ''::text)
            ELSE 'Mixed'::text
        END AS status,
    v_daily_summary_on_current_trecord.driver_info_id,
    v_daily_summary_on_current_trecord.date_of,
    v_daily_summary_on_current_trecord.pay_period,
    v_daily_summary_on_current_trecord.supervisor,
    count(*) AS total_record,
    sum(v_daily_summary_on_current_trecord.work_time) AS work_time,
    edta.array_cat_agg(v_daily_summary_on_current_trecord.group_id) AS group_id,
    md5(((((v_daily_summary_on_current_trecord.driver_info_id)::text || (v_daily_summary_on_current_trecord.date_of)::text) || (v_daily_summary_on_current_trecord.pay_period)::text) || (COALESCE(v_daily_summary_on_current_trecord.supervisor, ''::character varying))::text)) AS group_key,
    md5((((v_daily_summary_on_current_trecord.driver_info_id)::text || (v_daily_summary_on_current_trecord.date_of)::text) || (row_number() OVER (PARTITION BY v_daily_summary_on_current_trecord.driver_info_id, v_daily_summary_on_current_trecord.date_of ORDER BY v_daily_summary_on_current_trecord.driver_info_id, v_daily_summary_on_current_trecord.date_of))::text)) AS group_order
   FROM edta.v_daily_summary_on_current_trecord
  GROUP BY v_daily_summary_on_current_trecord.driver_info_id, v_daily_summary_on_current_trecord.date_of, v_daily_summary_on_current_trecord.pay_period, v_daily_summary_on_current_trecord.supervisor;


ALTER TABLE edta.v_daily_total_on_daily_summary OWNER TO edulog;

--
-- Name: v_pay_period_on_daily_total; Type: VIEW; Schema: edta; Owner: edulog
--

CREATE VIEW edta.v_pay_period_on_daily_total AS
 SELECT
        CASE
            WHEN ("position"(string_agg(DISTINCT v_daily_total_on_daily_summary.status, ', '::text), ','::text) = 0) THEN string_agg(DISTINCT v_daily_total_on_daily_summary.status, ''::text)
            ELSE 'Mixed'::text
        END AS status,
    v_daily_total_on_daily_summary.driver_info_id,
    v_daily_total_on_daily_summary.pay_period,
    v_daily_total_on_daily_summary.supervisor,
    count(*) AS total_record,
    sum(v_daily_total_on_daily_summary.work_time) AS work_time,
    edta.array_cat_agg(v_daily_total_on_daily_summary.group_id) AS group_id,
    md5((((v_daily_total_on_daily_summary.driver_info_id)::text || (v_daily_total_on_daily_summary.pay_period)::text) || (COALESCE(v_daily_total_on_daily_summary.supervisor, ''::character varying))::text)) AS group_key,
    md5(((v_daily_total_on_daily_summary.driver_info_id)::text || (row_number() OVER (PARTITION BY v_daily_total_on_daily_summary.driver_info_id ORDER BY v_daily_total_on_daily_summary.driver_info_id))::text)) AS group_order
   FROM edta.v_daily_total_on_daily_summary
  GROUP BY v_daily_total_on_daily_summary.driver_info_id, v_daily_total_on_daily_summary.pay_period, v_daily_total_on_daily_summary.supervisor;


ALTER TABLE edta.v_pay_period_on_daily_total OWNER TO edulog;

--
-- Name: work_group; Type: TABLE; Schema: edta; Owner: edulog
--

CREATE TABLE edta.work_group (
    id bigint NOT NULL,
    name_of character varying(30) NOT NULL
);


ALTER TABLE edta.work_group OWNER TO edulog;

--
-- Name: work_group_id_seq; Type: SEQUENCE; Schema: edta; Owner: edulog
--

CREATE SEQUENCE edta.work_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE edta.work_group_id_seq OWNER TO edulog;

--
-- Name: work_group_id_seq; Type: SEQUENCE OWNED BY; Schema: edta; Owner: edulog
--

ALTER SEQUENCE edta.work_group_id_seq OWNED BY edta.work_group.id;


--
-- Name: config; Type: TABLE; Schema: geo_master; Owner: edulog
--

CREATE TABLE geo_master.config (
    id bigint NOT NULL,
    application character varying(128) NOT NULL,
    setting character varying(128) NOT NULL,
    value character varying(128) NOT NULL,
    description character varying(128) NOT NULL
);


ALTER TABLE geo_master.config OWNER TO edulog;

--
-- Name: config_id_seq; Type: SEQUENCE; Schema: geo_master; Owner: edulog
--

CREATE SEQUENCE geo_master.config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_master.config_id_seq OWNER TO edulog;

--
-- Name: config_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_master; Owner: edulog
--

ALTER SEQUENCE geo_master.config_id_seq OWNED BY geo_master.config.id;


--
-- Name: geoserver_layer; Type: TABLE; Schema: geo_master; Owner: edulog
--

CREATE TABLE geo_master.geoserver_layer (
    id bigint NOT NULL,
    display_name character varying(60) NOT NULL,
    display_order integer NOT NULL,
    description character varying(1600)
);


ALTER TABLE geo_master.geoserver_layer OWNER TO edulog;

--
-- Name: geoserver_layer_id_seq; Type: SEQUENCE; Schema: geo_master; Owner: edulog
--

CREATE SEQUENCE geo_master.geoserver_layer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_master.geoserver_layer_id_seq OWNER TO edulog;

--
-- Name: geoserver_layer_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_master; Owner: edulog
--

ALTER SEQUENCE geo_master.geoserver_layer_id_seq OWNED BY geo_master.geoserver_layer.id;


--
-- Name: address; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.address (
    id bigint NOT NULL,
    location_id integer NOT NULL,
    number_of integer NOT NULL,
    number_of_suffix character varying(4),
    alpha character varying(32),
    contact character varying(24)
);


ALTER TABLE geo_plan.address OWNER TO edulog;

--
-- Name: address_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.address_id_seq OWNER TO edulog;

--
-- Name: address_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.address_id_seq OWNED BY geo_plan.address.id;


--
-- Name: adj_except; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.adj_except (
    id bigint NOT NULL,
    from_segment_id integer NOT NULL,
    from_right_side boolean NOT NULL,
    to_segment_id integer,
    to_right_side boolean
);


ALTER TABLE geo_plan.adj_except OWNER TO edulog;

--
-- Name: adj_except_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.adj_except_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.adj_except_id_seq OWNER TO edulog;

--
-- Name: adj_except_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.adj_except_id_seq OWNED BY geo_plan.adj_except.id;


--
-- Name: boundary; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.boundary (
    id bigint NOT NULL,
    code character varying(32) NOT NULL,
    import_id character varying(36),
    description character varying(60) NOT NULL,
    notes character varying(100) NOT NULL,
    locked boolean,
    time_changed timestamp(3) without time zone NOT NULL,
    geo public.geography NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


ALTER TABLE geo_plan.boundary OWNER TO edulog;

--
-- Name: boundary_group; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.boundary_group (
    id bigint NOT NULL,
    code character varying(32) NOT NULL,
    description character varying(60)
);


ALTER TABLE geo_plan.boundary_group OWNER TO edulog;

--
-- Name: boundary_group_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.boundary_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.boundary_group_id_seq OWNER TO edulog;

--
-- Name: boundary_group_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.boundary_group_id_seq OWNED BY geo_plan.boundary_group.id;


--
-- Name: boundary_group_mapping; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.boundary_group_mapping (
    boundary_id bigint NOT NULL,
    boundary_group_id bigint NOT NULL,
    posted integer
);


ALTER TABLE geo_plan.boundary_group_mapping OWNER TO edulog;

--
-- Name: boundary_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.boundary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.boundary_id_seq OWNER TO edulog;

--
-- Name: boundary_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.boundary_id_seq OWNED BY geo_plan.boundary.id;


--
-- Name: export_file; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.export_file (
    id bigint NOT NULL,
    file_name character varying(30) NOT NULL,
    url_file character varying(250),
    status character varying(30),
    percent integer,
    time_created timestamp without time zone,
    time_changed timestamp without time zone,
    type character varying(30)
);


ALTER TABLE geo_plan.export_file OWNER TO edulog;

--
-- Name: export_file_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.export_file_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.export_file_id_seq OWNER TO edulog;

--
-- Name: export_file_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.export_file_id_seq OWNED BY geo_plan.export_file.id;


--
-- Name: landmark; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.landmark (
    id bigint NOT NULL,
    location_id integer NOT NULL,
    name_of character varying(60) NOT NULL,
    alt_name character varying(60),
    type_of character varying(32) NOT NULL
);


ALTER TABLE geo_plan.landmark OWNER TO edulog;

--
-- Name: landmark_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.landmark_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.landmark_id_seq OWNER TO edulog;

--
-- Name: landmark_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.landmark_id_seq OWNED BY geo_plan.landmark.id;


--
-- Name: legal_description; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.legal_description (
    id bigint NOT NULL,
    location_id integer NOT NULL,
    meridian character varying(40) NOT NULL,
    township character varying(4) NOT NULL,
    range_of character varying(4) NOT NULL,
    section_of character varying(2) NOT NULL,
    section_of_div character varying(16) NOT NULL
);


ALTER TABLE geo_plan.legal_description OWNER TO edulog;

--
-- Name: legal_description_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.legal_description_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.legal_description_id_seq OWNER TO edulog;

--
-- Name: legal_description_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.legal_description_id_seq OWNED BY geo_plan.legal_description.id;


--
-- Name: location; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.location (
    id bigint NOT NULL,
    import_id character varying(36),
    street_segment_id integer,
    right_side boolean NOT NULL,
    percent_along double precision,
    notes character varying(140),
    orig_geo public.geography NOT NULL,
    calc_geo public.geography NOT NULL,
    opt_geo public.geography,
    source_of character varying(200),
    external_address character varying(200),
    effect_from_date timestamp without time zone,
    effect_to_date timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    changed boolean,
    deleted boolean
);


ALTER TABLE geo_plan.location OWNER TO edulog;

--
-- Name: location_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.location_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.location_id_seq OWNER TO edulog;

--
-- Name: location_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.location_id_seq OWNED BY geo_plan.location.id;


--
-- Name: mile_marker; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.mile_marker (
    id bigint NOT NULL,
    location_id integer NOT NULL,
    percent_along double precision NOT NULL,
    address_number integer
);


ALTER TABLE geo_plan.mile_marker OWNER TO edulog;

--
-- Name: mile_marker_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.mile_marker_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.mile_marker_id_seq OWNER TO edulog;

--
-- Name: mile_marker_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.mile_marker_id_seq OWNED BY geo_plan.mile_marker.id;


--
-- Name: node; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.node (
    id bigint NOT NULL,
    geo public.geography,
    CONSTRAINT limitnodeidforfrontend CHECK ((id <= '9007199254740991'::bigint))
);


ALTER TABLE geo_plan.node OWNER TO edulog;

--
-- Name: node_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.node_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.node_id_seq OWNER TO edulog;

--
-- Name: node_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.node_id_seq OWNED BY geo_plan.node.id;


--
-- Name: parsing; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.parsing (
    id bigint NOT NULL,
    type_of character varying(8),
    accept character varying(40),
    fix character varying(40)
);


ALTER TABLE geo_plan.parsing OWNER TO edulog;

--
-- Name: parsing_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.parsing_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.parsing_id_seq OWNER TO edulog;

--
-- Name: parsing_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.parsing_id_seq OWNED BY geo_plan.parsing.id;


--
-- Name: segment; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.segment (
    id bigint NOT NULL,
    hazard1 boolean NOT NULL,
    hazard2 boolean NOT NULL,
    hazard3 boolean NOT NULL,
    hazard4 boolean NOT NULL,
    from_flow boolean NOT NULL,
    to_flow boolean NOT NULL,
    walk_across boolean NOT NULL,
    from_node bigint NOT NULL,
    to_node bigint NOT NULL,
    width double precision,
    left_zip_code character varying(9),
    left_community character varying(32),
    left_speed1 smallint NOT NULL,
    left_speed2 smallint NOT NULL,
    left_speed3 smallint NOT NULL,
    left_speed4 smallint NOT NULL,
    left_speed5 smallint NOT NULL,
    left_speed6 smallint NOT NULL,
    left_posted_speed smallint NOT NULL,
    left_drive boolean NOT NULL,
    left_walk1 boolean NOT NULL,
    left_walk2 boolean NOT NULL,
    left_walk3 boolean NOT NULL,
    left_walk4 boolean NOT NULL,
    right_zip_code character varying(9),
    right_community character varying(32),
    right_speed1 smallint NOT NULL,
    right_speed2 smallint NOT NULL,
    right_speed3 smallint NOT NULL,
    right_speed4 smallint NOT NULL,
    right_speed5 smallint NOT NULL,
    right_speed6 smallint NOT NULL,
    right_posted_speed smallint NOT NULL,
    right_drive boolean NOT NULL,
    right_walk1 boolean NOT NULL,
    right_walk2 boolean NOT NULL,
    right_walk3 boolean NOT NULL,
    right_walk4 boolean NOT NULL,
    base_id integer,
    start_date timestamp(3) without time zone,
    end_date timestamp(3) without time zone,
    geo public.geography NOT NULL,
    geom_geoserver public.geometry NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE geo_plan.segment OWNER TO edulog;

--
-- Name: segment_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.segment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.segment_id_seq OWNER TO edulog;

--
-- Name: segment_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.segment_id_seq OWNED BY geo_plan.segment.id;


--
-- Name: street; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.street (
    id bigint NOT NULL,
    prefix_of character varying(2),
    name_of character varying(60),
    type_of character varying(4),
    suffix character varying(2)
);


ALTER TABLE geo_plan.street OWNER TO edulog;

--
-- Name: street_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.street_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.street_id_seq OWNER TO edulog;

--
-- Name: street_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.street_id_seq OWNED BY geo_plan.street.id;


--
-- Name: street_segment; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.street_segment (
    id bigint NOT NULL,
    street_id integer NOT NULL,
    segment_id integer NOT NULL,
    left_from_address integer NOT NULL,
    left_to_address integer NOT NULL,
    right_from_address integer NOT NULL,
    right_to_address integer NOT NULL,
    feature_class character varying(5) NOT NULL,
    primary_segment boolean NOT NULL,
    reversed_geo boolean NOT NULL
);


ALTER TABLE geo_plan.street_segment OWNER TO edulog;

--
-- Name: street_segment_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.street_segment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.street_segment_id_seq OWNER TO edulog;

--
-- Name: street_segment_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.street_segment_id_seq OWNED BY geo_plan.street_segment.id;


--
-- Name: zipcode; Type: TABLE; Schema: geo_plan; Owner: edulog
--

CREATE TABLE geo_plan.zipcode (
    id bigint NOT NULL,
    zip character varying(9) NOT NULL,
    city character varying(30)
);


ALTER TABLE geo_plan.zipcode OWNER TO edulog;

--
-- Name: zipcode_id_seq; Type: SEQUENCE; Schema: geo_plan; Owner: edulog
--

CREATE SEQUENCE geo_plan.zipcode_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE geo_plan.zipcode_id_seq OWNER TO edulog;

--
-- Name: zipcode_id_seq; Type: SEQUENCE OWNED BY; Schema: geo_plan; Owner: edulog
--

ALTER SEQUENCE geo_plan.zipcode_id_seq OWNED BY geo_plan.zipcode.id;


--
-- Name: i_type; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.i_type (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL
);


ALTER TABLE ivin.i_type OWNER TO edulog;

--
-- Name: i_type_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.i_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.i_type_id_seq OWNER TO edulog;

--
-- Name: i_type_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.i_type_id_seq OWNED BY ivin.i_type.id;


--
-- Name: i_zone; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.i_zone (
    id bigint NOT NULL,
    description character varying(100),
    image_id bigint
);


ALTER TABLE ivin.i_zone OWNER TO edulog;

--
-- Name: i_zone_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.i_zone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.i_zone_id_seq OWNER TO edulog;

--
-- Name: i_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.i_zone_id_seq OWNED BY ivin.i_zone.id;


--
-- Name: image; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.image (
    id bigint NOT NULL,
    name_of character varying(50) NOT NULL,
    type_of character varying(50) NOT NULL,
    data bytea NOT NULL
);


ALTER TABLE ivin.image OWNER TO edulog;

--
-- Name: image_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.image_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.image_id_seq OWNER TO edulog;

--
-- Name: image_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.image_id_seq OWNED BY ivin.image.id;


--
-- Name: inspection; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.inspection (
    id bigint NOT NULL,
    name_of character varying(50),
    vehicle_id character varying(25) NOT NULL,
    mdt_id character varying(50) NOT NULL,
    driver_id character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    first_name character varying(50) NOT NULL,
    date_of date NOT NULL,
    status character varying(50) NOT NULL,
    odometer numeric,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone NOT NULL,
    duration_second integer NOT NULL,
    avg_duration_second integer,
    defect integer,
    action_of character varying(100),
    unsafe boolean,
    reason character varying(100),
    modified_user character varying(100),
    modified_date timestamp without time zone,
    created_date timestamp without time zone,
    template_id integer NOT NULL
);


ALTER TABLE ivin.inspection OWNER TO edulog;

--
-- Name: inspection_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.inspection_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.inspection_id_seq OWNER TO edulog;

--
-- Name: inspection_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.inspection_id_seq OWNED BY ivin.inspection.id;


--
-- Name: inspection_point; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.inspection_point (
    id bigint NOT NULL,
    status character varying(10) NOT NULL,
    note character varying(100),
    inspection_zone_id bigint,
    template_point_id bigint NOT NULL,
    image_id bigint,
    template_point_validation_id bigint
);


ALTER TABLE ivin.inspection_point OWNER TO edulog;

--
-- Name: inspection_point_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.inspection_point_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.inspection_point_id_seq OWNER TO edulog;

--
-- Name: inspection_point_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.inspection_point_id_seq OWNED BY ivin.inspection_point.id;


--
-- Name: inspection_zone; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.inspection_zone (
    id bigint NOT NULL,
    status character varying(10) NOT NULL,
    inspection_id integer,
    i_zone_id integer NOT NULL
);


ALTER TABLE ivin.inspection_zone OWNER TO edulog;

--
-- Name: inspection_zone_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.inspection_zone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.inspection_zone_id_seq OWNER TO edulog;

--
-- Name: inspection_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.inspection_zone_id_seq OWNED BY ivin.inspection_zone.id;


--
-- Name: template; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.template (
    id bigint NOT NULL,
    name_of character varying(100) NOT NULL,
    status character varying(20),
    created_date_time timestamp without time zone,
    created_date date,
    created_by character varying(100),
    i_type_id integer NOT NULL
);


ALTER TABLE ivin.template OWNER TO edulog;

--
-- Name: template_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.template_id_seq OWNER TO edulog;

--
-- Name: template_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.template_id_seq OWNED BY ivin.template.id;


--
-- Name: template_point; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.template_point (
    id bigint NOT NULL,
    description character varying(100) NOT NULL,
    is_critical boolean,
    is_walk_around boolean,
    is_power_on boolean,
    template_zone_id bigint,
    image_id bigint
);


ALTER TABLE ivin.template_point OWNER TO edulog;

--
-- Name: template_point_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.template_point_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.template_point_id_seq OWNER TO edulog;

--
-- Name: template_point_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.template_point_id_seq OWNED BY ivin.template_point.id;


--
-- Name: template_point_validation; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.template_point_validation (
    id bigint NOT NULL,
    order_of integer NOT NULL,
    description character varying(100) NOT NULL,
    template_point_validation_type_id integer
);


ALTER TABLE ivin.template_point_validation OWNER TO edulog;

--
-- Name: template_point_validation_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.template_point_validation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.template_point_validation_id_seq OWNER TO edulog;

--
-- Name: template_point_validation_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.template_point_validation_id_seq OWNED BY ivin.template_point_validation.id;


--
-- Name: template_point_validation_type; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.template_point_validation_type (
    id bigint NOT NULL,
    template_point_id bigint,
    validation_type_id bigint
);


ALTER TABLE ivin.template_point_validation_type OWNER TO edulog;

--
-- Name: template_point_validation_type_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.template_point_validation_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.template_point_validation_type_id_seq OWNER TO edulog;

--
-- Name: template_point_validation_type_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.template_point_validation_type_id_seq OWNED BY ivin.template_point_validation_type.id;


--
-- Name: template_zone; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.template_zone (
    id bigint NOT NULL,
    template_id bigint,
    i_zone_id bigint
);


ALTER TABLE ivin.template_zone OWNER TO edulog;

--
-- Name: template_zone_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.template_zone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.template_zone_id_seq OWNER TO edulog;

--
-- Name: template_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.template_zone_id_seq OWNED BY ivin.template_zone.id;


--
-- Name: validation_type; Type: TABLE; Schema: ivin; Owner: edulog
--

CREATE TABLE ivin.validation_type (
    id bigint NOT NULL,
    description character varying(100)
);


ALTER TABLE ivin.validation_type OWNER TO edulog;

--
-- Name: validation_type_id_seq; Type: SEQUENCE; Schema: ivin; Owner: edulog
--

CREATE SEQUENCE ivin.validation_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ivin.validation_type_id_seq OWNER TO edulog;

--
-- Name: validation_type_id_seq; Type: SEQUENCE OWNED BY; Schema: ivin; Owner: edulog
--

ALTER SEQUENCE ivin.validation_type_id_seq OWNED BY ivin.validation_type.id;


--
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: edulog
--

CREATE TABLE public.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


ALTER TABLE public.flyway_schema_history OWNER TO edulog;

--
-- Name: report_info; Type: TABLE; Schema: public; Owner: edulog
--

CREATE TABLE public.report_info (
    id bigint NOT NULL,
    reports text NOT NULL,
    media_type character varying(15) NOT NULL,
    user_name character varying(36) NOT NULL,
    report_type character varying(40) NOT NULL,
    scheduled boolean NOT NULL,
    is_preview boolean DEFAULT false NOT NULL,
    title character varying(60)
);


ALTER TABLE public.report_info OWNER TO edulog;

--
-- Name: report_info_id_seq; Type: SEQUENCE; Schema: public; Owner: edulog
--

CREATE SEQUENCE public.report_info_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.report_info_id_seq OWNER TO edulog;

--
-- Name: report_info_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: edulog
--

ALTER SEQUENCE public.report_info_id_seq OWNED BY public.report_info.id;


--
-- Name: access; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.access (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(128) NOT NULL,
    description character varying(512),
    access_type character varying(128) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.access OWNER TO edulog;

--
-- Name: access_domain; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.access_domain (
    id bigint NOT NULL,
    access_id bigint NOT NULL,
    domain_surrogate_key uuid NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.access_domain OWNER TO edulog;

--
-- Name: access_domains_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.access_domains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.access_domains_id_seq OWNER TO edulog;

--
-- Name: access_domains_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.access_domains_id_seq OWNED BY rp_master.access_domain.id;


--
-- Name: access_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.access_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.access_id_seq OWNER TO edulog;

--
-- Name: access_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.access_id_seq OWNED BY rp_master.access.id;


--
-- Name: access_school; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.access_school (
    id bigint NOT NULL,
    access_id bigint NOT NULL,
    school_surrogate_key uuid NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.access_school OWNER TO edulog;

--
-- Name: access_schools_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.access_schools_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.access_schools_id_seq OWNER TO edulog;

--
-- Name: access_schools_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.access_schools_id_seq OWNED BY rp_master.access_school.id;


--
-- Name: authentication_scope; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.authentication_scope (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    application character varying(32) NOT NULL,
    groupof character varying(32) NOT NULL,
    roleof character varying(32) NOT NULL,
    role_description character varying(60) NOT NULL,
    permissions jsonb NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.authentication_scope OWNER TO edulog;

--
-- Name: authentication_scope_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.authentication_scope_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.authentication_scope_id_seq OWNER TO edulog;

--
-- Name: authentication_scope_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.authentication_scope_id_seq OWNED BY rp_master.authentication_scope.id;


--
-- Name: avl_event; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.avl_event (
    id bigint NOT NULL,
    avl_template_id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    type_of character varying(32) NOT NULL,
    point public.geography NOT NULL,
    location character varying(32) NOT NULL,
    condition character varying(32) NOT NULL,
    speed integer NOT NULL,
    mileage real NOT NULL,
    heading character varying(32) NOT NULL,
    status character varying(32) NOT NULL,
    last_visited_stop_run character varying(32) NOT NULL,
    event_time timestamp with time zone NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.avl_event OWNER TO edulog;

--
-- Name: avl_event_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.avl_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.avl_event_id_seq OWNER TO edulog;

--
-- Name: avl_event_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.avl_event_id_seq OWNED BY rp_master.avl_event.id;


--
-- Name: avl_template; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.avl_template (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(32) NOT NULL,
    description character varying(256) NOT NULL,
    route_code character varying(32) NOT NULL,
    vehicle_number character varying(10) NOT NULL,
    actual_date date NOT NULL,
    begin_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    source_of character varying(32) NOT NULL,
    type_of character varying(32) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.avl_template OWNER TO edulog;

--
-- Name: avl_template_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.avl_template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.avl_template_id_seq OWNER TO edulog;

--
-- Name: avl_template_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.avl_template_id_seq OWNED BY rp_master.avl_template.id;


--
-- Name: cal; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.cal (
    id bigint NOT NULL,
    name_of character varying(75) NOT NULL,
    description character varying(300),
    calendar_type character varying NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE rp_master.cal OWNER TO edulog;

--
-- Name: cal_cal_event; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.cal_cal_event (
    cal_event_id bigint NOT NULL,
    cal_id bigint NOT NULL,
    id bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.cal_cal_event OWNER TO edulog;

--
-- Name: cal_cal_event_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.cal_cal_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.cal_cal_event_id_seq OWNER TO edulog;

--
-- Name: cal_cal_event_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.cal_cal_event_id_seq OWNED BY rp_master.cal_cal_event.id;


--
-- Name: cal_event; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.cal_event (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(30) NOT NULL,
    description character varying(60),
    start_at timestamp without time zone,
    end_at timestamp without time zone,
    all_day_event boolean NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    cal_event_type character varying NOT NULL
);


ALTER TABLE rp_master.cal_event OWNER TO edulog;

--
-- Name: cal_event_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.cal_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.cal_event_id_seq OWNER TO edulog;

--
-- Name: cal_event_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.cal_event_id_seq OWNED BY rp_master.cal_event.id;


--
-- Name: cal_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.cal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.cal_id_seq OWNER TO edulog;

--
-- Name: cal_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.cal_id_seq OWNED BY rp_master.cal.id;


--
-- Name: data_area; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.data_area (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(60) NOT NULL,
    rp_schema character varying(60) NOT NULL,
    geo_schema character varying(60) NOT NULL,
    description character varying(200) NOT NULL,
    rolling_seq integer,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.data_area OWNER TO edulog;

--
-- Name: data_area_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.data_area_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.data_area_id_seq OWNER TO edulog;

--
-- Name: data_area_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.data_area_id_seq OWNED BY rp_master.data_area.id;


--
-- Name: import_value_mapping; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.import_value_mapping (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    external_value character varying(20),
    internal_value character varying(20),
    type_of_value character varying(20)
);


ALTER TABLE rp_master.import_value_mapping OWNER TO edulog;

--
-- Name: import_value_mapping_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.import_value_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.import_value_mapping_id_seq OWNER TO edulog;

--
-- Name: import_value_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.import_value_mapping_id_seq OWNED BY rp_master.import_value_mapping.id;


--
-- Name: plan_rollover; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.plan_rollover (
    id bigint NOT NULL,
    plan_pushed_at timestamp without time zone NOT NULL,
    successful boolean DEFAULT true NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp without time zone NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


ALTER TABLE rp_master.plan_rollover OWNER TO edulog;

--
-- Name: plan_rollover_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.plan_rollover_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.plan_rollover_id_seq OWNER TO edulog;

--
-- Name: plan_rollover_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.plan_rollover_id_seq OWNED BY rp_master.plan_rollover.id;


--
-- Name: plan_rollover_log_items; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.plan_rollover_log_items (
    id bigint NOT NULL,
    plan_rollover_id bigint NOT NULL,
    object_type character varying(32),
    object_id bigint,
    notes character varying(2048),
    user_id character varying(100) NOT NULL,
    time_changed timestamp without time zone NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


ALTER TABLE rp_master.plan_rollover_log_items OWNER TO edulog;

--
-- Name: plan_rollover_log_items_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.plan_rollover_log_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.plan_rollover_log_items_id_seq OWNER TO edulog;

--
-- Name: plan_rollover_log_items_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.plan_rollover_log_items_id_seq OWNED BY rp_master.plan_rollover_log_items.id;


--
-- Name: role_permissions; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.role_permissions (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(32) NOT NULL,
    description_of character varying(60),
    functional_permissions jsonb,
    active boolean DEFAULT true NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.role_permissions OWNER TO edulog;

--
-- Name: role_permissions_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.role_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.role_permissions_id_seq OWNER TO edulog;

--
-- Name: role_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.role_permissions_id_seq OWNED BY rp_master.role_permissions.id;


--
-- Name: student_import_conf; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.student_import_conf (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    default_program character varying(10),
    default_country character varying(20),
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    shared boolean,
    full_import boolean,
    import_mode character varying(20)
);


ALTER TABLE rp_master.student_import_conf OWNER TO edulog;

--
-- Name: student_import_conf_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.student_import_conf_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.student_import_conf_id_seq OWNER TO edulog;

--
-- Name: student_import_conf_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.student_import_conf_id_seq OWNED BY rp_master.student_import_conf.id;


--
-- Name: student_import_mapping; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.student_import_mapping (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    district_id character varying(30),
    first_name character varying(30),
    last_name character varying(30),
    middle_name character varying(30),
    nick_name character varying(30),
    suffix character varying(30),
    gender character varying(30),
    max_ride_time character varying(30),
    mailing_address character varying(30),
    phone character varying(30),
    email character varying(30),
    rfid character varying(30),
    home_room_teacher character varying(30),
    address character varying(30),
    house_number character varying(30),
    street_direction character varying(30),
    street_name character varying(30),
    city character varying(30),
    state_of character varying(30),
    zip character varying(30),
    country character varying(30),
    grade character varying(30),
    program_code character varying(30),
    school_code character varying(30),
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    parent_name character varying(30),
    parent_phone character varying(30),
    enroll_date character varying,
    withdraw_date character varying
);


ALTER TABLE rp_master.student_import_mapping OWNER TO edulog;

--
-- Name: student_import_mapping_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.student_import_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.student_import_mapping_id_seq OWNER TO edulog;

--
-- Name: student_import_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.student_import_mapping_id_seq OWNED BY rp_master.student_import_mapping.id;


--
-- Name: user; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master."user" (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    person_id uuid,
    first_name character varying(32) NOT NULL,
    middle_name character varying(32),
    last_name character varying(32) NOT NULL,
    active boolean DEFAULT true,
    email character varying(256) NOT NULL,
    department character varying(256),
    "position" character varying(256),
    user_id_manager bigint,
    password_changed_at timestamp with time zone NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master."user" OWNER TO edulog;

--
-- Name: user_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.user_id_seq OWNER TO edulog;

--
-- Name: user_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.user_id_seq OWNED BY rp_master."user".id;


--
-- Name: user_profile; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.user_profile (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    user_profile_template_id bigint,
    active boolean DEFAULT true,
    user_id_changed character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.user_profile OWNER TO edulog;

--
-- Name: user_profile_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.user_profile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.user_profile_id_seq OWNER TO edulog;

--
-- Name: user_profile_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.user_profile_id_seq OWNED BY rp_master.user_profile.id;


--
-- Name: user_profile_template; Type: TABLE; Schema: rp_master; Owner: edulog
--

CREATE TABLE rp_master.user_profile_template (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(128) NOT NULL,
    description_of character varying(512),
    domain_id bigint,
    active boolean DEFAULT true,
    access_id bigint,
    role_permissions_id bigint DEFAULT 1 NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_master.user_profile_template OWNER TO edulog;

--
-- Name: user_profile_template_id_seq; Type: SEQUENCE; Schema: rp_master; Owner: edulog
--

CREATE SEQUENCE rp_master.user_profile_template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_master.user_profile_template_id_seq OWNER TO edulog;

--
-- Name: user_profile_template_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_master; Owner: edulog
--

ALTER SEQUENCE rp_master.user_profile_template_id_seq OWNED BY rp_master.user_profile_template.id;


--
-- Name: belltime; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.belltime (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    school_id bigint NOT NULL,
    type_of character varying(15) NOT NULL,
    bell time without time zone NOT NULL,
    early time without time zone NOT NULL,
    late time without time zone NOT NULL,
    depart time without time zone,
    section_of_day integer NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.belltime OWNER TO edulog;

--
-- Name: belltime_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.belltime_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.belltime_id_seq OWNER TO edulog;

--
-- Name: belltime_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.belltime_id_seq OWNED BY rp_plan.belltime.id;


--
-- Name: cluster; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.cluster (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(40) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.cluster OWNER TO edulog;

--
-- Name: cluster_belltime; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.cluster_belltime (
    id bigint NOT NULL,
    cluster_id bigint NOT NULL,
    belltime_id bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.cluster_belltime OWNER TO edulog;

--
-- Name: cluster_belltime_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.cluster_belltime_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.cluster_belltime_id_seq OWNER TO edulog;

--
-- Name: cluster_belltime_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.cluster_belltime_id_seq OWNED BY rp_plan.cluster_belltime.id;


--
-- Name: cluster_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.cluster_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.cluster_id_seq OWNER TO edulog;

--
-- Name: cluster_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.cluster_id_seq OWNED BY rp_plan.cluster.id;


--
-- Name: contact; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.contact (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    title character varying(10) NOT NULL,
    first_name character varying(30) NOT NULL,
    middle_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    primary_phone character varying(15) NOT NULL,
    primary_type character varying(15) NOT NULL,
    secondary_phone character varying(15) NOT NULL,
    secondary_type character varying(15) NOT NULL,
    alternate_phone character varying(15) NOT NULL,
    alternate_type character varying(15) NOT NULL,
    email character varying(254) NOT NULL,
    mailing_address character varying(300) NOT NULL,
    language_code character varying(15) NOT NULL,
    suffix character varying(10) NOT NULL,
    publish boolean NOT NULL,
    code character varying(20) NOT NULL,
    picture_file_name character varying NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.contact OWNER TO edulog;

--
-- Name: contact_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.contact_id_seq OWNER TO edulog;

--
-- Name: contact_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.contact_id_seq OWNED BY rp_plan.contact.id;


--
-- Name: contractor; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.contractor (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(40) NOT NULL,
    description character varying(60) DEFAULT ''::character varying NOT NULL,
    comments character varying(256) DEFAULT ''::character varying NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.contractor OWNER TO edulog;

--
-- Name: contractor_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.contractor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.contractor_id_seq OWNER TO edulog;

--
-- Name: contractor_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.contractor_id_seq OWNED BY rp_plan.contractor.id;


--
-- Name: direction_step; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.direction_step (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    path_cover_id bigint NOT NULL,
    waypoint_cover_id bigint,
    seq_number integer NOT NULL,
    instructions character varying(256) NOT NULL,
    distance integer NOT NULL,
    duration integer NOT NULL,
    polyline public.geography(LineString,4326),
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.direction_step OWNER TO edulog;

--
-- Name: direction_step_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.direction_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.direction_step_id_seq OWNER TO edulog;

--
-- Name: direction_step_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.direction_step_id_seq OWNED BY rp_plan.direction_step.id;


--
-- Name: district_eligibility; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.district_eligibility (
    id bigint NOT NULL,
    surrogate_key uuid NOT NULL,
    description character varying(60) NOT NULL,
    eligible boolean NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.district_eligibility OWNER TO edulog;

--
-- Name: district_eligibility_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.district_eligibility_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.district_eligibility_id_seq OWNER TO edulog;

--
-- Name: district_eligibility_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.district_eligibility_id_seq OWNED BY rp_plan.district_eligibility.id;


--
-- Name: domain; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.domain (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(300),
    parent_id bigint,
    active boolean DEFAULT true,
    time_changed timestamp with time zone NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id character varying(100) NOT NULL
);


ALTER TABLE rp_plan.domain OWNER TO edulog;

--
-- Name: domain_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.domain_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.domain_id_seq OWNER TO edulog;

--
-- Name: domain_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.domain_id_seq OWNED BY rp_plan.domain.id;


--
-- Name: edulog_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.edulog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.edulog_id_seq OWNER TO edulog;

--
-- Name: eligibility_rule; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.eligibility_rule (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name_of character varying(40) NOT NULL,
    description character varying(128) DEFAULT ''::character varying NOT NULL,
    comments character varying(256) DEFAULT ''::character varying NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.eligibility_rule OWNER TO edulog;

--
-- Name: eligibility_rule_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.eligibility_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.eligibility_rule_id_seq OWNER TO edulog;

--
-- Name: eligibility_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.eligibility_rule_id_seq OWNED BY rp_plan.eligibility_rule.id;


--
-- Name: gps_unit; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.gps_unit (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    manufacturer character varying(30) DEFAULT ''::character varying,
    model character varying(30) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    device_id character varying(32) NOT NULL
);


ALTER TABLE rp_plan.gps_unit OWNER TO edulog;

--
-- Name: gps_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.gps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.gps_id_seq OWNER TO edulog;

--
-- Name: gps_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.gps_id_seq OWNED BY rp_plan.gps_unit.id;


--
-- Name: grade; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.grade (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(4) NOT NULL,
    description character varying(60) NOT NULL,
    sort_order integer NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.grade OWNER TO edulog;

--
-- Name: grade_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.grade_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.grade_id_seq OWNER TO edulog;

--
-- Name: grade_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.grade_id_seq OWNED BY rp_plan.grade.id;


--
-- Name: hazard_zone; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.hazard_zone (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    location_id bigint NOT NULL,
    label character varying(60) NOT NULL,
    description character varying(60) NOT NULL,
    notes character varying(255) NOT NULL,
    distance integer NOT NULL,
    end_date date,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.hazard_zone OWNER TO edulog;

--
-- Name: hazard_zone_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.hazard_zone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.hazard_zone_id_seq OWNER TO edulog;

--
-- Name: hazard_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.hazard_zone_id_seq OWNED BY rp_plan.hazard_zone.id;


--
-- Name: head_count; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.head_count (
    id bigint NOT NULL,
    stop_id bigint NOT NULL,
    waypoint_master_id bigint NOT NULL,
    school_id bigint NOT NULL,
    belltime_id bigint NOT NULL,
    day1 integer NOT NULL,
    day2 integer NOT NULL,
    day3 integer NOT NULL,
    day4 integer NOT NULL,
    day5 integer NOT NULL,
    day6 integer NOT NULL,
    day7 integer NOT NULL
);


ALTER TABLE rp_plan.head_count OWNER TO edulog;

--
-- Name: head_count_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.head_count_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.head_count_id_seq OWNER TO edulog;

--
-- Name: head_count_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.head_count_id_seq OWNED BY rp_plan.head_count.id;


--
-- Name: inactive_student; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.inactive_student (
    id bigint NOT NULL,
    surrogate_key uuid NOT NULL,
    edulog_id character varying(32) NOT NULL,
    government_id character varying(32),
    district_id character varying(32),
    first_name character varying(30) NOT NULL,
    middle_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    suffix character varying(10) NOT NULL,
    nick_name character varying(30) NOT NULL,
    school_id bigint,
    grade_id bigint,
    program_id bigint,
    gender character(1),
    ethnicity character varying(4),
    distance_to_school integer NOT NULL,
    elg_code character varying(40) NOT NULL,
    district_eligibility_id bigint,
    sis_address character varying(165) NOT NULL,
    sis_apt_number character varying(10) NOT NULL,
    iep boolean NOT NULL,
    section_504 boolean NOT NULL,
    home_pickup boolean NOT NULL,
    home_right_side boolean NOT NULL,
    home_available boolean NOT NULL,
    load_time integer NOT NULL,
    date_of_birth date,
    max_ride_time integer NOT NULL,
    picture_file_name character varying(60),
    location_id bigint,
    mailing_address character varying(165) NOT NULL,
    rfid character varying(36) NOT NULL,
    begin_date date,
    enroll_date date,
    withdraw_date date,
    homeroom_teacher character varying(60),
    phone character varying(15) NOT NULL,
    email character varying(100) NOT NULL,
    transport_needs bigint[],
    needs bigint[],
    notes character varying(1024)[],
    medical_notes character varying(1024)[],
    contacts bigint[],
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.inactive_student OWNER TO edulog;

--
-- Name: inactive_student_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.inactive_student_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.inactive_student_id_seq OWNER TO edulog;

--
-- Name: inactive_student_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.inactive_student_id_seq OWNED BY rp_plan.inactive_student.id;


--
-- Name: load_time; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.load_time (
    id bigint NOT NULL,
    min_load integer NOT NULL,
    load_time integer NOT NULL
);


ALTER TABLE rp_plan.load_time OWNER TO edulog;

--
-- Name: load_time_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.load_time_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.load_time_id_seq OWNER TO edulog;

--
-- Name: load_time_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.load_time_id_seq OWNED BY rp_plan.load_time.id;


--
-- Name: location; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.location (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    address character varying(165) NOT NULL,
    point public.geography NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    landmark character varying(165) DEFAULT ''::character varying,
    street_number character varying(10) DEFAULT ''::character varying,
    street character varying(165) DEFAULT ''::character varying,
    street_two character varying(165) DEFAULT ''::character varying,
    city character varying(50) DEFAULT ''::character varying,
    state character varying(50) DEFAULT ''::character varying,
    postal_code character varying(32) DEFAULT ''::character varying,
    country character varying(50) DEFAULT ''::character varying,
    node_one_id bigint,
    node_one_point public.geography,
    node_two_id bigint,
    node_two_point public.geography,
    percent_along double precision,
    right_side boolean,
    geo_location_id bigint,
    geo_street_id bigint,
    geo_street_two_id bigint,
    geo_segment_id bigint
);


ALTER TABLE rp_plan.location OWNER TO edulog;

--
-- Name: location_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.location_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.location_id_seq OWNER TO edulog;

--
-- Name: location_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.location_id_seq OWNED BY rp_plan.location.id;


--
-- Name: medical_note; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.medical_note (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    student_id bigint NOT NULL,
    note character varying(1024) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.medical_note OWNER TO edulog;

--
-- Name: medical_note_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.medical_note_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.medical_note_id_seq OWNER TO edulog;

--
-- Name: medical_note_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.medical_note_id_seq OWNED BY rp_plan.medical_note.id;


--
-- Name: need; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.need (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    description character varying(50) NOT NULL,
    sort_order integer NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.need OWNER TO edulog;

--
-- Name: need_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.need_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.need_id_seq OWNER TO edulog;

--
-- Name: need_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.need_id_seq OWNED BY rp_plan.need.id;


--
-- Name: path_cover; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.path_cover (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    path_master_id bigint NOT NULL,
    cover character varying(7) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.path_cover OWNER TO edulog;

--
-- Name: path_cover_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.path_cover_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.path_cover_id_seq OWNER TO edulog;

--
-- Name: path_cover_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.path_cover_id_seq OWNED BY rp_plan.path_cover.id;


--
-- Name: path_master; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.path_master (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    description character varying(40) NOT NULL,
    type_of character varying(20) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.path_master OWNER TO edulog;

--
-- Name: path_master_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.path_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.path_master_id_seq OWNER TO edulog;

--
-- Name: path_master_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.path_master_id_seq OWNED BY rp_plan.path_master.id;


--
-- Name: program; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.program (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(4) NOT NULL,
    description character varying(60) NOT NULL,
    sort_order integer NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.program OWNER TO edulog;

--
-- Name: program_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.program_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.program_id_seq OWNER TO edulog;

--
-- Name: program_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.program_id_seq OWNED BY rp_plan.program.id;


--
-- Name: route; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.route (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    path_master_id bigint NOT NULL,
    code character varying(32) NOT NULL,
    description character varying(40) NOT NULL,
    comments character varying(256) NOT NULL,
    proxy boolean NOT NULL,
    map_set integer NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    vehicle_id bigint,
    contractor_id bigint,
    version bigint DEFAULT 0 NOT NULL,
    depot_id uuid
);


ALTER TABLE rp_plan.route OWNER TO edulog;

--
-- Name: route_contact; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.route_contact (
    id bigint NOT NULL,
    contact_id bigint NOT NULL,
    route_id bigint NOT NULL,
    relation_descriptor character varying(15) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.route_contact OWNER TO edulog;

--
-- Name: route_contact_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.route_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.route_contact_id_seq OWNER TO edulog;

--
-- Name: route_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.route_contact_id_seq OWNED BY rp_plan.route_contact.id;


--
-- Name: route_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.route_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.route_id_seq OWNER TO edulog;

--
-- Name: route_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.route_id_seq OWNED BY rp_plan.route.id;


--
-- Name: route_run; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.route_run (
    id bigint NOT NULL,
    route_id bigint NOT NULL,
    run_id bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.route_run OWNER TO edulog;

--
-- Name: route_run_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.route_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.route_run_id_seq OWNER TO edulog;

--
-- Name: route_run_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.route_run_id_seq OWNED BY rp_plan.route_run.id;


--
-- Name: run; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.run (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(32) NOT NULL,
    description character varying(60) NOT NULL,
    to_from character varying(15) NOT NULL,
    max_duration integer NOT NULL,
    max_load integer NOT NULL,
    comments character varying(256) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    dynamic_freq boolean DEFAULT true,
    version bigint DEFAULT 0 NOT NULL
);


ALTER TABLE rp_plan.run OWNER TO edulog;

--
-- Name: run_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.run_id_seq OWNER TO edulog;

--
-- Name: run_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.run_id_seq OWNED BY rp_plan.run.id;


--
-- Name: run_max_duration_view; Type: VIEW; Schema: rp_plan; Owner: edulog
--

CREATE VIEW rp_plan.run_max_duration_view AS
SELECT
    NULL::bigint AS run_id,
    NULL::boolean AS over_max_duration;


ALTER TABLE rp_plan.run_max_duration_view OWNER TO edulog;

--
-- Name: trip_cover; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.trip_cover (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    freq character varying(7) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    transport_def_cover_id bigint NOT NULL
);


ALTER TABLE rp_plan.trip_cover OWNER TO edulog;

--
-- Name: trip_leg; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.trip_leg (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    trip_cover_id bigint NOT NULL,
    seq_number integer NOT NULL,
    description character varying(60),
    type_of character varying(30) NOT NULL,
    type_of_origin character varying(15) NOT NULL,
    type_of_destination character varying(15) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.trip_leg OWNER TO edulog;

--
-- Name: trip_leg_waypoint_master; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.trip_leg_waypoint_master (
    id bigint NOT NULL,
    trip_leg_id bigint NOT NULL,
    waypoint_master_id_origin bigint NOT NULL,
    waypoint_master_id_destination bigint NOT NULL
);


ALTER TABLE rp_plan.trip_leg_waypoint_master OWNER TO edulog;

--
-- Name: waypoint_cover; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.waypoint_cover (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    waypoint_master_id bigint NOT NULL,
    path_cover_id bigint NOT NULL,
    seq_number integer NOT NULL,
    begin_date date,
    end_date date,
    student_crossing boolean NOT NULL,
    time_at time without time zone,
    load_time integer NOT NULL,
    fixed_time time without time zone,
    duration_override integer,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.waypoint_cover OWNER TO edulog;

--
-- Name: waypoint_master; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.waypoint_master (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    path_master_id bigint NOT NULL,
    route_run_id bigint,
    location_id bigint NOT NULL,
    seq_number integer NOT NULL,
    boarding_type character varying(7) NOT NULL,
    type_of character varying(15) NOT NULL,
    description character varying(165) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    dynamic_freq boolean DEFAULT true
);


ALTER TABLE rp_plan.waypoint_master OWNER TO edulog;

--
-- Name: run_over_max_load_view; Type: VIEW; Schema: rp_plan; Owner: edulog
--

CREATE VIEW rp_plan.run_over_max_load_view AS
 SELECT sub1.run_id,
    bool_or(sub1.over) AS over_max_load
   FROM ( SELECT sub.run_id,
            (sum((sub.orig_cnt - sub.dest_cnt)) OVER (PARTITION BY sub.run_id, sub.freq_day ORDER BY sub.wpm_seq_number) > (sub.max_load)::numeric) AS over
           FROM ( SELECT run.id AS run_id,
                    run.max_load,
                    waypoint_master.seq_number AS wpm_seq_number,
                    days.freq_day,
                    count(otl.trip_cover_id) AS orig_cnt,
                    count(dtl.trip_cover_id) AS dest_cnt
                   FROM (((((((((((rp_plan.waypoint_master
                     LEFT JOIN rp_plan.waypoint_cover wp_cover ON ((wp_cover.waypoint_master_id = waypoint_master.id)))
                     LEFT JOIN rp_plan.path_cover p_cover ON ((p_cover.id = wp_cover.path_cover_id)))
                     LEFT JOIN rp_plan.route_run rr ON ((rr.id = waypoint_master.route_run_id)))
                     LEFT JOIN rp_plan.run ON ((rr.run_id = run.id)))
                     LEFT JOIN rp_plan.trip_leg_waypoint_master otlwm ON ((otlwm.waypoint_master_id_origin = waypoint_master.id)))
                     LEFT JOIN rp_plan.trip_leg_waypoint_master dtlwm ON ((dtlwm.waypoint_master_id_destination = waypoint_master.id)))
                     LEFT JOIN rp_plan.trip_leg otl ON ((otl.id = otlwm.trip_leg_id)))
                     LEFT JOIN rp_plan.trip_leg dtl ON ((dtl.id = dtlwm.trip_leg_id)))
                     LEFT JOIN rp_plan.trip_cover otc ON ((otl.trip_cover_id = otc.id)))
                     LEFT JOIN rp_plan.trip_cover dtc ON ((dtl.trip_cover_id = dtc.id)))
                     JOIN ( SELECT 'M'::text AS freq_day
                        UNION
                         SELECT 'T'::text AS text
                        UNION
                         SELECT 'W'::text AS text
                        UNION
                         SELECT 'U'::text AS text
                        UNION
                         SELECT 'F'::text AS text
                        UNION
                         SELECT 'A'::text AS text
                        UNION
                         SELECT 'S'::text AS text) days ON ((((p_cover.cover)::text <> 'EMPTY'::text) AND ((p_cover.cover)::text ~~ concat('%', days.freq_day, '%')) AND ((otc.* IS NULL) OR (((otc.freq)::text <> 'EMPTY'::text) AND ((otc.freq)::text ~~ concat('%', days.freq_day, '%')))) AND ((dtc.* IS NULL) OR (((dtc.freq)::text <> 'EMPTY'::text) AND ((dtc.freq)::text ~~ concat('%', days.freq_day, '%')))))))
                  WHERE (rr.run_id IS NOT NULL)
                  GROUP BY run.id, run.max_load, p_cover.cover, days.freq_day, waypoint_master.id, waypoint_master.type_of, waypoint_master.seq_number
                  ORDER BY run.id, p_cover.cover, waypoint_master.seq_number) sub
          GROUP BY sub.run_id, sub.max_load, sub.freq_day, sub.wpm_seq_number, sub.orig_cnt, sub.dest_cnt
          ORDER BY sub.run_id) sub1
  GROUP BY sub1.run_id;


ALTER TABLE rp_plan.run_over_max_load_view OWNER TO edulog;

--
-- Name: school; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(32) NOT NULL,
    name_of character varying(50) NOT NULL,
    grade_level character varying(30),
    address character varying(100) NOT NULL,
    city character varying(30),
    state_code character varying(3),
    postal_code character varying(10),
    country character varying(3),
    max_ride_time integer,
    school_id_transport bigint,
    school_district_id bigint,
    board character varying(16),
    school_type character varying(50),
    url character varying(100),
    comments character varying(256),
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    cal_id bigint
);


ALTER TABLE rp_plan.school OWNER TO edulog;

--
-- Name: school_contact; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school_contact (
    id bigint NOT NULL,
    school_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    relation_descriptor character varying(30) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.school_contact OWNER TO edulog;

--
-- Name: school_contact_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_contact_id_seq OWNER TO edulog;

--
-- Name: school_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_contact_id_seq OWNED BY rp_plan.school_contact.id;


--
-- Name: school_district; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school_district (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(32) NOT NULL,
    county character varying(32) NOT NULL,
    url character varying(100) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    description character varying(60) DEFAULT ''::character varying NOT NULL,
    cal_id bigint
);


ALTER TABLE rp_plan.school_district OWNER TO edulog;

--
-- Name: school_district_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_district_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_district_id_seq OWNER TO edulog;

--
-- Name: school_district_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_district_id_seq OWNED BY rp_plan.school_district.id;


--
-- Name: school_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_id_seq OWNER TO edulog;

--
-- Name: school_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_id_seq OWNED BY rp_plan.school.id;


--
-- Name: school_location; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school_location (
    id bigint NOT NULL,
    school_id bigint NOT NULL,
    location_id bigint NOT NULL,
    type_of character varying(15) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.school_location OWNER TO edulog;

--
-- Name: school_location_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_location_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_location_id_seq OWNER TO edulog;

--
-- Name: school_location_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_location_id_seq OWNED BY rp_plan.school_location.id;


--
-- Name: school_operation_cover; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school_operation_cover (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    school_operation_master_id bigint NOT NULL,
    belltime_id_depart bigint NOT NULL,
    belltime_id_arrival bigint NOT NULL,
    freq character varying(7) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.school_operation_cover OWNER TO edulog;

--
-- Name: school_operation_cover_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_operation_cover_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_operation_cover_id_seq OWNER TO edulog;

--
-- Name: school_operation_cover_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_operation_cover_id_seq OWNED BY rp_plan.school_operation_cover.id;


--
-- Name: school_operation_master; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school_operation_master (
    id bigint NOT NULL,
    school_id bigint NOT NULL,
    grade_id bigint NOT NULL,
    program_id bigint NOT NULL,
    hazard_type integer NOT NULL,
    web_allowed boolean NOT NULL,
    school_calendar character varying(64) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    max_assign_dist integer
);


ALTER TABLE rp_plan.school_operation_master OWNER TO edulog;

--
-- Name: school_operation_master_boundary; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.school_operation_master_boundary (
    id bigint NOT NULL,
    school_operation_master_id bigint NOT NULL,
    posting_type character varying(10) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    eligibility_rule_id bigint,
    geo_boundary_uuid uuid
);


ALTER TABLE rp_plan.school_operation_master_boundary OWNER TO edulog;

--
-- Name: school_operation_master_boundary_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_operation_master_boundary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_operation_master_boundary_id_seq OWNER TO edulog;

--
-- Name: school_operation_master_boundary_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_operation_master_boundary_id_seq OWNED BY rp_plan.school_operation_master_boundary.id;


--
-- Name: school_operation_master_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.school_operation_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.school_operation_master_id_seq OWNER TO edulog;

--
-- Name: school_operation_master_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.school_operation_master_id_seq OWNED BY rp_plan.school_operation_master.id;


--
-- Name: site_meta_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_meta_data (
    id bigint NOT NULL,
    data_type character varying(15) NOT NULL,
    field_type character varying(15) NOT NULL,
    label character varying(32) NOT NULL,
    data_length integer NOT NULL,
    visible boolean NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.site_meta_data OWNER TO edulog;

--
-- Name: site_meta_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_meta_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_meta_data_id_seq OWNER TO edulog;

--
-- Name: site_meta_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_meta_data_id_seq OWNED BY rp_plan.site_meta_data.id;


--
-- Name: site_route_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_route_data (
    id bigint NOT NULL,
    route_id bigint NOT NULL,
    json_string character varying(256000)
);


ALTER TABLE rp_plan.site_route_data OWNER TO edulog;

--
-- Name: site_route_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_route_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_route_data_id_seq OWNER TO edulog;

--
-- Name: site_route_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_route_data_id_seq OWNED BY rp_plan.site_route_data.id;


--
-- Name: site_run_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_run_data (
    id bigint NOT NULL,
    run_id bigint NOT NULL,
    json_string character varying(256000)
);


ALTER TABLE rp_plan.site_run_data OWNER TO edulog;

--
-- Name: site_run_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_run_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_run_data_id_seq OWNER TO edulog;

--
-- Name: site_run_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_run_data_id_seq OWNED BY rp_plan.site_run_data.id;


--
-- Name: site_school_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_school_data (
    id bigint NOT NULL,
    school_id bigint NOT NULL,
    json_string character varying(256000)
);


ALTER TABLE rp_plan.site_school_data OWNER TO edulog;

--
-- Name: site_school_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_school_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_school_data_id_seq OWNER TO edulog;

--
-- Name: site_school_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_school_data_id_seq OWNED BY rp_plan.site_school_data.id;


--
-- Name: site_stop_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_stop_data (
    id bigint NOT NULL,
    stop_id bigint NOT NULL,
    json_string character varying(256000)
);


ALTER TABLE rp_plan.site_stop_data OWNER TO edulog;

--
-- Name: site_stop_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_stop_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_stop_data_id_seq OWNER TO edulog;

--
-- Name: site_stop_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_stop_data_id_seq OWNED BY rp_plan.site_stop_data.id;


--
-- Name: site_student_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_student_data (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    json_string character varying(256000)
);


ALTER TABLE rp_plan.site_student_data OWNER TO edulog;

--
-- Name: site_student_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_student_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_student_data_id_seq OWNER TO edulog;

--
-- Name: site_student_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_student_data_id_seq OWNED BY rp_plan.site_student_data.id;


--
-- Name: site_trip_data; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.site_trip_data (
    id bigint NOT NULL,
    trip_master_id bigint NOT NULL,
    json_string character varying(256000)
);


ALTER TABLE rp_plan.site_trip_data OWNER TO edulog;

--
-- Name: site_trip_data_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.site_trip_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.site_trip_data_id_seq OWNER TO edulog;

--
-- Name: site_trip_data_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.site_trip_data_id_seq OWNED BY rp_plan.site_trip_data.id;


--
-- Name: stop; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.stop (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    location_id bigint NOT NULL,
    code character varying(32) NOT NULL,
    government_id character varying(32) NOT NULL,
    description character varying(165) NOT NULL,
    comments character varying(256) NOT NULL,
    right_side boolean NOT NULL,
    end_date date,
    begin_date date,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE rp_plan.stop OWNER TO edulog;

--
-- Name: stop_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.stop_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.stop_id_seq OWNER TO edulog;

--
-- Name: stop_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.stop_id_seq OWNED BY rp_plan.stop.id;


--
-- Name: student; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.student (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    edulog_id character varying(32) NOT NULL,
    government_id character varying(32),
    district_id character varying(32),
    first_name character varying(30) NOT NULL,
    middle_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    suffix character varying(10) NOT NULL,
    nick_name character varying(30) NOT NULL,
    school_operation_master_id bigint,
    gender character(1),
    ethnicity character varying(4),
    distance_to_school integer NOT NULL,
    elg_code character varying(40) NOT NULL,
    sis_address character varying(165) NOT NULL,
    sis_apt_number character varying(10) NOT NULL,
    iep boolean NOT NULL,
    section_504 boolean NOT NULL,
    home_stop boolean NOT NULL,
    home_right_side boolean NOT NULL,
    home_available boolean NOT NULL,
    load_time integer NOT NULL,
    date_of_birth date,
    max_ride_time integer NOT NULL,
    picture_file_name character varying(60),
    location_id bigint,
    mailing_address character varying(165) NOT NULL,
    rfid character varying(36) NOT NULL,
    begin_date date,
    enroll_date date,
    withdraw_date date,
    homeroom_teacher character varying(60),
    phone character varying(15) NOT NULL,
    email character varying(100) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    district_eligibility_id bigint,
    school_bus_ride_allowed boolean DEFAULT true NOT NULL
);


ALTER TABLE rp_plan.student OWNER TO edulog;

--
-- Name: student_contact; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.student_contact (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    mailing_address boolean NOT NULL,
    emergency_contact boolean NOT NULL,
    releasable boolean NOT NULL,
    relation_descriptor character varying(15) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.student_contact OWNER TO edulog;

--
-- Name: student_contact_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_contact_id_seq OWNER TO edulog;

--
-- Name: student_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_contact_id_seq OWNED BY rp_plan.student_contact.id;


--
-- Name: student_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_id_seq OWNER TO edulog;

--
-- Name: student_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_id_seq OWNED BY rp_plan.student.id;


--
-- Name: student_import_line; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.student_import_line (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    athena_id bigint NOT NULL,
    district_id character varying(30),
    first_name character varying(30),
    last_name character varying(30),
    middle_name character varying(30),
    nick_name character varying(30),
    suffix character varying(30),
    gender character varying(30),
    ethnicity character varying(30),
    distance_to_school character varying(30),
    max_ride_time character varying(30),
    mailing_address character varying(255),
    phone character varying(30),
    email character varying(30),
    rfid character varying(30),
    home_room_teacher character varying(30),
    address character varying(255),
    house_number character varying(30),
    street_direction character varying(30),
    street_name character varying(30),
    city character varying(30),
    state_of character varying(30),
    zip character varying(30),
    country character varying(30),
    grade character varying(30),
    program_code character varying(30),
    school_code character varying(30),
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    parent_name character varying(30),
    parent_phone character varying(30),
    enroll_date date,
    withdraw_date date
);


ALTER TABLE rp_plan.student_import_line OWNER TO edulog;

--
-- Name: student_import_line_athena_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_import_line_athena_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_import_line_athena_id_seq OWNER TO edulog;

--
-- Name: student_import_line_athena_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_import_line_athena_id_seq OWNED BY rp_plan.student_import_line.athena_id;


--
-- Name: student_import_line_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_import_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_import_line_id_seq OWNER TO edulog;

--
-- Name: student_import_line_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_import_line_id_seq OWNED BY rp_plan.student_import_line.id;


--
-- Name: student_need; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.student_need (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    need_id bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.student_need OWNER TO edulog;

--
-- Name: student_need_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_need_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_need_id_seq OWNER TO edulog;

--
-- Name: student_need_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_need_id_seq OWNED BY rp_plan.student_need.id;


--
-- Name: student_note; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.student_note (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    student_id bigint NOT NULL,
    note character varying(1024) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.student_note OWNER TO edulog;

--
-- Name: student_note_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_note_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_note_id_seq OWNER TO edulog;

--
-- Name: student_note_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_note_id_seq OWNED BY rp_plan.student_note.id;


--
-- Name: student_note_student_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_note_student_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_note_student_id_seq OWNER TO edulog;

--
-- Name: student_note_student_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_note_student_id_seq OWNED BY rp_plan.student_note.student_id;


--
-- Name: student_transport_need; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.student_transport_need (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    transport_need_id bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.student_transport_need OWNER TO edulog;

--
-- Name: student_transport_need_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.student_transport_need_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.student_transport_need_id_seq OWNER TO edulog;

--
-- Name: student_transport_need_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.student_transport_need_id_seq OWNED BY rp_plan.student_transport_need.id;


--
-- Name: transport_def_cover; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.transport_def_cover (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    transport_def_master_id bigint NOT NULL,
    belltime_id_origin bigint,
    belltime_id_destination bigint,
    freq character varying(7) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.transport_def_cover OWNER TO edulog;

--
-- Name: transport_def_cover_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.transport_def_cover_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.transport_def_cover_id_seq OWNER TO edulog;

--
-- Name: transport_def_cover_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.transport_def_cover_id_seq OWNED BY rp_plan.transport_def_cover.id;


--
-- Name: transport_def_master; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.transport_def_master (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    description character varying(60) DEFAULT ''::character varying NOT NULL,
    school_id_origin bigint,
    location_id_origin bigint NOT NULL,
    school_id_destination bigint,
    location_id_destination bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.transport_def_master OWNER TO edulog;

--
-- Name: transport_def_master_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.transport_def_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.transport_def_master_id_seq OWNER TO edulog;

--
-- Name: transport_def_master_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.transport_def_master_id_seq OWNED BY rp_plan.transport_def_master.id;


--
-- Name: transport_itinerary; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.transport_itinerary (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    transport_request_detail_id bigint NOT NULL,
    freq character varying(7) NOT NULL,
    stop_code_to_school character varying(32) NOT NULL,
    stop_description_to_school character varying(165) NOT NULL,
    run_code_to_school character varying(32) NOT NULL,
    run_description_to_school character varying(60) NOT NULL,
    time_at_to_school time without time zone,
    stop_code_from_school character varying(32) NOT NULL,
    stop_description_from_school character varying(165) NOT NULL,
    run_code_from_school character varying(32) NOT NULL,
    run_description_from_school character varying(60) NOT NULL,
    time_at_from_school time without time zone,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.transport_itinerary OWNER TO edulog;

--
-- Name: transport_itinerary_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.transport_itinerary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.transport_itinerary_id_seq OWNER TO edulog;

--
-- Name: transport_itinerary_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.transport_itinerary_id_seq OWNED BY rp_plan.transport_itinerary.id;


--
-- Name: transport_need; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.transport_need (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    description character varying(50) NOT NULL,
    type_of character varying(15) NOT NULL,
    load_value integer NOT NULL,
    load_time integer NOT NULL,
    sort_order integer NOT NULL,
    extra_run_load integer NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.transport_need OWNER TO edulog;

--
-- Name: transport_need_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.transport_need_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.transport_need_id_seq OWNER TO edulog;

--
-- Name: transport_need_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.transport_need_id_seq OWNED BY rp_plan.transport_need.id;


--
-- Name: transport_request; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.transport_request (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    begin_date date,
    end_date date,
    transport_mode character varying(20) NOT NULL,
    location_id_requested_stop bigint,
    requested_stop_required boolean NOT NULL,
    request_source character varying(30) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    direction character varying(15),
    student_id bigint NOT NULL,
    transport_def_master_id_to_school bigint,
    transport_def_master_id_from_school bigint,
    elg_code character varying(40) NOT NULL,
    elg_overridden boolean DEFAULT false NOT NULL,
    student_default boolean NOT NULL,
    transport_request_id_overridden bigint,
    home_stop boolean DEFAULT false NOT NULL,
    school_bus_ride_allowed boolean DEFAULT true NOT NULL
);


ALTER TABLE rp_plan.transport_request OWNER TO edulog;

--
-- Name: transport_request_detail; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.transport_request_detail (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    transport_request_id bigint NOT NULL,
    seq_number integer NOT NULL,
    status character varying(10) NOT NULL,
    reviewer_group character varying(32),
    comments character varying(256) NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE rp_plan.transport_request_detail OWNER TO edulog;

--
-- Name: transport_request_detail_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.transport_request_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.transport_request_detail_id_seq OWNER TO edulog;

--
-- Name: transport_request_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.transport_request_detail_id_seq OWNED BY rp_plan.transport_request_detail.id;


--
-- Name: transport_request_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.transport_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.transport_request_id_seq OWNER TO edulog;

--
-- Name: transport_request_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.transport_request_id_seq OWNED BY rp_plan.transport_request.id;


--
-- Name: trip_cover_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.trip_cover_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.trip_cover_id_seq OWNER TO edulog;

--
-- Name: trip_cover_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.trip_cover_id_seq OWNED BY rp_plan.trip_cover.id;


--
-- Name: trip_leg_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.trip_leg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.trip_leg_id_seq OWNER TO edulog;

--
-- Name: trip_leg_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.trip_leg_id_seq OWNED BY rp_plan.trip_leg.id;


--
-- Name: trip_leg_waypoint_master_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.trip_leg_waypoint_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.trip_leg_waypoint_master_id_seq OWNER TO edulog;

--
-- Name: trip_leg_waypoint_master_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.trip_leg_waypoint_master_id_seq OWNED BY rp_plan.trip_leg_waypoint_master.id;


--
-- Name: trip_master; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.trip_master (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    transport_def_master_id bigint NOT NULL,
    assigned_status character varying NOT NULL,
    version bigint DEFAULT 0 NOT NULL
);


ALTER TABLE rp_plan.trip_master OWNER TO edulog;

--
-- Name: trip_master_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.trip_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.trip_master_id_seq OWNER TO edulog;

--
-- Name: trip_master_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.trip_master_id_seq OWNED BY rp_plan.trip_master.id;


--
-- Name: vehicle; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.vehicle (
    id bigint NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    vin character varying(20),
    name_of character varying(32) NOT NULL,
    capacity integer DEFAULT 0 NOT NULL,
    description character varying(60) DEFAULT ''::character varying NOT NULL,
    gps_unit_id bigint,
    make character varying(30) DEFAULT ''::character varying NOT NULL,
    model character varying(30) DEFAULT ''::character varying NOT NULL,
    year_of integer DEFAULT 0 NOT NULL,
    comments character varying(256) DEFAULT ''::character varying NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp with time zone NOT NULL,
    create_date timestamp with time zone NOT NULL,
    contractor_id bigint,
    start_of_service date,
    end_of_service date,
    license_number character varying(20) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE rp_plan.vehicle OWNER TO edulog;

--
-- Name: vehicle_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.vehicle_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.vehicle_id_seq OWNER TO edulog;

--
-- Name: vehicle_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.vehicle_id_seq OWNED BY rp_plan.vehicle.id;


--
-- Name: vehicle_maintenance; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.vehicle_maintenance (
    id bigint NOT NULL,
    service_start_date date NOT NULL,
    service_start_time time without time zone,
    estimated_service_end_date date,
    estimated_service_end_time time without time zone,
    actual_service_end_date date,
    actual_service_end_time time without time zone,
    vehicle_id bigint NOT NULL,
    user_id character varying(100) NOT NULL,
    time_changed timestamp without time zone NOT NULL,
    surrogate_key uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


ALTER TABLE rp_plan.vehicle_maintenance OWNER TO edulog;

--
-- Name: vehicle_maintenance_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.vehicle_maintenance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.vehicle_maintenance_id_seq OWNER TO edulog;

--
-- Name: vehicle_maintenance_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.vehicle_maintenance_id_seq OWNED BY rp_plan.vehicle_maintenance.id;


--
-- Name: vehicle_transport_need; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.vehicle_transport_need (
    id bigint NOT NULL,
    vehicle_id bigint NOT NULL,
    transport_need_id bigint NOT NULL
);


ALTER TABLE rp_plan.vehicle_transport_need OWNER TO edulog;

--
-- Name: vehicle_transport_need_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.vehicle_transport_need_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.vehicle_transport_need_id_seq OWNER TO edulog;

--
-- Name: vehicle_transport_need_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.vehicle_transport_need_id_seq OWNED BY rp_plan.vehicle_transport_need.id;


--
-- Name: waypoint_cover_belltime; Type: TABLE; Schema: rp_plan; Owner: edulog
--

CREATE TABLE rp_plan.waypoint_cover_belltime (
    id bigint NOT NULL,
    belltime_id bigint NOT NULL,
    waypoint_cover_id bigint NOT NULL
);


ALTER TABLE rp_plan.waypoint_cover_belltime OWNER TO edulog;

--
-- Name: waypoint_cover_belltime_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.waypoint_cover_belltime_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.waypoint_cover_belltime_id_seq OWNER TO edulog;

--
-- Name: waypoint_cover_belltime_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.waypoint_cover_belltime_id_seq OWNED BY rp_plan.waypoint_cover_belltime.id;


--
-- Name: waypoint_cover_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.waypoint_cover_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.waypoint_cover_id_seq OWNER TO edulog;

--
-- Name: waypoint_cover_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.waypoint_cover_id_seq OWNED BY rp_plan.waypoint_cover.id;


--
-- Name: waypoint_master_id_seq; Type: SEQUENCE; Schema: rp_plan; Owner: edulog
--

CREATE SEQUENCE rp_plan.waypoint_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rp_plan.waypoint_master_id_seq OWNER TO edulog;

--
-- Name: waypoint_master_id_seq; Type: SEQUENCE OWNED BY; Schema: rp_plan; Owner: edulog
--

ALTER SEQUENCE rp_plan.waypoint_master_id_seq OWNED BY rp_plan.waypoint_master.id;


--
-- Name: board; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.board (
    label character varying(16) NOT NULL,
    web_allowed boolean NOT NULL
);


ALTER TABLE settings.board OWNER TO edulog;

--
-- Name: city; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.city (
    label character varying(30) NOT NULL
);


ALTER TABLE settings.city OWNER TO edulog;

--
-- Name: ethnicity; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.ethnicity (
    label character varying(4) NOT NULL,
    description character varying(60) NOT NULL
);


ALTER TABLE settings.ethnicity OWNER TO edulog;

--
-- Name: form_of_address; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.form_of_address (
    title character varying(10) NOT NULL
);


ALTER TABLE settings.form_of_address OWNER TO edulog;

--
-- Name: hazard_type; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.hazard_type (
    description character varying(60) NOT NULL
);


ALTER TABLE settings.hazard_type OWNER TO edulog;

--
-- Name: language; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.language (
    description character varying(15) NOT NULL
);


ALTER TABLE settings.language OWNER TO edulog;

--
-- Name: postal_code; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.postal_code (
    code character varying(10) NOT NULL
);


ALTER TABLE settings.postal_code OWNER TO edulog;

--
-- Name: route_contact_relationship; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.route_contact_relationship (
    title character varying(15) NOT NULL
);


ALTER TABLE settings.route_contact_relationship OWNER TO edulog;

--
-- Name: school_calendar; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.school_calendar (
    label character varying(12) NOT NULL
);


ALTER TABLE settings.school_calendar OWNER TO edulog;

--
-- Name: school_contact_relationship; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.school_contact_relationship (
    title character varying(15) NOT NULL
);


ALTER TABLE settings.school_contact_relationship OWNER TO edulog;

--
-- Name: school_type; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.school_type (
    description character varying(50) NOT NULL
);


ALTER TABLE settings.school_type OWNER TO edulog;

--
-- Name: state_country; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.state_country (
    state_code character varying(2) NOT NULL,
    state_description character varying(30) NOT NULL,
    country_description character varying(20) NOT NULL,
    country_code character varying(3) NOT NULL
);


ALTER TABLE settings.state_country OWNER TO edulog;

--
-- Name: student_contact_relationship; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.student_contact_relationship (
    title character varying(15) NOT NULL
);


ALTER TABLE settings.student_contact_relationship OWNER TO edulog;

--
-- Name: user_title; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.user_title (
    title character varying(30) NOT NULL
);


ALTER TABLE settings.user_title OWNER TO edulog;

--
-- Name: version; Type: TABLE; Schema: settings; Owner: edulog
--

CREATE TABLE settings.version (
    type character varying(25) NOT NULL,
    type_version character varying(12) NOT NULL,
    time_changed timestamp with time zone NOT NULL
);


ALTER TABLE settings.version OWNER TO edulog;


--
-- Command Distributor Table
--

CREATE TABLE public.registered_command_rest_hooks (
    application_id uuid not null
        constraint registered_command_rest_hooks_pkey
            primary key,
    application_name varchar(20) not null,
    application_version varchar(20),
    tenant_id uuid not null,
    url_to_send_event text not null,
    created_by varchar(20),
    created_on timestamp,
    updated_by varchar(20),
    updated_on timestamp,
    last_published_success timestamp,
    last_published_error timestamp
);

alter table public.registered_command_rest_hooks owner to edulog;

--
-- Name: activity id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.activity ALTER COLUMN id SET DEFAULT nextval('edta.activity_id_seq'::regclass);


--
-- Name: billing_type id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.billing_type ALTER COLUMN id SET DEFAULT nextval('edta.billing_type_id_seq'::regclass);


--
-- Name: certification id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.certification ALTER COLUMN id SET DEFAULT nextval('edta.certification_id_seq'::regclass);


--
-- Name: department id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.department ALTER COLUMN id SET DEFAULT nextval('edta.department_id_seq'::regclass);


--
-- Name: district id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.district ALTER COLUMN id SET DEFAULT nextval('edta.district_id_seq'::regclass);


--
-- Name: driver_class id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_class ALTER COLUMN id SET DEFAULT nextval('edta.driver_class_id_seq'::regclass);


--
-- Name: driver_info id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info ALTER COLUMN id SET DEFAULT nextval('edta.driver_info_id_seq'::regclass);


--
-- Name: emp_class id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.emp_class ALTER COLUMN id SET DEFAULT nextval('edta.emp_class_id_seq'::regclass);


--
-- Name: emp_group id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.emp_group ALTER COLUMN id SET DEFAULT nextval('edta.emp_group_id_seq'::regclass);


--
-- Name: grade id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.grade ALTER COLUMN id SET DEFAULT nextval('edta.grade_id_seq'::regclass);


--
-- Name: image id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.image ALTER COLUMN id SET DEFAULT nextval('edta.image_id_seq'::regclass);


--
-- Name: level id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.level ALTER COLUMN id SET DEFAULT nextval('edta.level_id_seq'::regclass);


--
-- Name: license_class id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.license_class ALTER COLUMN id SET DEFAULT nextval('edta.license_class_id_seq'::regclass);


--
-- Name: ridership id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.ridership ALTER COLUMN id SET DEFAULT nextval('edta.ridership_id_seq'::regclass);


--
-- Name: scale_hour id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.scale_hour ALTER COLUMN id SET DEFAULT nextval('edta.scale_hour_id_seq'::regclass);


--
-- Name: search id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.search ALTER COLUMN id SET DEFAULT nextval('edta.search_id_seq'::regclass);


--
-- Name: seniority id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.seniority ALTER COLUMN id SET DEFAULT nextval('edta.seniority_id_seq'::regclass);


--
-- Name: skill id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.skill ALTER COLUMN id SET DEFAULT nextval('edta.skill_id_seq'::regclass);


--
-- Name: training id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.training ALTER COLUMN id SET DEFAULT nextval('edta.training_id_seq'::regclass);


--
-- Name: transaction id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.transaction ALTER COLUMN id SET DEFAULT nextval('edta.transaction_id_seq'::regclass);


--
-- Name: union id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta."union" ALTER COLUMN id SET DEFAULT nextval('edta.union_id_seq'::regclass);


--
-- Name: work_group id; Type: DEFAULT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.work_group ALTER COLUMN id SET DEFAULT nextval('edta.work_group_id_seq'::regclass);


--
-- Name: config id; Type: DEFAULT; Schema: geo_master; Owner: edulog
--

ALTER TABLE ONLY geo_master.config ALTER COLUMN id SET DEFAULT nextval('geo_master.config_id_seq'::regclass);


--
-- Name: geoserver_layer id; Type: DEFAULT; Schema: geo_master; Owner: edulog
--

ALTER TABLE ONLY geo_master.geoserver_layer ALTER COLUMN id SET DEFAULT nextval('geo_master.geoserver_layer_id_seq'::regclass);


--
-- Name: address id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.address ALTER COLUMN id SET DEFAULT nextval('geo_plan.address_id_seq'::regclass);


--
-- Name: adj_except id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.adj_except ALTER COLUMN id SET DEFAULT nextval('geo_plan.adj_except_id_seq'::regclass);


--
-- Name: boundary id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary ALTER COLUMN id SET DEFAULT nextval('geo_plan.boundary_id_seq'::regclass);


--
-- Name: boundary_group id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary_group ALTER COLUMN id SET DEFAULT nextval('geo_plan.boundary_group_id_seq'::regclass);


--
-- Name: export_file id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.export_file ALTER COLUMN id SET DEFAULT nextval('geo_plan.export_file_id_seq'::regclass);


--
-- Name: landmark id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.landmark ALTER COLUMN id SET DEFAULT nextval('geo_plan.landmark_id_seq'::regclass);


--
-- Name: legal_description id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.legal_description ALTER COLUMN id SET DEFAULT nextval('geo_plan.legal_description_id_seq'::regclass);


--
-- Name: location id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.location ALTER COLUMN id SET DEFAULT nextval('geo_plan.location_id_seq'::regclass);


--
-- Name: mile_marker id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.mile_marker ALTER COLUMN id SET DEFAULT nextval('geo_plan.mile_marker_id_seq'::regclass);


--
-- Name: node id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.node ALTER COLUMN id SET DEFAULT nextval('geo_plan.node_id_seq'::regclass);


--
-- Name: parsing id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.parsing ALTER COLUMN id SET DEFAULT nextval('geo_plan.parsing_id_seq'::regclass);


--
-- Name: segment id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.segment ALTER COLUMN id SET DEFAULT nextval('geo_plan.segment_id_seq'::regclass);


--
-- Name: street id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.street ALTER COLUMN id SET DEFAULT nextval('geo_plan.street_id_seq'::regclass);


--
-- Name: street_segment id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.street_segment ALTER COLUMN id SET DEFAULT nextval('geo_plan.street_segment_id_seq'::regclass);


--
-- Name: zipcode id; Type: DEFAULT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.zipcode ALTER COLUMN id SET DEFAULT nextval('geo_plan.zipcode_id_seq'::regclass);


--
-- Name: i_type id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.i_type ALTER COLUMN id SET DEFAULT nextval('ivin.i_type_id_seq'::regclass);


--
-- Name: i_zone id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.i_zone ALTER COLUMN id SET DEFAULT nextval('ivin.i_zone_id_seq'::regclass);


--
-- Name: image id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.image ALTER COLUMN id SET DEFAULT nextval('ivin.image_id_seq'::regclass);


--
-- Name: inspection id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection ALTER COLUMN id SET DEFAULT nextval('ivin.inspection_id_seq'::regclass);


--
-- Name: inspection_point id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_point ALTER COLUMN id SET DEFAULT nextval('ivin.inspection_point_id_seq'::regclass);


--
-- Name: inspection_zone id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_zone ALTER COLUMN id SET DEFAULT nextval('ivin.inspection_zone_id_seq'::regclass);


--
-- Name: template id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template ALTER COLUMN id SET DEFAULT nextval('ivin.template_id_seq'::regclass);


--
-- Name: template_point id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point ALTER COLUMN id SET DEFAULT nextval('ivin.template_point_id_seq'::regclass);


--
-- Name: template_point_validation id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation ALTER COLUMN id SET DEFAULT nextval('ivin.template_point_validation_id_seq'::regclass);


--
-- Name: template_point_validation_type id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation_type ALTER COLUMN id SET DEFAULT nextval('ivin.template_point_validation_type_id_seq'::regclass);


--
-- Name: template_zone id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_zone ALTER COLUMN id SET DEFAULT nextval('ivin.template_zone_id_seq'::regclass);


--
-- Name: validation_type id; Type: DEFAULT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.validation_type ALTER COLUMN id SET DEFAULT nextval('ivin.validation_type_id_seq'::regclass);


--
-- Name: report_info id; Type: DEFAULT; Schema: public; Owner: edulog
--

ALTER TABLE ONLY public.report_info ALTER COLUMN id SET DEFAULT nextval('public.report_info_id_seq'::regclass);


--
-- Name: access id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access ALTER COLUMN id SET DEFAULT nextval('rp_master.access_id_seq'::regclass);


--
-- Name: access_domain id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access_domain ALTER COLUMN id SET DEFAULT nextval('rp_master.access_domains_id_seq'::regclass);


--
-- Name: access_school id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access_school ALTER COLUMN id SET DEFAULT nextval('rp_master.access_schools_id_seq'::regclass);


--
-- Name: authentication_scope id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.authentication_scope ALTER COLUMN id SET DEFAULT nextval('rp_master.authentication_scope_id_seq'::regclass);


--
-- Name: avl_event id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_event ALTER COLUMN id SET DEFAULT nextval('rp_master.avl_event_id_seq'::regclass);


--
-- Name: avl_template id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_template ALTER COLUMN id SET DEFAULT nextval('rp_master.avl_template_id_seq'::regclass);


--
-- Name: cal id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal ALTER COLUMN id SET DEFAULT nextval('rp_master.cal_id_seq'::regclass);


--
-- Name: cal_cal_event id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal_cal_event ALTER COLUMN id SET DEFAULT nextval('rp_master.cal_cal_event_id_seq'::regclass);


--
-- Name: cal_event id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal_event ALTER COLUMN id SET DEFAULT nextval('rp_master.cal_event_id_seq'::regclass);


--
-- Name: data_area id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area ALTER COLUMN id SET DEFAULT nextval('rp_master.data_area_id_seq'::regclass);


--
-- Name: import_value_mapping id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.import_value_mapping ALTER COLUMN id SET DEFAULT nextval('rp_master.import_value_mapping_id_seq'::regclass);


--
-- Name: plan_rollover id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.plan_rollover ALTER COLUMN id SET DEFAULT nextval('rp_master.plan_rollover_id_seq'::regclass);


--
-- Name: plan_rollover_log_items id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.plan_rollover_log_items ALTER COLUMN id SET DEFAULT nextval('rp_master.plan_rollover_log_items_id_seq'::regclass);


--
-- Name: role_permissions id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.role_permissions ALTER COLUMN id SET DEFAULT nextval('rp_master.role_permissions_id_seq'::regclass);


--
-- Name: student_import_conf id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.student_import_conf ALTER COLUMN id SET DEFAULT nextval('rp_master.student_import_conf_id_seq'::regclass);


--
-- Name: student_import_mapping id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.student_import_mapping ALTER COLUMN id SET DEFAULT nextval('rp_master.student_import_mapping_id_seq'::regclass);


--
-- Name: user id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master."user" ALTER COLUMN id SET DEFAULT nextval('rp_master.user_id_seq'::regclass);


--
-- Name: user_profile id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile ALTER COLUMN id SET DEFAULT nextval('rp_master.user_profile_id_seq'::regclass);


--
-- Name: user_profile_template id; Type: DEFAULT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template ALTER COLUMN id SET DEFAULT nextval('rp_master.user_profile_template_id_seq'::regclass);


--
-- Name: belltime id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.belltime ALTER COLUMN id SET DEFAULT nextval('rp_plan.belltime_id_seq'::regclass);


--
-- Name: cluster id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster ALTER COLUMN id SET DEFAULT nextval('rp_plan.cluster_id_seq'::regclass);


--
-- Name: cluster_belltime id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster_belltime ALTER COLUMN id SET DEFAULT nextval('rp_plan.cluster_belltime_id_seq'::regclass);


--
-- Name: contact id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contact ALTER COLUMN id SET DEFAULT nextval('rp_plan.contact_id_seq'::regclass);


--
-- Name: contractor id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contractor ALTER COLUMN id SET DEFAULT nextval('rp_plan.contractor_id_seq'::regclass);


--
-- Name: direction_step id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.direction_step ALTER COLUMN id SET DEFAULT nextval('rp_plan.direction_step_id_seq'::regclass);


--
-- Name: district_eligibility id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.district_eligibility ALTER COLUMN id SET DEFAULT nextval('rp_plan.district_eligibility_id_seq'::regclass);


--
-- Name: domain id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.domain ALTER COLUMN id SET DEFAULT nextval('rp_plan.domain_id_seq'::regclass);


--
-- Name: eligibility_rule id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.eligibility_rule ALTER COLUMN id SET DEFAULT nextval('rp_plan.eligibility_rule_id_seq'::regclass);


--
-- Name: gps_unit id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.gps_unit ALTER COLUMN id SET DEFAULT nextval('rp_plan.gps_id_seq'::regclass);


--
-- Name: grade id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.grade ALTER COLUMN id SET DEFAULT nextval('rp_plan.grade_id_seq'::regclass);


--
-- Name: hazard_zone id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.hazard_zone ALTER COLUMN id SET DEFAULT nextval('rp_plan.hazard_zone_id_seq'::regclass);


--
-- Name: head_count id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.head_count ALTER COLUMN id SET DEFAULT nextval('rp_plan.head_count_id_seq'::regclass);


--
-- Name: inactive_student id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student ALTER COLUMN id SET DEFAULT nextval('rp_plan.inactive_student_id_seq'::regclass);


--
-- Name: load_time id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.load_time ALTER COLUMN id SET DEFAULT nextval('rp_plan.load_time_id_seq'::regclass);


--
-- Name: location id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.location ALTER COLUMN id SET DEFAULT nextval('rp_plan.location_id_seq'::regclass);


--
-- Name: medical_note id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.medical_note ALTER COLUMN id SET DEFAULT nextval('rp_plan.medical_note_id_seq'::regclass);


--
-- Name: need id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.need ALTER COLUMN id SET DEFAULT nextval('rp_plan.need_id_seq'::regclass);


--
-- Name: path_cover id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_cover ALTER COLUMN id SET DEFAULT nextval('rp_plan.path_cover_id_seq'::regclass);


--
-- Name: path_master id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_master ALTER COLUMN id SET DEFAULT nextval('rp_plan.path_master_id_seq'::regclass);


--
-- Name: program id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.program ALTER COLUMN id SET DEFAULT nextval('rp_plan.program_id_seq'::regclass);


--
-- Name: route id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route ALTER COLUMN id SET DEFAULT nextval('rp_plan.route_id_seq'::regclass);


--
-- Name: route_contact id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_contact ALTER COLUMN id SET DEFAULT nextval('rp_plan.route_contact_id_seq'::regclass);


--
-- Name: route_run id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_run ALTER COLUMN id SET DEFAULT nextval('rp_plan.route_run_id_seq'::regclass);


--
-- Name: run id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.run ALTER COLUMN id SET DEFAULT nextval('rp_plan.run_id_seq'::regclass);


--
-- Name: school id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_id_seq'::regclass);


--
-- Name: school_contact id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_contact ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_contact_id_seq'::regclass);


--
-- Name: school_district id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_district ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_district_id_seq'::regclass);


--
-- Name: school_location id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_location ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_location_id_seq'::regclass);


--
-- Name: school_operation_cover id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_cover ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_operation_cover_id_seq'::regclass);


--
-- Name: school_operation_master id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_operation_master_id_seq'::regclass);


--
-- Name: school_operation_master_boundary id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master_boundary ALTER COLUMN id SET DEFAULT nextval('rp_plan.school_operation_master_boundary_id_seq'::regclass);


--
-- Name: site_meta_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_meta_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_meta_data_id_seq'::regclass);


--
-- Name: site_route_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_route_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_route_data_id_seq'::regclass);


--
-- Name: site_run_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_run_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_run_data_id_seq'::regclass);


--
-- Name: site_school_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_school_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_school_data_id_seq'::regclass);


--
-- Name: site_stop_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_stop_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_stop_data_id_seq'::regclass);


--
-- Name: site_student_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_student_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_student_data_id_seq'::regclass);


--
-- Name: site_trip_data id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_trip_data ALTER COLUMN id SET DEFAULT nextval('rp_plan.site_trip_data_id_seq'::regclass);


--
-- Name: stop id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.stop ALTER COLUMN id SET DEFAULT nextval('rp_plan.stop_id_seq'::regclass);


--
-- Name: student id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student ALTER COLUMN id SET DEFAULT nextval('rp_plan.student_id_seq'::regclass);


--
-- Name: student_contact id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_contact ALTER COLUMN id SET DEFAULT nextval('rp_plan.student_contact_id_seq'::regclass);


--
-- Name: student_import_line id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_import_line ALTER COLUMN id SET DEFAULT nextval('rp_plan.student_import_line_id_seq'::regclass);


--
-- Name: student_import_line athena_id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_import_line ALTER COLUMN athena_id SET DEFAULT nextval('rp_plan.student_import_line_athena_id_seq'::regclass);


--
-- Name: student_need id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_need ALTER COLUMN id SET DEFAULT nextval('rp_plan.student_need_id_seq'::regclass);


--
-- Name: student_note id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_note ALTER COLUMN id SET DEFAULT nextval('rp_plan.student_note_id_seq'::regclass);


--
-- Name: student_note student_id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_note ALTER COLUMN student_id SET DEFAULT nextval('rp_plan.student_note_student_id_seq'::regclass);


--
-- Name: student_transport_need id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_transport_need ALTER COLUMN id SET DEFAULT nextval('rp_plan.student_transport_need_id_seq'::regclass);


--
-- Name: transport_def_cover id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_cover ALTER COLUMN id SET DEFAULT nextval('rp_plan.transport_def_cover_id_seq'::regclass);


--
-- Name: transport_def_master id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master ALTER COLUMN id SET DEFAULT nextval('rp_plan.transport_def_master_id_seq'::regclass);


--
-- Name: transport_itinerary id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_itinerary ALTER COLUMN id SET DEFAULT nextval('rp_plan.transport_itinerary_id_seq'::regclass);


--
-- Name: transport_need id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_need ALTER COLUMN id SET DEFAULT nextval('rp_plan.transport_need_id_seq'::regclass);


--
-- Name: transport_request id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request ALTER COLUMN id SET DEFAULT nextval('rp_plan.transport_request_id_seq'::regclass);


--
-- Name: transport_request_detail id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request_detail ALTER COLUMN id SET DEFAULT nextval('rp_plan.transport_request_detail_id_seq'::regclass);


--
-- Name: trip_cover id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_cover ALTER COLUMN id SET DEFAULT nextval('rp_plan.trip_cover_id_seq'::regclass);


--
-- Name: trip_leg id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg ALTER COLUMN id SET DEFAULT nextval('rp_plan.trip_leg_id_seq'::regclass);


--
-- Name: trip_leg_waypoint_master id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master ALTER COLUMN id SET DEFAULT nextval('rp_plan.trip_leg_waypoint_master_id_seq'::regclass);


--
-- Name: trip_master id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_master ALTER COLUMN id SET DEFAULT nextval('rp_plan.trip_master_id_seq'::regclass);


--
-- Name: vehicle id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle ALTER COLUMN id SET DEFAULT nextval('rp_plan.vehicle_id_seq'::regclass);


--
-- Name: vehicle_maintenance id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_maintenance ALTER COLUMN id SET DEFAULT nextval('rp_plan.vehicle_maintenance_id_seq'::regclass);


--
-- Name: vehicle_transport_need id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_transport_need ALTER COLUMN id SET DEFAULT nextval('rp_plan.vehicle_transport_need_id_seq'::regclass);


--
-- Name: waypoint_cover id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover ALTER COLUMN id SET DEFAULT nextval('rp_plan.waypoint_cover_id_seq'::regclass);


--
-- Name: waypoint_cover_belltime id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover_belltime ALTER COLUMN id SET DEFAULT nextval('rp_plan.waypoint_cover_belltime_id_seq'::regclass);


--
-- Name: waypoint_master id; Type: DEFAULT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_master ALTER COLUMN id SET DEFAULT nextval('rp_plan.waypoint_master_id_seq'::regclass);


--
-- Data for Name: activity; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.activity (id, code, name_of) FROM stdin;
\.


--
-- Data for Name: billing_type; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.billing_type (id, code, name_of) FROM stdin;
\.


--
-- Data for Name: certification; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.certification (id, type_of, no_of, description, iss_date, exp_date, comment, driver_info_id) FROM stdin;
\.


--
-- Data for Name: department; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.department (id, name_of) FROM stdin;
\.


--
-- Data for Name: district; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.district (id, name_of) FROM stdin;
\.


--
-- Data for Name: driver_class; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.driver_class (id, name_of) FROM stdin;
\.


--
-- Data for Name: driver_info; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.driver_info (id, employee_id, initial, first_name, last_name, birth_day, is_temporary, work_phone, home_phone, email, description, note, is_active, no_of, state_code_license, expire, driver_district_id, fuel_card, call_board, retriction, address, state_code_contact, city, zip, employer, supervisor, date_hire, date_terminated, sequence_number, type_of, frequency, rate, per, leave_rate, emergency_contact_name, emergency_address, relation, license_class_id, driver_class_id, union_id, seniority_id, district_id, emp_class_id, grade_id, level_id, emp_group_id, scale_hour_id, billing_type_id, department_id, work_group_id) FROM stdin;
\.


--
-- Data for Name: driver_skill; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.driver_skill (driver_info_id, skill_id) FROM stdin;
\.


--
-- Data for Name: emp_class; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.emp_class (id, name_of) FROM stdin;
\.


--
-- Data for Name: emp_group; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.emp_group (id, name_of) FROM stdin;
\.


--
-- Data for Name: grade; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.grade (id, name_of) FROM stdin;
\.


--
-- Data for Name: image; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.image (id, name_of, type_of, data, driver_info_id) FROM stdin;
\.


--
-- Data for Name: level; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.level (id, name_of) FROM stdin;
\.


--
-- Data for Name: license_class; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.license_class (id, name_of) FROM stdin;
\.


--
-- Data for Name: ridership; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.ridership (id, log_date, edulog_id, route, run, ts_pu_ac_bus, ts_pu_ac_driver, ts_pu_ac_stopid, ts_pu_ac_stoptime, ts_pu_ac_desc, ts_pu_ac_status, ts_pu_ac_latlong, ts_pu_pl_bus, ts_pu_pl_stopid, ts_pu_pl_stoptime, ts_pu_pl_desc, ts_do_ac_schoolname, ts_do_ac_arrivaltime, ts_do_ac_status, ts_do_ac_latlong, ts_do_pl_schoolname, ts_do_pl_arrivaltime, fs_pu_ac_bus, fs_pu_ac_driver, fs_pu_ac_schoolcode, fs_pu_ac_departtime, fs_pu_ac_schoolname, fs_pu_ac_status, fs_pu_ac_latlong, fs_pu_pl_schoolcode, fs_pu_pl_departtime, fs_pu_pl_schoolname, fs_do_ac_stopid, fs_do_ac_stoptime, fs_do_ac_desc, fs_do_ac_status, fs_do_ac_latlong, fs_do_pl_stopid, fs_do_pl_stoptime, fs_do_pl_desc) FROM stdin;
\.


--
-- Data for Name: scale_hour; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.scale_hour (id, value_of) FROM stdin;
\.


--
-- Data for Name: search; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.search (id, name_of, is_last, is_append, search_json, driver_info_id) FROM stdin;
\.


--
-- Data for Name: seniority; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.seniority (id, name_of) FROM stdin;
\.


--
-- Data for Name: skill; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.skill (id, name_of) FROM stdin;
\.


--
-- Data for Name: state; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.state (code, description) FROM stdin;
\.


--
-- Data for Name: student; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.student (id, edulogid, firstname, lastname, school, grade, program, district, rfid) FROM stdin;
\.


--
-- Data for Name: training; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.training (id, type_of, class_of, start_date, end_date, repeat, frequency, driver_info_id) FROM stdin;
\.


--
-- Data for Name: transaction; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.transaction (id, date_of, login, logout, pay_period, supervisor, status, comment, record_time, created_by, vehicle_id, source_type, parent_id, driver_info_id, billing_type_id, activity_id) FROM stdin;
\.


--
-- Data for Name: union; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta."union" (id, name_of) FROM stdin;
\.


--
-- Data for Name: work_group; Type: TABLE DATA; Schema: edta; Owner: edulog
--

COPY edta.work_group (id, name_of) FROM stdin;
\.


--
-- Data for Name: config; Type: TABLE DATA; Schema: geo_master; Owner: edulog
--

COPY geo_master.config (id, application, setting, value, description) FROM stdin;
\.


--
-- Data for Name: geoserver_layer; Type: TABLE DATA; Schema: geo_master; Owner: edulog
--

COPY geo_master.geoserver_layer (id, display_name, display_order, description) FROM stdin;
\.


--
-- Data for Name: address; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.address (id, location_id, number_of, number_of_suffix, alpha, contact) FROM stdin;
\.


--
-- Data for Name: adj_except; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.adj_except (id, from_segment_id, from_right_side, to_segment_id, to_right_side) FROM stdin;
\.


--
-- Data for Name: boundary; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.boundary (id, code, import_id, description, notes, locked, time_changed, geo, surrogate_key) FROM stdin;
\.


--
-- Data for Name: boundary_group; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.boundary_group (id, code, description) FROM stdin;
1	ATTENDANCE	Attendance
2	WALK	Walking
3	HAZARD	Hazard
4	PREMISE	Premise
5	PARKING	Parking
6	<<booked>>6	Input description
7	<<booked>>7	Input description
8	<<booked>>8	Input description
9	<<booked>>9	Input description
10	<<booked>>10	Input description
11	<<booked>>11	Input description
12	<<booked>>12	Input description
13	<<booked>>13	Input description
14	<<booked>>14	Input description
15	<<booked>>15	Input description
16	<<booked>>16	Input description
17	<<booked>>17	Input description
18	<<booked>>18	Input description
19	<<booked>>19	Input description
20	<<booked>>20	Input description
21	<<booked>>21	Input description
22	<<booked>>22	Input description
23	<<booked>>23	Input description
24	<<booked>>24	Input description
25	<<booked>>25	Input description
26	<<booked>>26	Input description
27	<<booked>>27	Input description
28	<<booked>>28	Input description
29	<<booked>>29	Input description
30	<<booked>>30	Input description
31	<<booked>>31	Input description
32	<<booked>>32	Input description
33	<<booked>>33	Input description
34	<<booked>>34	Input description
35	<<booked>>35	Input description
36	<<booked>>36	Input description
37	<<booked>>37	Input description
38	<<booked>>38	Input description
39	<<booked>>39	Input description
40	<<booked>>40	Input description
41	<<booked>>41	Input description
42	<<booked>>42	Input description
43	<<booked>>43	Input description
44	<<booked>>44	Input description
45	<<booked>>45	Input description
46	<<booked>>46	Input description
47	<<booked>>47	Input description
48	<<booked>>48	Input description
49	<<booked>>49	Input description
50	<<booked>>50	Input description
51	<<booked>>51	Input description
52	<<booked>>52	Input description
53	<<booked>>53	Input description
54	<<booked>>54	Input description
55	<<booked>>55	Input description
56	<<booked>>56	Input description
57	<<booked>>57	Input description
58	<<booked>>58	Input description
59	<<booked>>59	Input description
60	<<booked>>60	Input description
61	<<booked>>61	Input description
62	<<booked>>62	Input description
63	<<booked>>63	Input description
64	<<booked>>64	Input description
65	<<booked>>65	Input description
66	<<booked>>66	Input description
67	<<booked>>67	Input description
68	<<booked>>68	Input description
69	<<booked>>69	Input description
70	<<booked>>70	Input description
71	<<booked>>71	Input description
72	<<booked>>72	Input description
73	<<booked>>73	Input description
74	<<booked>>74	Input description
75	<<booked>>75	Input description
76	<<booked>>76	Input description
77	<<booked>>77	Input description
78	<<booked>>78	Input description
79	<<booked>>79	Input description
80	<<booked>>80	Input description
81	<<booked>>81	Input description
82	<<booked>>82	Input description
83	<<booked>>83	Input description
84	<<booked>>84	Input description
85	<<booked>>85	Input description
86	<<booked>>86	Input description
87	<<booked>>87	Input description
88	<<booked>>88	Input description
89	<<booked>>89	Input description
90	<<booked>>90	Input description
91	<<booked>>91	Input description
92	<<booked>>92	Input description
93	<<booked>>93	Input description
94	<<booked>>94	Input description
95	<<booked>>95	Input description
96	<<booked>>96	Input description
97	<<booked>>97	Input description
98	<<booked>>98	Input description
99	<<booked>>99	Input description
\.


--
-- Data for Name: boundary_group_mapping; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.boundary_group_mapping (boundary_id, boundary_group_id, posted) FROM stdin;
\.


--
-- Data for Name: export_file; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.export_file (id, file_name, url_file, status, percent, time_created, time_changed, type) FROM stdin;
\.


--
-- Data for Name: landmark; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.landmark (id, location_id, name_of, alt_name, type_of) FROM stdin;
\.


--
-- Data for Name: legal_description; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.legal_description (id, location_id, meridian, township, range_of, section_of, section_of_div) FROM stdin;
\.


--
-- Data for Name: location; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.location (id, import_id, street_segment_id, right_side, percent_along, notes, orig_geo, calc_geo, opt_geo, source_of, external_address, effect_from_date, effect_to_date, created_at, updated_at, changed, deleted) FROM stdin;
\.


--
-- Data for Name: mile_marker; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.mile_marker (id, location_id, percent_along, address_number) FROM stdin;
\.


--
-- Data for Name: node; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.node (id, geo) FROM stdin;
\.


--
-- Data for Name: parsing; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.parsing (id, type_of, accept, fix) FROM stdin;
\.


--
-- Data for Name: segment; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.segment (id, hazard1, hazard2, hazard3, hazard4, from_flow, to_flow, walk_across, from_node, to_node, width, left_zip_code, left_community, left_speed1, left_speed2, left_speed3, left_speed4, left_speed5, left_speed6, left_posted_speed, left_drive, left_walk1, left_walk2, left_walk3, left_walk4, right_zip_code, right_community, right_speed1, right_speed2, right_speed3, right_speed4, right_speed5, right_speed6, right_posted_speed, right_drive, right_walk1, right_walk2, right_walk3, right_walk4, base_id, start_date, end_date, geo, geom_geoserver, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: street; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.street (id, prefix_of, name_of, type_of, suffix) FROM stdin;
\.


--
-- Data for Name: street_segment; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.street_segment (id, street_id, segment_id, left_from_address, left_to_address, right_from_address, right_to_address, feature_class, primary_segment, reversed_geo) FROM stdin;
\.


--
-- Data for Name: zipcode; Type: TABLE DATA; Schema: geo_plan; Owner: edulog
--

COPY geo_plan.zipcode (id, zip, city) FROM stdin;
\.


--
-- Data for Name: i_type; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.i_type (id, name_of) FROM stdin;
\.


--
-- Data for Name: i_zone; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.i_zone (id, description, image_id) FROM stdin;
\.


--
-- Data for Name: image; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.image (id, name_of, type_of, data) FROM stdin;
\.


--
-- Data for Name: inspection; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.inspection (id, name_of, vehicle_id, mdt_id, driver_id, last_name, first_name, date_of, status, odometer, start_time, end_time, duration_second, avg_duration_second, defect, action_of, unsafe, reason, modified_user, modified_date, created_date, template_id) FROM stdin;
\.


--
-- Data for Name: inspection_point; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.inspection_point (id, status, note, inspection_zone_id, template_point_id, image_id, template_point_validation_id) FROM stdin;
\.


--
-- Data for Name: inspection_zone; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.inspection_zone (id, status, inspection_id, i_zone_id) FROM stdin;
\.


--
-- Data for Name: template; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.template (id, name_of, status, created_date_time, created_date, created_by, i_type_id) FROM stdin;
\.


--
-- Data for Name: template_point; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.template_point (id, description, is_critical, is_walk_around, is_power_on, template_zone_id, image_id) FROM stdin;
\.


--
-- Data for Name: template_point_validation; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.template_point_validation (id, order_of, description, template_point_validation_type_id) FROM stdin;
\.


--
-- Data for Name: template_point_validation_type; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.template_point_validation_type (id, template_point_id, validation_type_id) FROM stdin;
\.


--
-- Data for Name: template_zone; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.template_zone (id, template_id, i_zone_id) FROM stdin;
\.


--
-- Data for Name: validation_type; Type: TABLE DATA; Schema: ivin; Owner: edulog
--

COPY ivin.validation_type (id, description) FROM stdin;
\.


--
-- Data for Name: flyway_schema_history; Type: TABLE DATA; Schema: public; Owner: edulog
--

COPY public.flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
1	1.000	 Initial Schema	SQL	V1.000__Initial_Schema.sql	-1835402115	edulog	2020-07-18 23:03:39.073255	1106	t
2	1.001	 District Eligibility	SQL	V1.001__District_Eligibility.sql	1437386594	edulog	2020-07-18 23:03:40.200098	11	t
3	1.002	 Update Contacts	SQL	V1.002__Update_Contacts.sql	715809704	edulog	2020-07-18 23:03:40.216336	4	t
4	1.003	 TR Denied to Rejected Status	SQL	V1.003__TR_Denied_to_Rejected_Status.sql	-1957266663	edulog	2020-07-18 23:03:40.223564	2	t
5	1.004	 Add Vehicle Table	SQL	V1.004__Add_Vehicle_Table.sql	-294536344	edulog	2020-07-18 23:03:40.229374	14	t
6	2.000	 Update Multi Cover Support	SQL	V2.000__Update_Multi_Cover_Support.sql	1673229542	edulog	2020-07-18 23:03:40.249276	45	t
7	2.001	 Add Bell Times On Walk Paths	SQL	V2.001__Add_Bell_Times_On_Walk_Paths.sql	-23331641	edulog	2020-07-18 23:03:40.298963	3	t
8	2.002	 Add Stop Active	SQL	V2.002__Add_Stop_Active.sql	-1436412535	edulog	2020-07-18 23:03:40.305895	4	t
9	2.003	 inactivated student data	SQL	V2.003__inactivated_student_data.sql	1415246562	edulog	2020-07-18 23:03:40.313699	9	t
10	2.004	 Remove Trips for NonFinal TRs	SQL	V2.004__Remove_Trips_for_NonFinal_TRs.sql	-778404108	edulog	2020-07-18 23:03:40.327424	5	t
11	2.005	 User Management Tables	SQL	V2.005__User_Management_Tables.sql	-1345321540	edulog	2020-07-18 23:03:40.336026	17	t
12	2.006	 Calendar and Rollover Tables	SQL	V2.006__Calendar_and_Rollover_Tables.sql	850886303	edulog	2020-07-18 23:03:40.358027	12	t
13	2.007	 Increase Waypoint Description Length	SQL	V2.007__Increase_Waypoint_Description_Length.sql	-1441796114	edulog	2020-07-18 23:03:40.375109	2	t
14	2.008	 Calendar and Rollover Table Mods	SQL	V2.008__Calendar_and_Rollover_Table_Mods.sql	1248161702	edulog	2020-07-18 23:03:40.3796	2	t
15	2.009	 Add Gps DeviceId	SQL	V2.009__Add_Gps_DeviceId.sql	-369982840	edulog	2020-07-18 23:03:40.386201	2	t
16	2.010	 Add Max Assign Dist	SQL	V2.010__Add_Max_Assign_Dist.sql	1986082233	edulog	2020-07-18 23:03:40.392584	1	t
17	2.011	 Access Management	SQL	V2.011__Access_Management.sql	-2049021688	edulog	2020-07-18 23:03:40.396968	17	t
18	2.012	 Add Plan Rollover Log Table	SQL	V2.012__Add_Plan_Rollover_Log_Table.sql	1240503011	edulog	2020-07-18 23:03:40.419229	5	t
19	2.013	 Role Permissions Table	SQL	V2.013__Role_Permissions_Table.sql	-1726542837	edulog	2020-07-18 23:03:40.429115	9	t
20	2.014	 school district update	SQL	V2.014__school_district_update.sql	1507848293	edulog	2020-07-18 23:03:40.443518	3	t
21	2.015	 Fix Vin Type	SQL	V2.015__Fix_Vin_Type.sql	-150389474	edulog	2020-07-18 23:03:40.450081	1	t
22	2.016	 Initial Report Functions	SQL	V2.016__Initial_Report_Functions.sql	1176482092	edulog	2020-07-18 23:03:40.454369	10	t
23	2.017	 GeoCode	SQL	V2.017__GeoCode.sql	927029896	edulog	2020-07-18 23:03:40.468977	46	t
24	2.018	 Update TR Structure For Eff Dates	SQL	V2.018__Update_TR_Structure_For_Eff_Dates.sql	1379037620	edulog	2020-07-18 23:03:40.520634	26	t
25	2.019	 GeoCode Boundary	SQL	V2.019__GeoCode_Boundary.sql	-144711022	edulog	2020-07-18 23:03:40.552081	8	t
26	2.020	 Add StudentImportTables	SQL	V2.020__Add_StudentImportTables.sql	-398732669	edulog	2020-07-18 23:03:40.568026	22	t
27	2.021	 Fix BoundaryCode Type	SQL	V2.021__Fix_BoundaryCode_Type.sql	-1521420475	edulog	2020-07-18 23:03:40.59163	4	t
28	2.022	 Add Calendar Table	SQL	V2.022__Add_Calendar_Table.sql	1841516164	edulog	2020-07-18 23:03:40.599502	10	t
29	2.023	 Updating student imp related tables	SQL	V2.023__Updating_student_imp_related_tables.sql	-1910154654	edulog	2020-07-18 23:03:40.613533	3	t
30	2.024	 Add Edta Schema Tables backup	SQL	V2.024__Add_Edta_Schema_Tables_backup.sql	1913517184	edulog	2020-07-18 23:03:40.620023	109	t
31	2.025	 Add Ivin Schema Tables backup	SQL	V2.025__Add_Ivin_Schema_Tables_backup.sql	-1514393161	edulog	2020-07-18 23:03:40.737496	24	t
32	2.026	 Fix Calendar Table	SQL	V2.026__Fix_Calendar_Table.sql	-1734003985	edulog	2020-07-18 23:03:40.765715	5	t
33	2.027	 Updating StudImp Tables	SQL	V2.027__Updating_StudImp_Tables.sql	-1669818610	edulog	2020-07-18 23:03:40.773962	1	t
34	2.028	 Update Boundary Seq	SQL	V2.028__Update_Boundary_Seq.sql	-165076124	edulog	2020-07-18 23:03:40.77838	1	t
35	2.029	 Add Vehicle Service Table	SQL	V2.029__Add_Vehicle_Service_Table.sql	1874881145	edulog	2020-07-18 23:03:40.781992	3	t
36	2.030	 Vehicle Route Contractor Updates	SQL	V2.030__Vehicle_Route_Contractor_Updates.sql	-2034161314	edulog	2020-07-18 23:03:40.787718	20	t
37	2.031	 Fix Extra End Of Path Dir Steps	SQL	V2.031__Fix_Extra_End_Of_Path_Dir_Steps.sql	-1476256081	edulog	2020-07-18 23:03:40.812013	0	t
38	2.032	 Fixed Aggregation Supervisor Driver Time Attendance	SQL	V2.032__Fixed_Aggregation_Supervisor_Driver_Time_Attendance.sql	1399287747	edulog	2020-07-18 23:03:40.815442	4	t
39	2.033	 Fix StudentImp config	SQL	V2.033__Fix_StudentImp_config.sql	1805609036	edulog	2020-07-18 23:03:40.822276	6	t
40	2.034	 StudentImp mapping	SQL	V2.034__StudentImp_mapping.sql	1213966813	edulog	2020-07-18 23:03:40.832253	2	t
41	2.035	 StudImp mapping	SQL	V2.035__StudImp_mapping.sql	1227478161	edulog	2020-07-18 23:03:40.836891	5	t
42	2.036	 StudImp adjustColumn	SQL	V2.036__StudImp_adjustColumn.sql	-483518222	edulog	2020-07-18 23:03:40.846729	1	t
43	2.037	 Update Plan Rollover And Removal Calendar	SQL	V2.037__Update_Plan_Rollover_And_Removal_Calendar.sql	-1309002373	edulog	2020-07-18 23:03:40.850721	11	t
44	2.038	 Report Tables	SQL	V2.038__Report_Tables.sql	-1697893018	edulog	2020-07-18 23:03:40.867638	4	t
45	2.039	 Routing Data Area Schema Separation	SQL	V2.039__Routing_Data_Area_Schema_Separation.sql	-2025071700	edulog	2020-07-18 23:03:40.876662	49	t
46	2.040	 Data Area Functions	SQL	V2.040__Data_Area_Functions.sql	-1002796147	edulog	2020-07-18 23:03:40.930684	6	t
47	2.041	 GEO Add posts to boundary add boundary group	SQL	V2.041__GEO_Add_posts_to_boundary_add_boundary_group.sql	1037532868	edulog	2020-07-18 23:03:40.939071	5	t
48	2.042	 Report Tables	SQL	V2.042__Report_Tables.sql	942219105	edulog	2020-07-18 23:03:40.94857	1	t
49	2.043	 DA Create Boundary Group Post	SQL	V2.043__DA_Create_Boundary_Group_Post.sql	-1196213688	edulog	2020-07-18 23:03:40.952664	12	t
50	2.044	 DA Add Eligibility Rule	SQL	V2.044__DA_Add_Eligibility_Rule.sql	1018040554	edulog	2020-07-18 23:03:40.971956	13	t
51	2.045	 Fix Routing User Audit Columns	SQL	V2.045__Fix_Routing_User_Audit_Columns.sql	-211648470	edulog	2020-07-18 23:03:40.989387	7	t
52	2.046	 DA Fix Boundary Group Sequence	SQL	V2.046__DA_Fix_Boundary_Group_Sequence.sql	816274931	edulog	2020-07-18 23:03:40.999679	1	t
53	2.047	 Fix User And Cal Table Sequences	SQL	V2.047__Fix_User_And_Cal_Table_Sequences.sql	2001429657	edulog	2020-07-18 23:03:41.003727	5	t
54	2.048	 DA Posting With No Boundary	SQL	V2.048__DA_Posting_With_No_Boundary.sql	2126753566	edulog	2020-07-18 23:03:41.012356	1	t
55	2.049	 DA Plan Add Indexes To FKs	SQL	V2.049__DA_Plan_Add_Indexes_To_FKs.sql	1718012063	edulog	2020-07-18 23:03:41.020268	60	t
56	2.050	 CreateExtension	SQL	V2.050__CreateExtension.sql	-1148974962	edulog	2020-07-18 23:03:41.08311	5	t
57	2.051	 DA Add Dynamic Frequency Property	SQL	V2.051__DA_Add_Dynamic_Frequency_Property.sql	421415597	edulog	2020-07-18 23:03:41.091771	1	t
58	2.052	 DA FixDynamicFreqValues	SQL	V2.052__DA_FixDynamicFreqValues.sql	-150819789	edulog	2020-07-18 23:03:41.095172	7	t
59	2.053	 DA Add Column Extend Point Info	SQL	V2.053__DA_Add_Column_Extend_Point_Info.sql	651183544	edulog	2020-07-18 23:03:41.106092	1	t
60	2.054	 Add Column Report Title	SQL	V2.054__Add_Column_Report_Title.sql	-1433223858	edulog	2020-07-18 23:03:41.110157	1	t
61	2.055	 DA Append Boundary Group	SQL	V2.055__DA_Append_Boundary_Group.sql	1812251679	edulog	2020-07-18 23:03:41.11472	6	t
62	2.056	 Remove Column Mapping Fields	SQL	V2.056__Remove_Column_Mapping_Fields.sql	1184069717	edulog	2020-07-18 23:03:41.124542	1	t
63	2.057	 Reports Modify column user name	SQL	V2.057__Reports_Modify_column_user_name.sql	-2095736535	edulog	2020-07-18 23:03:41.127826	0	t
64	2.058	 DA Location Add Changed Deleted	SQL	V2.058__DA_Location_Add_Changed_Deleted.sql	-690857263	edulog	2020-07-18 23:03:41.130724	1	t
65	2.058.01	 DA Segment Add Updated Created Column	SQL	V2.058.01__DA_Segment_Add_Updated_Created_Column.sql	-1076056504	edulog	2020-07-18 23:03:41.134196	0	t
66	2.059	 DA Update TripMaster Status	SQL	V2.059__DA_Update_TripMaster_Status.sql	399751219	edulog	2020-07-18 23:03:41.137495	5	t
67	2.060	 DA Drop boundaries RP	SQL	V2.060__DA_Drop_boundaries_RP.sql	1270617611	edulog	2020-07-18 23:03:41.144982	1	t
68	2.061	 DA Add ExportFile Table	SQL	V2.061__DA_Add_ExportFile_Table.sql	-134241475	edulog	2020-07-18 23:03:41.150538	3	t
69	2.062	 Reports Drop entity ids	SQL	V2.062__Reports_Drop_entity_ids.sql	-1131148363	edulog	2020-07-18 23:03:41.158101	1	t
70	2.063	 DA Add TR Elg Properties	SQL	V2.063__DA_Add_TR_Elg_Properties.sql	-462280810	edulog	2020-07-27 16:56:57.661353	138	t
71	2.064	 DA Add TR Override	SQL	V2.064__DA_Add_TR_Override.sql	-1287837460	edulog	2020-07-27 16:56:57.808135	1	t
72	2.065	 DA Add Version Column	SQL	V2.065__DA_Add_Version_Column.sql	-1704162878	edulog	2020-10-07 17:23:33.18692	6	t
73	2.066	 DA Add TR Home Stop	SQL	V2.066__DA_Add_TR_Home_Stop.sql	374841546	edulog	2020-10-07 17:23:33.201813	3	t
74	2.067	 DA Rename Stu Home Stop	SQL	V2.067__DA_Rename_Stu_Home_Stop.sql	50838666	edulog	2020-10-07 17:23:33.209918	2	t
75	2.068	 DA run max load view	SQL	V2.068__DA_run_max_load_view.sql	72498728	edulog	2020-10-07 17:23:33.218886	13	t
76	2.069	 DA run max duration view	SQL	V2.069__DA_run_max_duration_view.sql	-58830492	edulog	2020-10-07 17:23:33.241416	10	t
77	2.070	 Add Calendar Active	SQL	V2.070__Add_Calendar_Active.sql	-1499575049	edulog	2020-10-07 17:23:33.256987	2	t
78	2.071	 DA Alter SchoolName Len	SQL	V2.071__DA_Alter_SchoolName_Len.sql	-367543289	edulog	2020-10-07 17:23:33.264814	3	t
79	2.072	 DA Add Version Column Route	SQL	V2.072__DA_Add_Version_Column_Route.sql	919006771	edulog	2020-10-07 17:23:33.272748	1	t
80	2.073	 DA Location Table Geo Code	SQL	V2.073__DA_Location_Table_Geo_Code.sql	-2077166049	edulog	2020-10-07 17:23:33.279073	12	t
81	2.074	 DA Update Type Segment Node Id 	SQL	V2.074__DA_Update_Type_Segment_Node_Id_.sql	804877711	edulog	2020-10-07 17:23:33.295839	81	t
82	2.075	 Copy Views In Clone Schema Function	SQL	V2.075__Copy_Views_In_Clone_Schema_Function.sql	2077361860	edulog	2020-10-07 17:23:33.38529	4	t
83	2.076	 DA Add Version Column Trip	SQL	V2.076__DA_Add_Version_Column_Trip.sql	-695643473	edulog	2020-10-07 17:23:33.39466	2	t
84	2.077	 DA Drop Depot Add Karros Id	SQL	V2.077__DA_Drop_Depot_Add_Karros_Id.sql	-907561292	edulog	2020-11-10 17:03:14.328394	40	t
85	2.078	 DA Add Student Ride Column	SQL	V2.078__DA_Add_Student_Ride_Column.sql	661926866	edulog	2020-11-10 17:03:14.550099	9	t
86	2.079	 DA Add EduLog Id Seq	SQL	V2.079__DA_Add_EduLog_Id_Seq.sql	-1098300461	edulog	2020-11-10 17:03:14.578952	56	t
\.


--
-- Data for Name: report_info; Type: TABLE DATA; Schema: public; Owner: edulog
--

COPY public.report_info (id, reports, media_type, user_name, report_type, scheduled, is_preview, title) FROM stdin;
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: edulog
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: access; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.access (id, surrogate_key, name_of, description, access_type, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: access_domain; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.access_domain (id, access_id, domain_surrogate_key, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: access_school; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.access_school (id, access_id, school_surrogate_key, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: authentication_scope; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.authentication_scope (id, surrogate_key, application, groupof, roleof, role_description, permissions, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: avl_event; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.avl_event (id, avl_template_id, surrogate_key, type_of, point, location, condition, speed, mileage, heading, status, last_visited_stop_run, event_time, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: avl_template; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.avl_template (id, surrogate_key, name_of, description, route_code, vehicle_number, actual_date, begin_time, end_time, source_of, type_of, user_id, time_changed, create_date) FROM stdin;
\.


--
-- Data for Name: cal; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.cal (id, name_of, description, calendar_type, user_id, time_changed, surrogate_key, active) FROM stdin;
\.


--
-- Data for Name: cal_cal_event; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.cal_cal_event (cal_event_id, cal_id, id, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: cal_event; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.cal_event (id, surrogate_key, name_of, description, start_at, end_at, all_day_event, user_id, time_changed, cal_event_type) FROM stdin;
\.


--
-- Data for Name: data_area; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.data_area (id, surrogate_key, name_of, rp_schema, geo_schema, description, rolling_seq, user_id, time_changed) FROM stdin;
1	ad0a53fd-9e77-48f9-ab8e-d06a41c5035f	plan	rp_plan	geo_plan	Default planning area	1	SYSTEM	2020-07-18 23:03:40.876662+07
\.


--
-- Data for Name: import_value_mapping; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.import_value_mapping (id, surrogate_key, user_id, time_changed, external_value, internal_value, type_of_value) FROM stdin;
\.


--
-- Data for Name: plan_rollover; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.plan_rollover (id, plan_pushed_at, successful, user_id, time_changed, surrogate_key) FROM stdin;
\.


--
-- Data for Name: plan_rollover_log_items; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.plan_rollover_log_items (id, plan_rollover_id, object_type, object_id, notes, user_id, time_changed, surrogate_key) FROM stdin;
\.


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.role_permissions (id, surrogate_key, name_of, description_of, functional_permissions, active, user_id, time_changed) FROM stdin;
1	f7a99aff-155c-43c0-885d-a3d404432fc7	Administrator	Administrator	{"modules": [{"name": "athena", "access": true, "submodules": [{"name": "datamanagement", "access": true, "submodules": [{"name": "studentsadmin", "access": true, "submodules": []}, {"name": "tripsadmin", "access": true, "submodules": []}, {"name": "stopsadmin", "access": true, "submodules": []}, {"name": "runsadmin", "access": true, "submodules": []}, {"name": "routesadmin", "access": true, "submodules": []}, {"name": "avltemplatesadmin", "access": true, "submodules": []}, {"name": "schoolsadmin", "access": true, "submodules": []}, {"name": "vehiclesadmin", "access": true, "submodules": []}, {"name": "driversadmin", "access": true, "submodules": []}]}, {"name": "routing", "access": true, "submodules": [{"name": "transportationrequests", "access": true, "submodules": []}, {"name": "tripplanning", "access": true, "submodules": []}, {"name": "runmanagement", "access": true, "submodules": []}, {"name": "routesmanagement", "access": true, "submodules": []}, {"name": "schoolrouting", "access": true, "submodules": []}]}, {"name": "optimization", "access": true, "submodules": [{"name": "stops", "access": true, "submodules": []}, {"name": "runs", "access": true, "submodules": []}, {"name": "routes", "access": true, "submodules": []}, {"name": "belltimes", "access": true, "submodules": []}]}, {"name": "dashboard", "access": true, "submodules": [{"name": "routers", "access": true, "submodules": []}, {"name": "dispatcher", "access": true, "submodules": []}, {"name": "supervisor", "access": true, "submodules": []}]}, {"name": "mapping", "access": true, "submodules": [{"name": "streetnetwork", "access": true, "submodules": []}, {"name": "boundaries", "access": true, "submodules": []}]}]}, {"name": "ridership", "access": true, "submodules": []}, {"name": "dispatch", "access": true, "submodules": []}, {"name": "timeandattendance", "access": true, "submodules": []}, {"name": "telematics", "access": true, "submodules": [{"name": "tracking", "access": true, "submodules": [{"name": "live", "access": true, "submodules": []}, {"name": "history", "access": true, "submodules": []}]}, {"name": "detection", "access": true, "submodules": [{"name": "substitution", "access": true, "submodules": []}, {"name": "hazard", "access": true, "submodules": []}]}, {"name": "analysis", "access": true, "submodules": [{"name": "hardware", "access": true, "submodules": []}, {"name": "avl", "access": true, "submodules": []}]}, {"name": "riders", "access": true, "submodules": [{"name": "students", "access": true, "submodules": []}]}, {"name": "drivers", "access": true, "submodules": [{"name": "time", "access": true, "submodules": []}, {"name": "attendance", "access": true, "submodules": []}]}, {"name": "dashboard", "access": true, "submodules": [{"name": "routers", "access": true, "submodules": []}, {"name": "dispatcher", "access": true, "submodules": []}, {"name": "supervisor", "access": true, "submodules": []}]}]}, {"name": "mapping", "access": true, "submodules": []}, {"name": "analytics", "access": true, "submodules": []}, {"name": "admin", "access": true, "submodules": [{"name": "users", "access": true, "submodules": [{"name": "roles", "access": true, "submodules": []}]}, {"name": "app", "access": true, "submodules": [{"name": "account", "access": true, "submodules": []}]}, {"access": true, "submodules": []}]}, {"name": "helpcenter", "access": true, "submodules": [{"name": "contextualhelp", "access": true, "submodules": []}]}], "endpoints": [{"ops": [{"name": "loadavlroutemetadata", "access": true}, {"name": "loadavlroute", "access": true}], "name": "avl", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "avltemplate", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "belltimes", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "get", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "clusters", "fields": []}, {"ops": [{"name": "getruns", "access": true}, {"name": "getrunsbytaskid", "access": true}, {"name": "gettrips", "access": true}, {"name": "gettripsbytaskid", "access": true}, {"name": "getstoprequests", "access": true}, {"name": "getstoprequestsbytaskid", "access": true}, {"name": "getstopservices", "access": true}, {"name": "getstopservicesbytaskid", "access": true}, {"name": "getunassignedruns", "access": true}, {"name": "getunassignedrunsbytaskid", "access": true}, {"name": "getroutes", "access": true}, {"name": "getfullroute", "access": true}, {"name": "getroutesbytaskid", "access": true}], "name": "contexts", "fields": []}, {"ops": [{"name": "read", "access": true}], "name": "grades", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "locations", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "previewassignstopsonrun", "access": true}, {"name": "commitassignstopsonrun", "access": true}, {"name": "previewassignstopsonruns", "access": true}, {"name": "commitassignstopsonruns", "access": true}, {"name": "previewresequencerun", "access": true}, {"name": "commitresequencerun", "access": true}, {"name": "previewresequenceruns", "access": true}, {"name": "commitresequenceruns", "access": true}, {"name": "previewbuildruns", "access": true}, {"name": "commitbuildruns", "access": true}], "name": "opt", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "programs", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "previewassignrun", "access": true}, {"name": "commitassignrun", "access": true}, {"name": "previewassignruns", "access": true}, {"name": "commitassignruns", "access": true}, {"name": "previewunassignrun", "access": true}, {"name": "commitunassignrun", "access": true}, {"name": "previewunassignruns", "access": true}, {"name": "commitunassignruns", "access": true}, {"name": "shiftrunsonroutes", "access": true}], "name": "routes", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "previewremovestopfromrun", "access": true}, {"name": "commitremovestopfromrun", "access": true}, {"name": "previewmovestopbetweenruns", "access": true}, {"name": "commitmovestopbetweenruns", "access": true}, {"name": "previewinsertstoponrun", "access": true}, {"name": "commitinsertstoponrun", "access": true}, {"name": "previewremovecheckpointfromrun", "access": true}, {"name": "commitremovecheckpointfromrun", "access": true}, {"name": "previewmovecheckpoint", "access": true}, {"name": "commitmovecheckpoint", "access": true}, {"name": "previewinsertcheckpointonrun", "access": true}, {"name": "commitinsertcheckpointonrun", "access": true}, {"name": "commitdrivetimechange", "access": true}, {"name": "committimeatstopchange", "access": true}, {"name": "shiftunassignedruns", "access": true}, {"name": "removeallstopsfromrun", "access": true}, {"name": "savetoroutingdb", "access": true}], "name": "runs", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "schools", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "servicerequests", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "search", "access": true}, {"name": "waypointServices", "access": true}, {"name": "onRunsNoTrips", "access": true}, {"name": "tripsNotOnRuns", "access": true}, {"name": "noRunsNoTrips", "access": true}], "name": "stops", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "search", "access": true}, {"name": "unassigned", "access": true}, {"name": "partialAssigned", "access": true}, {"name": "unmatched", "access": true}], "name": "students", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "tasks", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "transportationRequestDetails", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "search", "access": true}, {"name": "addDetails", "access": true}, {"name": "commitItinerary", "access": true}, {"name": "previewItinerary", "access": true}], "name": "transportationRequests", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "transportneeds", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}, {"name": "assigntriptostoprequest", "access": true}, {"name": "assigntripstostoprequest", "access": true}, {"name": "assigntriptostopservice", "access": true}, {"name": "assigntripstostopservice", "access": true}, {"name": "unassigntripfromstoprequest", "access": true}, {"name": "unassigntripsfromstoprequest", "access": true}, {"name": "unassigntripfromstopservice", "access": true}, {"name": "unassigntripsfromstopservice", "access": true}, {"name": "quickassign", "access": true}, {"name": "savetoroutingdb", "access": true}], "name": "trips", "fields": []}, {"ops": [{"name": "create", "access": true}, {"name": "read", "access": true}, {"name": "update", "access": true}, {"name": "delete", "access": true}], "name": "userRoles", "fields": []}]}	t	SYSTEM	2019-04-12 05:40:39.82837+07
\.


--
-- Data for Name: student_import_conf; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.student_import_conf (id, surrogate_key, default_program, default_country, user_id, time_changed, create_date, shared, full_import, import_mode) FROM stdin;
\.


--
-- Data for Name: student_import_mapping; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.student_import_mapping (id, surrogate_key, district_id, first_name, last_name, middle_name, nick_name, suffix, gender, max_ride_time, mailing_address, phone, email, rfid, home_room_teacher, address, house_number, street_direction, street_name, city, state_of, zip, country, grade, program_code, school_code, user_id, time_changed, create_date, parent_name, parent_phone, enroll_date, withdraw_date) FROM stdin;
\.


--
-- Data for Name: user; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master."user" (id, surrogate_key, person_id, first_name, middle_name, last_name, active, email, department, "position", user_id_manager, password_changed_at, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: user_profile; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.user_profile (id, surrogate_key, user_id, user_profile_template_id, active, user_id_changed, time_changed) FROM stdin;
\.


--
-- Data for Name: user_profile_template; Type: TABLE DATA; Schema: rp_master; Owner: edulog
--

COPY rp_master.user_profile_template (id, surrogate_key, name_of, description_of, domain_id, active, access_id, role_permissions_id, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: belltime; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.belltime (id, surrogate_key, school_id, type_of, bell, early, late, depart, section_of_day, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: cluster; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.cluster (id, surrogate_key, name_of, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: cluster_belltime; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.cluster_belltime (id, cluster_id, belltime_id, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: contact; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.contact (id, surrogate_key, title, first_name, middle_name, last_name, primary_phone, primary_type, secondary_phone, secondary_type, alternate_phone, alternate_type, email, mailing_address, language_code, suffix, publish, code, picture_file_name, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: contractor; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.contractor (id, surrogate_key, name_of, description, comments, user_id, time_changed, create_date) FROM stdin;
\.


--
-- Data for Name: direction_step; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.direction_step (id, surrogate_key, path_cover_id, waypoint_cover_id, seq_number, instructions, distance, duration, polyline, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: district_eligibility; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.district_eligibility (id, surrogate_key, description, eligible, user_id, time_changed) FROM stdin;
1	49ae6c74-e091-45ab-9a41-8305976d4e41	ELIGIBLE.	t	migration-V1.001	2020-07-18 23:03:40.200098+07
2	b42c2dcf-872e-4e9d-b804-63f0f13a643c	ELIGIBLE DUE TO INJURY.	t	migration-V1.001	2020-07-18 23:03:40.200098+07
3	17537e97-e434-4149-b0fa-d9b13e1de1d4	ELIGIBLE DUE SPECIAL CIRCUMSTANCE.	t	migration-V1.001	2020-07-18 23:03:40.200098+07
4	7742f461-a431-41d5-9f1b-c8fa3be63a86	NOT ELIGIBLE.	f	migration-V1.001	2020-07-18 23:03:40.200098+07
5	7741c5c3-c812-4eaa-aad4-a72f427288ec	NOT ELIGIBLE BEHAVIORAL ISSUES ON THE BUS.	f	migration-V1.001	2020-07-18 23:03:40.200098+07
\.


--
-- Data for Name: domain; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.domain (id, name, description, parent_id, active, time_changed, surrogate_key, user_id) FROM stdin;
\.


--
-- Data for Name: eligibility_rule; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.eligibility_rule (id, surrogate_key, name_of, description, comments, user_id, time_changed, create_date) FROM stdin;
\.


--
-- Data for Name: gps_unit; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.gps_unit (id, surrogate_key, manufacturer, model, user_id, time_changed, create_date, device_id) FROM stdin;
\.


--
-- Data for Name: grade; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.grade (id, surrogate_key, code, description, sort_order, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: hazard_zone; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.hazard_zone (id, surrogate_key, location_id, label, description, notes, distance, end_date, user_id, time_changed, create_date) FROM stdin;
\.


--
-- Data for Name: head_count; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.head_count (id, stop_id, waypoint_master_id, school_id, belltime_id, day1, day2, day3, day4, day5, day6, day7) FROM stdin;
\.


--
-- Data for Name: inactive_student; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.inactive_student (id, surrogate_key, edulog_id, government_id, district_id, first_name, middle_name, last_name, suffix, nick_name, school_id, grade_id, program_id, gender, ethnicity, distance_to_school, elg_code, district_eligibility_id, sis_address, sis_apt_number, iep, section_504, home_pickup, home_right_side, home_available, load_time, date_of_birth, max_ride_time, picture_file_name, location_id, mailing_address, rfid, begin_date, enroll_date, withdraw_date, homeroom_teacher, phone, email, transport_needs, needs, notes, medical_notes, contacts, user_id, time_changed, create_date) FROM stdin;
\.


--
-- Data for Name: load_time; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.load_time (id, min_load, load_time) FROM stdin;
\.


--
-- Data for Name: location; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.location (id, surrogate_key, address, point, user_id, time_changed, landmark, street_number, street, street_two, city, state, postal_code, country, node_one_id, node_one_point, node_two_id, node_two_point, percent_along, right_side, geo_location_id, geo_street_id, geo_street_two_id, geo_segment_id) FROM stdin;
\.


--
-- Data for Name: medical_note; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.medical_note (id, surrogate_key, student_id, note, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: need; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.need (id, surrogate_key, description, sort_order, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: path_cover; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.path_cover (id, surrogate_key, path_master_id, cover, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: path_master; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.path_master (id, surrogate_key, description, type_of, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: program; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.program (id, surrogate_key, code, description, sort_order, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: route; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.route (id, surrogate_key, path_master_id, code, description, comments, proxy, map_set, user_id, time_changed, create_date, vehicle_id, contractor_id, version, depot_id) FROM stdin;
\.


--
-- Data for Name: route_contact; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.route_contact (id, contact_id, route_id, relation_descriptor, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: route_run; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.route_run (id, route_id, run_id, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: run; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.run (id, surrogate_key, code, description, to_from, max_duration, max_load, comments, user_id, time_changed, create_date, dynamic_freq, version) FROM stdin;
\.


--
-- Data for Name: school; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school (id, surrogate_key, code, name_of, grade_level, address, city, state_code, postal_code, country, max_ride_time, school_id_transport, school_district_id, board, school_type, url, comments, user_id, time_changed, cal_id) FROM stdin;
\.


--
-- Data for Name: school_contact; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school_contact (id, school_id, contact_id, relation_descriptor, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: school_district; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school_district (id, surrogate_key, code, county, url, user_id, time_changed, description, cal_id) FROM stdin;
\.


--
-- Data for Name: school_location; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school_location (id, school_id, location_id, type_of, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: school_operation_cover; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school_operation_cover (id, surrogate_key, school_operation_master_id, belltime_id_depart, belltime_id_arrival, freq, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: school_operation_master; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school_operation_master (id, school_id, grade_id, program_id, hazard_type, web_allowed, school_calendar, user_id, time_changed, max_assign_dist) FROM stdin;
\.


--
-- Data for Name: school_operation_master_boundary; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.school_operation_master_boundary (id, school_operation_master_id, posting_type, user_id, time_changed, eligibility_rule_id, geo_boundary_uuid) FROM stdin;
\.


--
-- Data for Name: site_meta_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_meta_data (id, data_type, field_type, label, data_length, visible, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: site_route_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_route_data (id, route_id, json_string) FROM stdin;
\.


--
-- Data for Name: site_run_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_run_data (id, run_id, json_string) FROM stdin;
\.


--
-- Data for Name: site_school_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_school_data (id, school_id, json_string) FROM stdin;
\.


--
-- Data for Name: site_stop_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_stop_data (id, stop_id, json_string) FROM stdin;
\.


--
-- Data for Name: site_student_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_student_data (id, student_id, json_string) FROM stdin;
\.


--
-- Data for Name: site_trip_data; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.site_trip_data (id, trip_master_id, json_string) FROM stdin;
\.


--
-- Data for Name: stop; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.stop (id, surrogate_key, location_id, code, government_id, description, comments, right_side, end_date, begin_date, user_id, time_changed, create_date, active) FROM stdin;
\.


--
-- Data for Name: student; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.student (id, surrogate_key, edulog_id, government_id, district_id, first_name, middle_name, last_name, suffix, nick_name, school_operation_master_id, gender, ethnicity, distance_to_school, elg_code, sis_address, sis_apt_number, iep, section_504, home_stop, home_right_side, home_available, load_time, date_of_birth, max_ride_time, picture_file_name, location_id, mailing_address, rfid, begin_date, enroll_date, withdraw_date, homeroom_teacher, phone, email, user_id, time_changed, create_date, district_eligibility_id, school_bus_ride_allowed) FROM stdin;
\.


--
-- Data for Name: student_contact; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.student_contact (id, student_id, contact_id, mailing_address, emergency_contact, releasable, relation_descriptor, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: student_import_line; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.student_import_line (id, surrogate_key, athena_id, district_id, first_name, last_name, middle_name, nick_name, suffix, gender, ethnicity, distance_to_school, max_ride_time, mailing_address, phone, email, rfid, home_room_teacher, address, house_number, street_direction, street_name, city, state_of, zip, country, grade, program_code, school_code, user_id, time_changed, create_date, parent_name, parent_phone, enroll_date, withdraw_date) FROM stdin;
\.


--
-- Data for Name: student_need; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.student_need (id, student_id, need_id, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: student_note; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.student_note (id, surrogate_key, student_id, note, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: student_transport_need; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.student_transport_need (id, student_id, transport_need_id, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: transport_def_cover; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.transport_def_cover (id, surrogate_key, transport_def_master_id, belltime_id_origin, belltime_id_destination, freq, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: transport_def_master; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.transport_def_master (id, surrogate_key, description, school_id_origin, location_id_origin, school_id_destination, location_id_destination, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: transport_itinerary; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.transport_itinerary (id, surrogate_key, transport_request_detail_id, freq, stop_code_to_school, stop_description_to_school, run_code_to_school, run_description_to_school, time_at_to_school, stop_code_from_school, stop_description_from_school, run_code_from_school, run_description_from_school, time_at_from_school, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: transport_need; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.transport_need (id, surrogate_key, description, type_of, load_value, load_time, sort_order, extra_run_load, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: transport_request; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.transport_request (id, surrogate_key, begin_date, end_date, transport_mode, location_id_requested_stop, requested_stop_required, request_source, user_id, time_changed, direction, student_id, transport_def_master_id_to_school, transport_def_master_id_from_school, elg_code, elg_overridden, student_default, transport_request_id_overridden, home_stop, school_bus_ride_allowed) FROM stdin;
\.


--
-- Data for Name: transport_request_detail; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.transport_request_detail (id, surrogate_key, transport_request_id, seq_number, status, reviewer_group, comments, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: trip_cover; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.trip_cover (id, surrogate_key, freq, user_id, time_changed, transport_def_cover_id) FROM stdin;
\.


--
-- Data for Name: trip_leg; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.trip_leg (id, surrogate_key, trip_cover_id, seq_number, description, type_of, type_of_origin, type_of_destination, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: trip_leg_waypoint_master; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.trip_leg_waypoint_master (id, trip_leg_id, waypoint_master_id_origin, waypoint_master_id_destination) FROM stdin;
\.


--
-- Data for Name: trip_master; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.trip_master (id, surrogate_key, user_id, time_changed, transport_def_master_id, assigned_status, version) FROM stdin;
\.


--
-- Data for Name: vehicle; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.vehicle (id, surrogate_key, vin, name_of, capacity, description, gps_unit_id, make, model, year_of, comments, user_id, time_changed, create_date, contractor_id, start_of_service, end_of_service, license_number) FROM stdin;
\.


--
-- Data for Name: vehicle_maintenance; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.vehicle_maintenance (id, service_start_date, service_start_time, estimated_service_end_date, estimated_service_end_time, actual_service_end_date, actual_service_end_time, vehicle_id, user_id, time_changed, surrogate_key) FROM stdin;
\.


--
-- Data for Name: vehicle_transport_need; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.vehicle_transport_need (id, vehicle_id, transport_need_id) FROM stdin;
\.


--
-- Data for Name: waypoint_cover; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.waypoint_cover (id, surrogate_key, waypoint_master_id, path_cover_id, seq_number, begin_date, end_date, student_crossing, time_at, load_time, fixed_time, duration_override, user_id, time_changed) FROM stdin;
\.


--
-- Data for Name: waypoint_cover_belltime; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.waypoint_cover_belltime (id, belltime_id, waypoint_cover_id) FROM stdin;
\.


--
-- Data for Name: waypoint_master; Type: TABLE DATA; Schema: rp_plan; Owner: edulog
--

COPY rp_plan.waypoint_master (id, surrogate_key, path_master_id, route_run_id, location_id, seq_number, boarding_type, type_of, description, user_id, time_changed, dynamic_freq) FROM stdin;
\.


--
-- Data for Name: board; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.board (label, web_allowed) FROM stdin;
\.


--
-- Data for Name: city; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.city (label) FROM stdin;
\.


--
-- Data for Name: ethnicity; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.ethnicity (label, description) FROM stdin;
\.


--
-- Data for Name: form_of_address; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.form_of_address (title) FROM stdin;
\.


--
-- Data for Name: hazard_type; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.hazard_type (description) FROM stdin;
\.


--
-- Data for Name: language; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.language (description) FROM stdin;
\.


--
-- Data for Name: postal_code; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.postal_code (code) FROM stdin;
\.


--
-- Data for Name: route_contact_relationship; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.route_contact_relationship (title) FROM stdin;
\.


--
-- Data for Name: school_calendar; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.school_calendar (label) FROM stdin;
\.


--
-- Data for Name: school_contact_relationship; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.school_contact_relationship (title) FROM stdin;
\.


--
-- Data for Name: school_type; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.school_type (description) FROM stdin;
\.


--
-- Data for Name: state_country; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.state_country (state_code, state_description, country_description, country_code) FROM stdin;
\.


--
-- Data for Name: student_contact_relationship; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.student_contact_relationship (title) FROM stdin;
\.


--
-- Data for Name: user_title; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.user_title (title) FROM stdin;
\.


--
-- Data for Name: version; Type: TABLE DATA; Schema: settings; Owner: edulog
--

COPY settings.version (type, type_version, time_changed) FROM stdin;
\.


--
-- Name: activity_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.activity_id_seq', 1, false);


--
-- Name: billing_type_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.billing_type_id_seq', 1, false);


--
-- Name: certification_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.certification_id_seq', 1, false);


--
-- Name: department_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.department_id_seq', 1, false);


--
-- Name: district_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.district_id_seq', 1, false);


--
-- Name: driver_class_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.driver_class_id_seq', 1, false);


--
-- Name: driver_info_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.driver_info_id_seq', 1, false);


--
-- Name: emp_class_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.emp_class_id_seq', 1, false);


--
-- Name: emp_group_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.emp_group_id_seq', 1, false);


--
-- Name: grade_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.grade_id_seq', 1, false);


--
-- Name: image_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.image_id_seq', 1, false);


--
-- Name: level_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.level_id_seq', 1, false);


--
-- Name: license_class_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.license_class_id_seq', 1, false);


--
-- Name: ridership_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.ridership_id_seq', 1, false);


--
-- Name: scale_hour_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.scale_hour_id_seq', 1, false);


--
-- Name: search_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.search_id_seq', 1, false);


--
-- Name: seniority_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.seniority_id_seq', 1, false);


--
-- Name: skill_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.skill_id_seq', 1, false);


--
-- Name: student_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.student_id_seq', 1, false);


--
-- Name: training_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.training_id_seq', 1, false);


--
-- Name: transaction_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.transaction_id_seq', 1, false);


--
-- Name: union_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.union_id_seq', 1, false);


--
-- Name: work_group_id_seq; Type: SEQUENCE SET; Schema: edta; Owner: edulog
--

SELECT pg_catalog.setval('edta.work_group_id_seq', 1, false);


--
-- Name: config_id_seq; Type: SEQUENCE SET; Schema: geo_master; Owner: edulog
--

SELECT pg_catalog.setval('geo_master.config_id_seq', 1, false);


--
-- Name: geoserver_layer_id_seq; Type: SEQUENCE SET; Schema: geo_master; Owner: edulog
--

SELECT pg_catalog.setval('geo_master.geoserver_layer_id_seq', 1, false);


--
-- Name: address_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.address_id_seq', 1, false);


--
-- Name: adj_except_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.adj_except_id_seq', 1, false);


--
-- Name: boundary_group_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.boundary_group_id_seq', 99, true);


--
-- Name: boundary_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.boundary_id_seq', 1, false);


--
-- Name: export_file_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.export_file_id_seq', 1, false);


--
-- Name: landmark_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.landmark_id_seq', 1, false);


--
-- Name: legal_description_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.legal_description_id_seq', 1, false);


--
-- Name: location_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.location_id_seq', 1, false);


--
-- Name: mile_marker_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.mile_marker_id_seq', 1, false);


--
-- Name: node_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.node_id_seq', 1, false);


--
-- Name: parsing_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.parsing_id_seq', 1, false);


--
-- Name: segment_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.segment_id_seq', 1, false);


--
-- Name: street_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.street_id_seq', 1, false);


--
-- Name: street_segment_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.street_segment_id_seq', 1, false);


--
-- Name: zipcode_id_seq; Type: SEQUENCE SET; Schema: geo_plan; Owner: edulog
--

SELECT pg_catalog.setval('geo_plan.zipcode_id_seq', 1, false);


--
-- Name: i_type_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.i_type_id_seq', 1, false);


--
-- Name: i_zone_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.i_zone_id_seq', 1, false);


--
-- Name: image_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.image_id_seq', 1, false);


--
-- Name: inspection_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.inspection_id_seq', 1, false);


--
-- Name: inspection_point_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.inspection_point_id_seq', 1, false);


--
-- Name: inspection_zone_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.inspection_zone_id_seq', 1, false);


--
-- Name: template_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.template_id_seq', 1, false);


--
-- Name: template_point_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.template_point_id_seq', 1, false);


--
-- Name: template_point_validation_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.template_point_validation_id_seq', 1, false);


--
-- Name: template_point_validation_type_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.template_point_validation_type_id_seq', 1, false);


--
-- Name: template_zone_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.template_zone_id_seq', 1, false);


--
-- Name: validation_type_id_seq; Type: SEQUENCE SET; Schema: ivin; Owner: edulog
--

SELECT pg_catalog.setval('ivin.validation_type_id_seq', 1, false);


--
-- Name: report_info_id_seq; Type: SEQUENCE SET; Schema: public; Owner: edulog
--

SELECT pg_catalog.setval('public.report_info_id_seq', 1, false);


--
-- Name: access_domains_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.access_domains_id_seq', 1, false);


--
-- Name: access_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.access_id_seq', 1, false);


--
-- Name: access_schools_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.access_schools_id_seq', 1, false);


--
-- Name: authentication_scope_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.authentication_scope_id_seq', 1, false);


--
-- Name: avl_event_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.avl_event_id_seq', 1, false);


--
-- Name: avl_template_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.avl_template_id_seq', 1, false);


--
-- Name: cal_cal_event_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.cal_cal_event_id_seq', 1, false);


--
-- Name: cal_event_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.cal_event_id_seq', 1, false);


--
-- Name: cal_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.cal_id_seq', 1, false);


--
-- Name: data_area_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.data_area_id_seq', 1, true);


--
-- Name: import_value_mapping_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.import_value_mapping_id_seq', 1, false);


--
-- Name: plan_rollover_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.plan_rollover_id_seq', 1, false);


--
-- Name: plan_rollover_log_items_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.plan_rollover_log_items_id_seq', 1, false);


--
-- Name: role_permissions_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.role_permissions_id_seq', 2, false);


--
-- Name: student_import_conf_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.student_import_conf_id_seq', 1, false);


--
-- Name: student_import_mapping_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.student_import_mapping_id_seq', 1, false);


--
-- Name: user_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.user_id_seq', 1, false);


--
-- Name: user_profile_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.user_profile_id_seq', 1, false);


--
-- Name: user_profile_template_id_seq; Type: SEQUENCE SET; Schema: rp_master; Owner: edulog
--

SELECT pg_catalog.setval('rp_master.user_profile_template_id_seq', 1, false);


--
-- Name: belltime_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.belltime_id_seq', 1, false);


--
-- Name: cluster_belltime_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.cluster_belltime_id_seq', 1, false);


--
-- Name: cluster_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.cluster_id_seq', 1, false);


--
-- Name: contact_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.contact_id_seq', 1, false);


--
-- Name: contractor_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.contractor_id_seq', 1, false);


--
-- Name: direction_step_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.direction_step_id_seq', 1, false);


--
-- Name: district_eligibility_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.district_eligibility_id_seq', 5, true);


--
-- Name: domain_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.domain_id_seq', 1, false);


--
-- Name: edulog_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.edulog_id_seq', 1, false);


--
-- Name: eligibility_rule_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.eligibility_rule_id_seq', 1, false);


--
-- Name: gps_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.gps_id_seq', 1, false);


--
-- Name: grade_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.grade_id_seq', 1, false);


--
-- Name: hazard_zone_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.hazard_zone_id_seq', 1, false);


--
-- Name: head_count_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.head_count_id_seq', 1, false);


--
-- Name: inactive_student_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.inactive_student_id_seq', 1, false);


--
-- Name: load_time_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.load_time_id_seq', 1, false);


--
-- Name: location_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.location_id_seq', 1, false);


--
-- Name: medical_note_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.medical_note_id_seq', 1, false);


--
-- Name: need_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.need_id_seq', 1, false);


--
-- Name: path_cover_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.path_cover_id_seq', 1, false);


--
-- Name: path_master_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.path_master_id_seq', 1, false);


--
-- Name: program_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.program_id_seq', 1, false);


--
-- Name: route_contact_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.route_contact_id_seq', 1, false);


--
-- Name: route_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.route_id_seq', 1, false);


--
-- Name: route_run_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.route_run_id_seq', 1, false);


--
-- Name: run_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.run_id_seq', 1, false);


--
-- Name: school_contact_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_contact_id_seq', 1, false);


--
-- Name: school_district_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_district_id_seq', 1, false);


--
-- Name: school_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_id_seq', 1, false);


--
-- Name: school_location_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_location_id_seq', 1, false);


--
-- Name: school_operation_cover_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_operation_cover_id_seq', 1, false);


--
-- Name: school_operation_master_boundary_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_operation_master_boundary_id_seq', 1, false);


--
-- Name: school_operation_master_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.school_operation_master_id_seq', 1, false);


--
-- Name: site_meta_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_meta_data_id_seq', 1, false);


--
-- Name: site_route_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_route_data_id_seq', 1, false);


--
-- Name: site_run_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_run_data_id_seq', 1, false);


--
-- Name: site_school_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_school_data_id_seq', 1, false);


--
-- Name: site_stop_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_stop_data_id_seq', 1, false);


--
-- Name: site_student_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_student_data_id_seq', 1, false);


--
-- Name: site_trip_data_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.site_trip_data_id_seq', 1, false);


--
-- Name: stop_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.stop_id_seq', 1, false);


--
-- Name: student_contact_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_contact_id_seq', 1, false);


--
-- Name: student_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_id_seq', 1, false);


--
-- Name: student_import_line_athena_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_import_line_athena_id_seq', 1, false);


--
-- Name: student_import_line_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_import_line_id_seq', 1, false);


--
-- Name: student_need_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_need_id_seq', 1, false);


--
-- Name: student_note_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_note_id_seq', 1, false);


--
-- Name: student_note_student_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_note_student_id_seq', 1, false);


--
-- Name: student_transport_need_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.student_transport_need_id_seq', 1, false);


--
-- Name: transport_def_cover_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.transport_def_cover_id_seq', 1, false);


--
-- Name: transport_def_master_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.transport_def_master_id_seq', 1, false);


--
-- Name: transport_itinerary_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.transport_itinerary_id_seq', 1, false);


--
-- Name: transport_need_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.transport_need_id_seq', 1, false);


--
-- Name: transport_request_detail_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.transport_request_detail_id_seq', 1, false);


--
-- Name: transport_request_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.transport_request_id_seq', 1, false);


--
-- Name: trip_cover_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.trip_cover_id_seq', 1, false);


--
-- Name: trip_leg_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.trip_leg_id_seq', 1, false);


--
-- Name: trip_leg_waypoint_master_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.trip_leg_waypoint_master_id_seq', 1, false);


--
-- Name: trip_master_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.trip_master_id_seq', 1, false);


--
-- Name: vehicle_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.vehicle_id_seq', 1, false);


--
-- Name: vehicle_maintenance_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.vehicle_maintenance_id_seq', 1, false);


--
-- Name: vehicle_transport_need_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.vehicle_transport_need_id_seq', 1, false);


--
-- Name: waypoint_cover_belltime_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.waypoint_cover_belltime_id_seq', 1, false);


--
-- Name: waypoint_cover_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.waypoint_cover_id_seq', 1, false);


--
-- Name: waypoint_master_id_seq; Type: SEQUENCE SET; Schema: rp_plan; Owner: edulog
--

SELECT pg_catalog.setval('rp_plan.waypoint_master_id_seq', 1, false);


--
-- Name: activity pk_activity; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.activity
    ADD CONSTRAINT pk_activity PRIMARY KEY (id);


--
-- Name: billing_type pk_billingtype; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.billing_type
    ADD CONSTRAINT pk_billingtype PRIMARY KEY (id);


--
-- Name: certification pk_certification; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.certification
    ADD CONSTRAINT pk_certification PRIMARY KEY (id);


--
-- Name: department pk_department; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.department
    ADD CONSTRAINT pk_department PRIMARY KEY (id);


--
-- Name: district pk_district; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.district
    ADD CONSTRAINT pk_district PRIMARY KEY (id);


--
-- Name: driver_class pk_driver_class; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_class
    ADD CONSTRAINT pk_driver_class PRIMARY KEY (id);


--
-- Name: driver_info pk_driver_info; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT pk_driver_info PRIMARY KEY (id);


--
-- Name: driver_skill pk_driver_skill; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_skill
    ADD CONSTRAINT pk_driver_skill PRIMARY KEY (driver_info_id, skill_id);


--
-- Name: emp_class pk_emp_class; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.emp_class
    ADD CONSTRAINT pk_emp_class PRIMARY KEY (id);


--
-- Name: emp_group pk_emp_group; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.emp_group
    ADD CONSTRAINT pk_emp_group PRIMARY KEY (id);


--
-- Name: grade pk_grade; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.grade
    ADD CONSTRAINT pk_grade PRIMARY KEY (id);


--
-- Name: image pk_image; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.image
    ADD CONSTRAINT pk_image PRIMARY KEY (id);


--
-- Name: level pk_level; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.level
    ADD CONSTRAINT pk_level PRIMARY KEY (id);


--
-- Name: license_class pk_license_class; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.license_class
    ADD CONSTRAINT pk_license_class PRIMARY KEY (id);


--
-- Name: ridership pk_ridership_id; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.ridership
    ADD CONSTRAINT pk_ridership_id PRIMARY KEY (id);


--
-- Name: scale_hour pk_scale_hour; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.scale_hour
    ADD CONSTRAINT pk_scale_hour PRIMARY KEY (id);


--
-- Name: search pk_search; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.search
    ADD CONSTRAINT pk_search PRIMARY KEY (id);


--
-- Name: seniority pk_seniority; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.seniority
    ADD CONSTRAINT pk_seniority PRIMARY KEY (id);


--
-- Name: skill pk_skill; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.skill
    ADD CONSTRAINT pk_skill PRIMARY KEY (id);


--
-- Name: state pk_state; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.state
    ADD CONSTRAINT pk_state PRIMARY KEY (code);


--
-- Name: student pk_student_id; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.student
    ADD CONSTRAINT pk_student_id PRIMARY KEY (id);


--
-- Name: training pk_trainning; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.training
    ADD CONSTRAINT pk_trainning PRIMARY KEY (id);


--
-- Name: transaction pk_transaction; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.transaction
    ADD CONSTRAINT pk_transaction PRIMARY KEY (id);


--
-- Name: union pk_union; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta."union"
    ADD CONSTRAINT pk_union PRIMARY KEY (id);


--
-- Name: work_group pk_work_group; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.work_group
    ADD CONSTRAINT pk_work_group PRIMARY KEY (id);


--
-- Name: activity uq_activity_code; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.activity
    ADD CONSTRAINT uq_activity_code UNIQUE (code);


--
-- Name: activity uq_activity_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.activity
    ADD CONSTRAINT uq_activity_name_of UNIQUE (name_of);


--
-- Name: billing_type uq_billing_code; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.billing_type
    ADD CONSTRAINT uq_billing_code UNIQUE (code);


--
-- Name: billing_type uq_billing_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.billing_type
    ADD CONSTRAINT uq_billing_name_of UNIQUE (name_of);


--
-- Name: department uq_department_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.department
    ADD CONSTRAINT uq_department_name_of UNIQUE (name_of);


--
-- Name: state uq_description; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.state
    ADD CONSTRAINT uq_description UNIQUE (description);


--
-- Name: district uq_district_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.district
    ADD CONSTRAINT uq_district_name_of UNIQUE (name_of);


--
-- Name: driver_class uq_driver_class_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_class
    ADD CONSTRAINT uq_driver_class_name_of UNIQUE (name_of);


--
-- Name: emp_class uq_emp_class_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.emp_class
    ADD CONSTRAINT uq_emp_class_name_of UNIQUE (name_of);


--
-- Name: emp_group uq_emp_group_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.emp_group
    ADD CONSTRAINT uq_emp_group_name_of UNIQUE (name_of);


--
-- Name: driver_info uq_employee_id; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT uq_employee_id UNIQUE (employee_id);


--
-- Name: grade uq_grade_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.grade
    ADD CONSTRAINT uq_grade_name_of UNIQUE (name_of);


--
-- Name: image uq_image_driver_info_id; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.image
    ADD CONSTRAINT uq_image_driver_info_id UNIQUE (driver_info_id);


--
-- Name: level uq_level_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.level
    ADD CONSTRAINT uq_level_name_of UNIQUE (name_of);


--
-- Name: license_class uq_license_class_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.license_class
    ADD CONSTRAINT uq_license_class_name_of UNIQUE (name_of);


--
-- Name: scale_hour uq_scale_hour_value; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.scale_hour
    ADD CONSTRAINT uq_scale_hour_value UNIQUE (value_of);


--
-- Name: seniority uq_seniority_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.seniority
    ADD CONSTRAINT uq_seniority_name_of UNIQUE (name_of);


--
-- Name: skill uq_skill_name; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.skill
    ADD CONSTRAINT uq_skill_name UNIQUE (name_of);


--
-- Name: union uq_union_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta."union"
    ADD CONSTRAINT uq_union_name_of UNIQUE (name_of);


--
-- Name: work_group uq_work_group_name_of; Type: CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.work_group
    ADD CONSTRAINT uq_work_group_name_of UNIQUE (name_of);


--
-- Name: config config_pkey; Type: CONSTRAINT; Schema: geo_master; Owner: edulog
--

ALTER TABLE ONLY geo_master.config
    ADD CONSTRAINT config_pkey PRIMARY KEY (id);


--
-- Name: geoserver_layer geoserver_layer_pkey; Type: CONSTRAINT; Schema: geo_master; Owner: edulog
--

ALTER TABLE ONLY geo_master.geoserver_layer
    ADD CONSTRAINT geoserver_layer_pkey PRIMARY KEY (id);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (id);


--
-- Name: adj_except adj_except_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.adj_except
    ADD CONSTRAINT adj_except_pkey PRIMARY KEY (id);


--
-- Name: boundary_group_mapping boundary_group_mapping_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary_group_mapping
    ADD CONSTRAINT boundary_group_mapping_pkey PRIMARY KEY (boundary_id, boundary_group_id);


--
-- Name: boundary boundary_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary
    ADD CONSTRAINT boundary_pkey PRIMARY KEY (id);


--
-- Name: export_file export_file_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.export_file
    ADD CONSTRAINT export_file_pkey PRIMARY KEY (id);


--
-- Name: boundary_group group_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary_group
    ADD CONSTRAINT group_pkey PRIMARY KEY (id);


--
-- Name: landmark landmark_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.landmark
    ADD CONSTRAINT landmark_pkey PRIMARY KEY (id);


--
-- Name: legal_description legal_description_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.legal_description
    ADD CONSTRAINT legal_description_pkey PRIMARY KEY (id);


--
-- Name: location location_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.location
    ADD CONSTRAINT location_pkey PRIMARY KEY (id);


--
-- Name: mile_marker mile_marker_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.mile_marker
    ADD CONSTRAINT mile_marker_pkey PRIMARY KEY (id);


--
-- Name: node node_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.node
    ADD CONSTRAINT node_pkey PRIMARY KEY (id);


--
-- Name: parsing parsing_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.parsing
    ADD CONSTRAINT parsing_pkey PRIMARY KEY (id);


--
-- Name: segment segment_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.segment
    ADD CONSTRAINT segment_pkey PRIMARY KEY (id);


--
-- Name: street street_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.street
    ADD CONSTRAINT street_pkey PRIMARY KEY (id);


--
-- Name: street_segment street_segment_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.street_segment
    ADD CONSTRAINT street_segment_pkey PRIMARY KEY (id);


--
-- Name: boundary uq_boundary_surrogate_key; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary
    ADD CONSTRAINT uq_boundary_surrogate_key UNIQUE (surrogate_key);


--
-- Name: zipcode zipcode_pkey; Type: CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.zipcode
    ADD CONSTRAINT zipcode_pkey PRIMARY KEY (id);


--
-- Name: image pk_image; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.image
    ADD CONSTRAINT pk_image PRIMARY KEY (id);


--
-- Name: inspection_zone pk_inspec_zone; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_zone
    ADD CONSTRAINT pk_inspec_zone PRIMARY KEY (id);


--
-- Name: inspection pk_inspection; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection
    ADD CONSTRAINT pk_inspection PRIMARY KEY (id);


--
-- Name: inspection_point pk_inspection_point; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_point
    ADD CONSTRAINT pk_inspection_point PRIMARY KEY (id);


--
-- Name: template pk_temp; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template
    ADD CONSTRAINT pk_temp PRIMARY KEY (id);


--
-- Name: template_point pk_template_point; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point
    ADD CONSTRAINT pk_template_point PRIMARY KEY (id);


--
-- Name: template_point_validation pk_template_point_validation; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation
    ADD CONSTRAINT pk_template_point_validation PRIMARY KEY (id);


--
-- Name: template_point_validation_type pk_template_point_validation_type; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation_type
    ADD CONSTRAINT pk_template_point_validation_type PRIMARY KEY (id);


--
-- Name: template_zone pk_template_zone; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_zone
    ADD CONSTRAINT pk_template_zone PRIMARY KEY (id);


--
-- Name: i_type pk_type; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.i_type
    ADD CONSTRAINT pk_type PRIMARY KEY (id);


--
-- Name: validation_type pk_valid_type; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.validation_type
    ADD CONSTRAINT pk_valid_type PRIMARY KEY (id);


--
-- Name: i_zone pk_zone; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.i_zone
    ADD CONSTRAINT pk_zone PRIMARY KEY (id);


--
-- Name: i_type uq_name; Type: CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.i_type
    ADD CONSTRAINT uq_name UNIQUE (name_of);


--
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: edulog
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- Name: report_info pk_report_info; Type: CONSTRAINT; Schema: public; Owner: edulog
--

ALTER TABLE ONLY public.report_info
    ADD CONSTRAINT pk_report_info PRIMARY KEY (id);


--
-- Name: cal_cal_event cal_cal_event_pk; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal_cal_event
    ADD CONSTRAINT cal_cal_event_pk PRIMARY KEY (id);


--
-- Name: cal_event cal_event_pkey; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal_event
    ADD CONSTRAINT cal_event_pkey PRIMARY KEY (id);


--
-- Name: cal cal_pkey; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal
    ADD CONSTRAINT cal_pkey PRIMARY KEY (id);


--
-- Name: access pk_access; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access
    ADD CONSTRAINT pk_access PRIMARY KEY (id);


--
-- Name: access_domain pk_access_domain; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access_domain
    ADD CONSTRAINT pk_access_domain PRIMARY KEY (id);


--
-- Name: access_school pk_access_school; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access_school
    ADD CONSTRAINT pk_access_school PRIMARY KEY (id);


--
-- Name: avl_event pk_avl_event; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_event
    ADD CONSTRAINT pk_avl_event PRIMARY KEY (id);


--
-- Name: avl_template pk_avl_template; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_template
    ADD CONSTRAINT pk_avl_template PRIMARY KEY (id);


--
-- Name: data_area pk_data_area; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area
    ADD CONSTRAINT pk_data_area PRIMARY KEY (id);


--
-- Name: import_value_mapping pk_import_value_mapping; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.import_value_mapping
    ADD CONSTRAINT pk_import_value_mapping PRIMARY KEY (id);


--
-- Name: plan_rollover pk_plan_rollover; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.plan_rollover
    ADD CONSTRAINT pk_plan_rollover UNIQUE (id);


--
-- Name: plan_rollover_log_items pk_plan_rollover_log_items; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.plan_rollover_log_items
    ADD CONSTRAINT pk_plan_rollover_log_items UNIQUE (id);


--
-- Name: user_profile pk_profile; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile
    ADD CONSTRAINT pk_profile PRIMARY KEY (id);


--
-- Name: authentication_scope pk_scope; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.authentication_scope
    ADD CONSTRAINT pk_scope UNIQUE (application, groupof, roleof);


--
-- Name: user pk_user; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master."user"
    ADD CONSTRAINT pk_user UNIQUE (id);


--
-- Name: user_profile_template pk_user_profile_template; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template
    ADD CONSTRAINT pk_user_profile_template PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_un; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.role_permissions
    ADD CONSTRAINT role_permissions_un UNIQUE (name_of);


--
-- Name: authentication_scope scope_pkey; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.authentication_scope
    ADD CONSTRAINT scope_pkey PRIMARY KEY (id);


--
-- Name: student_import_conf student_import_conf_pkey; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.student_import_conf
    ADD CONSTRAINT student_import_conf_pkey PRIMARY KEY (id);


--
-- Name: student_import_mapping student_import_mapping_pkey; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.student_import_mapping
    ADD CONSTRAINT student_import_mapping_pkey PRIMARY KEY (id);


--
-- Name: access uq_access_name_of; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access
    ADD CONSTRAINT uq_access_name_of UNIQUE (name_of);


--
-- Name: access uq_access_surrogate_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access
    ADD CONSTRAINT uq_access_surrogate_key UNIQUE (surrogate_key);


--
-- Name: avl_event uq_avl_event_surrogate_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_event
    ADD CONSTRAINT uq_avl_event_surrogate_key UNIQUE (surrogate_key);


--
-- Name: avl_template uq_avl_template_name_of; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_template
    ADD CONSTRAINT uq_avl_template_name_of UNIQUE (name_of);


--
-- Name: avl_template uq_avl_template_surrogate_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_template
    ADD CONSTRAINT uq_avl_template_surrogate_key UNIQUE (surrogate_key);


--
-- Name: data_area uq_data_area_geo_schema; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area
    ADD CONSTRAINT uq_data_area_geo_schema UNIQUE (geo_schema);


--
-- Name: data_area uq_data_area_name_of; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area
    ADD CONSTRAINT uq_data_area_name_of UNIQUE (name_of);


--
-- Name: data_area uq_data_area_rp_schema; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area
    ADD CONSTRAINT uq_data_area_rp_schema UNIQUE (rp_schema);


--
-- Name: data_area uq_data_area_sort_order; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area
    ADD CONSTRAINT uq_data_area_sort_order UNIQUE (rolling_seq);


--
-- Name: data_area uq_data_area_surrogate_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.data_area
    ADD CONSTRAINT uq_data_area_surrogate_key UNIQUE (surrogate_key);


--
-- Name: import_value_mapping uq_import_value_mapping_internal_value_type_of_value; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.import_value_mapping
    ADD CONSTRAINT uq_import_value_mapping_internal_value_type_of_value UNIQUE (external_value, type_of_value);


--
-- Name: import_value_mapping uq_import_value_mapping_surrogate_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.import_value_mapping
    ADD CONSTRAINT uq_import_value_mapping_surrogate_key UNIQUE (surrogate_key);


--
-- Name: user user_email_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- Name: user user_person_id_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master."user"
    ADD CONSTRAINT user_person_id_key UNIQUE (person_id);


--
-- Name: user_profile user_profile_surrogate_un; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile
    ADD CONSTRAINT user_profile_surrogate_un UNIQUE (surrogate_key);


--
-- Name: user_profile_template user_profile_template_name_key; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template
    ADD CONSTRAINT user_profile_template_name_key UNIQUE (name_of);


--
-- Name: user_profile_template user_profile_template_surrogate_un; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template
    ADD CONSTRAINT user_profile_template_surrogate_un UNIQUE (surrogate_key);


--
-- Name: user_profile user_profile_un; Type: CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile
    ADD CONSTRAINT user_profile_un UNIQUE (user_id, user_profile_template_id);


--
-- Name: domain domain_name_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.domain
    ADD CONSTRAINT domain_name_key UNIQUE (name);


--
-- Name: belltime pk_belltime; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.belltime
    ADD CONSTRAINT pk_belltime PRIMARY KEY (id);


--
-- Name: cluster pk_cluster; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster
    ADD CONSTRAINT pk_cluster PRIMARY KEY (id);


--
-- Name: cluster_belltime pk_cluster_belltime; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster_belltime
    ADD CONSTRAINT pk_cluster_belltime PRIMARY KEY (id);


--
-- Name: contact pk_contact; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contact
    ADD CONSTRAINT pk_contact PRIMARY KEY (id);


--
-- Name: contractor pk_contractor; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contractor
    ADD CONSTRAINT pk_contractor PRIMARY KEY (id);


--
-- Name: direction_step pk_direction_step; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.direction_step
    ADD CONSTRAINT pk_direction_step PRIMARY KEY (id);


--
-- Name: district_eligibility pk_district_eligibility; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.district_eligibility
    ADD CONSTRAINT pk_district_eligibility PRIMARY KEY (id);


--
-- Name: domain pk_domain; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.domain
    ADD CONSTRAINT pk_domain PRIMARY KEY (id);


--
-- Name: eligibility_rule pk_eligibility_rule; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.eligibility_rule
    ADD CONSTRAINT pk_eligibility_rule PRIMARY KEY (id);


--
-- Name: gps_unit pk_gps_unit; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.gps_unit
    ADD CONSTRAINT pk_gps_unit PRIMARY KEY (id);


--
-- Name: grade pk_grade; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.grade
    ADD CONSTRAINT pk_grade PRIMARY KEY (id);


--
-- Name: hazard_zone pk_hazard_zone; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.hazard_zone
    ADD CONSTRAINT pk_hazard_zone PRIMARY KEY (id);


--
-- Name: head_count pk_head_count; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.head_count
    ADD CONSTRAINT pk_head_count PRIMARY KEY (id);


--
-- Name: inactive_student pk_inactive_student; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student
    ADD CONSTRAINT pk_inactive_student PRIMARY KEY (id);


--
-- Name: load_time pk_load_time; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.load_time
    ADD CONSTRAINT pk_load_time PRIMARY KEY (id);


--
-- Name: location pk_location; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.location
    ADD CONSTRAINT pk_location PRIMARY KEY (id);


--
-- Name: need pk_need; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.need
    ADD CONSTRAINT pk_need PRIMARY KEY (id);


--
-- Name: path_master pk_path; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_master
    ADD CONSTRAINT pk_path PRIMARY KEY (id);


--
-- Name: path_cover pk_path_cover; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_cover
    ADD CONSTRAINT pk_path_cover PRIMARY KEY (id);


--
-- Name: program pk_program; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.program
    ADD CONSTRAINT pk_program PRIMARY KEY (id);


--
-- Name: route pk_route; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route
    ADD CONSTRAINT pk_route PRIMARY KEY (id);


--
-- Name: route_contact pk_route_contact; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_contact
    ADD CONSTRAINT pk_route_contact PRIMARY KEY (id);


--
-- Name: route_run pk_route_run; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_run
    ADD CONSTRAINT pk_route_run PRIMARY KEY (id);


--
-- Name: run pk_run; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.run
    ADD CONSTRAINT pk_run PRIMARY KEY (id);


--
-- Name: school pk_school; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school
    ADD CONSTRAINT pk_school PRIMARY KEY (id);


--
-- Name: school_contact pk_school_contact; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_contact
    ADD CONSTRAINT pk_school_contact PRIMARY KEY (id);


--
-- Name: school_district pk_school_district; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_district
    ADD CONSTRAINT pk_school_district PRIMARY KEY (id);


--
-- Name: school_location pk_school_location; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_location
    ADD CONSTRAINT pk_school_location PRIMARY KEY (id);


--
-- Name: school_operation_master pk_school_operation; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master
    ADD CONSTRAINT pk_school_operation PRIMARY KEY (id);


--
-- Name: school_operation_master_boundary pk_school_operation_boundary; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master_boundary
    ADD CONSTRAINT pk_school_operation_boundary PRIMARY KEY (id);


--
-- Name: school_operation_cover pk_school_operation_cover; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_cover
    ADD CONSTRAINT pk_school_operation_cover PRIMARY KEY (id);


--
-- Name: site_meta_data pk_site_meta_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_meta_data
    ADD CONSTRAINT pk_site_meta_data PRIMARY KEY (id);


--
-- Name: site_route_data pk_site_route_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_route_data
    ADD CONSTRAINT pk_site_route_data PRIMARY KEY (id);


--
-- Name: site_run_data pk_site_run_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_run_data
    ADD CONSTRAINT pk_site_run_data PRIMARY KEY (id);


--
-- Name: site_school_data pk_site_school_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_school_data
    ADD CONSTRAINT pk_site_school_data PRIMARY KEY (id);


--
-- Name: site_stop_data pk_site_stop_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_stop_data
    ADD CONSTRAINT pk_site_stop_data PRIMARY KEY (id);


--
-- Name: site_student_data pk_site_student_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_student_data
    ADD CONSTRAINT pk_site_student_data PRIMARY KEY (id);


--
-- Name: site_trip_data pk_site_trip_data; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_trip_data
    ADD CONSTRAINT pk_site_trip_data PRIMARY KEY (trip_master_id);


--
-- Name: stop pk_stop; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.stop
    ADD CONSTRAINT pk_stop PRIMARY KEY (id);


--
-- Name: student pk_student; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT pk_student PRIMARY KEY (id);


--
-- Name: student_contact pk_student_contact; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_contact
    ADD CONSTRAINT pk_student_contact PRIMARY KEY (id);


--
-- Name: medical_note pk_student_medical_note; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.medical_note
    ADD CONSTRAINT pk_student_medical_note PRIMARY KEY (id);


--
-- Name: student_need pk_student_need; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_need
    ADD CONSTRAINT pk_student_need PRIMARY KEY (id);


--
-- Name: student_note pk_student_note; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_note
    ADD CONSTRAINT pk_student_note PRIMARY KEY (id);


--
-- Name: student_transport_need pk_student_transport_need; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_transport_need
    ADD CONSTRAINT pk_student_transport_need PRIMARY KEY (id);


--
-- Name: trip_master pk_student_trip; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_master
    ADD CONSTRAINT pk_student_trip PRIMARY KEY (id);


--
-- Name: transport_def_cover pk_transport_def_cover; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_cover
    ADD CONSTRAINT pk_transport_def_cover PRIMARY KEY (id);


--
-- Name: transport_def_master pk_transport_def_master; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master
    ADD CONSTRAINT pk_transport_def_master PRIMARY KEY (id);


--
-- Name: transport_itinerary pk_transport_itinerary; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_itinerary
    ADD CONSTRAINT pk_transport_itinerary PRIMARY KEY (id);


--
-- Name: transport_need pk_transport_need; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_need
    ADD CONSTRAINT pk_transport_need PRIMARY KEY (id);


--
-- Name: transport_request pk_transport_request; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request
    ADD CONSTRAINT pk_transport_request PRIMARY KEY (id);


--
-- Name: transport_request_detail pk_transport_request_detail; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request_detail
    ADD CONSTRAINT pk_transport_request_detail PRIMARY KEY (id);


--
-- Name: trip_cover pk_trip_cover; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_cover
    ADD CONSTRAINT pk_trip_cover PRIMARY KEY (id);


--
-- Name: trip_leg pk_trip_leg; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg
    ADD CONSTRAINT pk_trip_leg PRIMARY KEY (id);


--
-- Name: trip_leg_waypoint_master pk_trip_leg_waypoint_master; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master
    ADD CONSTRAINT pk_trip_leg_waypoint_master PRIMARY KEY (id);


--
-- Name: vehicle pk_vehicle; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle
    ADD CONSTRAINT pk_vehicle PRIMARY KEY (id);


--
-- Name: vehicle_maintenance pk_vehicle_maintenance; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_maintenance
    ADD CONSTRAINT pk_vehicle_maintenance PRIMARY KEY (id);


--
-- Name: waypoint_cover pk_waypoint_cover; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover
    ADD CONSTRAINT pk_waypoint_cover PRIMARY KEY (id);


--
-- Name: waypoint_cover_belltime pk_waypoint_cover_belltime; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover_belltime
    ADD CONSTRAINT pk_waypoint_cover_belltime PRIMARY KEY (id);


--
-- Name: waypoint_master pk_waypoint_master; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_master
    ADD CONSTRAINT pk_waypoint_master PRIMARY KEY (id);


--
-- Name: student_import_line student_import_line_pkey; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_import_line
    ADD CONSTRAINT student_import_line_pkey PRIMARY KEY (id);


--
-- Name: belltime uq_belltime_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.belltime
    ADD CONSTRAINT uq_belltime_surrogate_key UNIQUE (surrogate_key);


--
-- Name: cluster_belltime uq_cluster_belltime_cluster_id_belltime_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster_belltime
    ADD CONSTRAINT uq_cluster_belltime_cluster_id_belltime_id UNIQUE (cluster_id, belltime_id);


--
-- Name: cluster uq_cluster_name_of; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster
    ADD CONSTRAINT uq_cluster_name_of UNIQUE (name_of);


--
-- Name: cluster uq_cluster_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster
    ADD CONSTRAINT uq_cluster_surrogate_key UNIQUE (surrogate_key);


--
-- Name: contact uq_contact_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contact
    ADD CONSTRAINT uq_contact_surrogate_key UNIQUE (surrogate_key);


--
-- Name: contractor uq_contractor_name_of; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contractor
    ADD CONSTRAINT uq_contractor_name_of UNIQUE (name_of);


--
-- Name: contractor uq_contractor_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.contractor
    ADD CONSTRAINT uq_contractor_surrogate_key UNIQUE (surrogate_key);


--
-- Name: direction_step uq_direction_step_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.direction_step
    ADD CONSTRAINT uq_direction_step_surrogate_key UNIQUE (surrogate_key);


--
-- Name: eligibility_rule uq_eligibility_rule_name_of; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.eligibility_rule
    ADD CONSTRAINT uq_eligibility_rule_name_of UNIQUE (name_of);


--
-- Name: eligibility_rule uq_eligibility_rule_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.eligibility_rule
    ADD CONSTRAINT uq_eligibility_rule_surrogate_key UNIQUE (surrogate_key);


--
-- Name: gps_unit uq_gps_unit_device_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.gps_unit
    ADD CONSTRAINT uq_gps_unit_device_id UNIQUE (device_id);


--
-- Name: gps_unit uq_gps_unit_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.gps_unit
    ADD CONSTRAINT uq_gps_unit_surrogate_key UNIQUE (surrogate_key);


--
-- Name: grade uq_grade_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.grade
    ADD CONSTRAINT uq_grade_surrogate_key UNIQUE (surrogate_key);


--
-- Name: hazard_zone uq_hazard_zone_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.hazard_zone
    ADD CONSTRAINT uq_hazard_zone_surrogate_key UNIQUE (surrogate_key);


--
-- Name: inactive_student uq_inactive_student_district_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student
    ADD CONSTRAINT uq_inactive_student_district_id UNIQUE (district_id);


--
-- Name: inactive_student uq_inactive_student_edulog_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student
    ADD CONSTRAINT uq_inactive_student_edulog_id UNIQUE (edulog_id);


--
-- Name: inactive_student uq_inactive_student_government_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student
    ADD CONSTRAINT uq_inactive_student_government_id UNIQUE (government_id);


--
-- Name: inactive_student uq_inactive_student_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student
    ADD CONSTRAINT uq_inactive_student_surrogate_key UNIQUE (surrogate_key);


--
-- Name: location uq_location_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.location
    ADD CONSTRAINT uq_location_surrogate_key UNIQUE (surrogate_key);


--
-- Name: medical_note uq_medical_note_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.medical_note
    ADD CONSTRAINT uq_medical_note_surrogate_key UNIQUE (surrogate_key);


--
-- Name: path_cover uq_path_cover_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_cover
    ADD CONSTRAINT uq_path_cover_surrogate_key UNIQUE (surrogate_key);


--
-- Name: path_master uq_path_master_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_master
    ADD CONSTRAINT uq_path_master_surrogate_key UNIQUE (surrogate_key);


--
-- Name: program uq_program_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.program
    ADD CONSTRAINT uq_program_surrogate_key UNIQUE (surrogate_key);


--
-- Name: route uq_route_code; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route
    ADD CONSTRAINT uq_route_code UNIQUE (code);


--
-- Name: route_contact uq_route_contact_route_id_contact_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_contact
    ADD CONSTRAINT uq_route_contact_route_id_contact_id UNIQUE (route_id, contact_id);


--
-- Name: route_run uq_route_run_route_id_run_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_run
    ADD CONSTRAINT uq_route_run_route_id_run_id UNIQUE (route_id, run_id);


--
-- Name: route uq_route_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route
    ADD CONSTRAINT uq_route_surrogate_key UNIQUE (surrogate_key);


--
-- Name: run uq_run_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.run
    ADD CONSTRAINT uq_run_surrogate_key UNIQUE (surrogate_key);


--
-- Name: school_contact uq_school_contact_school_id_contact_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_contact
    ADD CONSTRAINT uq_school_contact_school_id_contact_id UNIQUE (school_id, contact_id);


--
-- Name: school_district uq_school_district_code; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_district
    ADD CONSTRAINT uq_school_district_code UNIQUE (code);


--
-- Name: school_district uq_school_district_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_district
    ADD CONSTRAINT uq_school_district_surrogate_key UNIQUE (surrogate_key);


--
-- Name: school_location uq_school_location_school_id_location_id_type_of; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_location
    ADD CONSTRAINT uq_school_location_school_id_location_id_type_of UNIQUE (school_id, location_id, type_of);


--
-- Name: school_operation_master uq_school_operation_master_school_id_grade_id_program_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master
    ADD CONSTRAINT uq_school_operation_master_school_id_grade_id_program_id UNIQUE (school_id, grade_id, program_id);


--
-- Name: school uq_school_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school
    ADD CONSTRAINT uq_school_surrogate_key UNIQUE (surrogate_key);


--
-- Name: stop uq_stop_location_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.stop
    ADD CONSTRAINT uq_stop_location_id UNIQUE (location_id);


--
-- Name: stop uq_stop_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.stop
    ADD CONSTRAINT uq_stop_surrogate_key UNIQUE (surrogate_key);


--
-- Name: student_contact uq_student_contact_student_id_contact_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_contact
    ADD CONSTRAINT uq_student_contact_student_id_contact_id UNIQUE (student_id, contact_id);


--
-- Name: student uq_student_district_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT uq_student_district_id UNIQUE (district_id);


--
-- Name: student uq_student_edulog_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT uq_student_edulog_id UNIQUE (edulog_id);


--
-- Name: student uq_student_government_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT uq_student_government_id UNIQUE (government_id);


--
-- Name: student uq_student_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT uq_student_surrogate_key UNIQUE (surrogate_key);


--
-- Name: transport_def_cover uq_transport_def_cover_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_cover
    ADD CONSTRAINT uq_transport_def_cover_surrogate_key UNIQUE (surrogate_key);


--
-- Name: transport_def_master uq_transport_def_master_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master
    ADD CONSTRAINT uq_transport_def_master_surrogate_key UNIQUE (surrogate_key);


--
-- Name: transport_itinerary uq_transport_itinerary_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_itinerary
    ADD CONSTRAINT uq_transport_itinerary_surrogate_key UNIQUE (surrogate_key);


--
-- Name: transport_request_detail uq_transport_request_detail_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request_detail
    ADD CONSTRAINT uq_transport_request_detail_surrogate_key UNIQUE (surrogate_key);


--
-- Name: transport_request uq_transport_request_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request
    ADD CONSTRAINT uq_transport_request_surrogate_key UNIQUE (surrogate_key);


--
-- Name: trip_cover uq_trip_cover_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_cover
    ADD CONSTRAINT uq_trip_cover_surrogate_key UNIQUE (surrogate_key);


--
-- Name: trip_leg uq_trip_leg_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg
    ADD CONSTRAINT uq_trip_leg_surrogate_key UNIQUE (surrogate_key);


--
-- Name: trip_leg_waypoint_master uq_trip_leg_waypoint_master_trip_leg_id_waypoint_master_id_dest; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master
    ADD CONSTRAINT uq_trip_leg_waypoint_master_trip_leg_id_waypoint_master_id_dest UNIQUE (trip_leg_id, waypoint_master_id_destination);


--
-- Name: trip_leg_waypoint_master uq_trip_leg_waypoint_master_trip_leg_id_waypoint_master_id_orig; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master
    ADD CONSTRAINT uq_trip_leg_waypoint_master_trip_leg_id_waypoint_master_id_orig UNIQUE (trip_leg_id, waypoint_master_id_origin);


--
-- Name: trip_master uq_trip_master_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_master
    ADD CONSTRAINT uq_trip_master_surrogate_key UNIQUE (surrogate_key);


--
-- Name: vehicle uq_vehicle_name_of; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle
    ADD CONSTRAINT uq_vehicle_name_of UNIQUE (name_of);


--
-- Name: vehicle uq_vehicle_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle
    ADD CONSTRAINT uq_vehicle_surrogate_key UNIQUE (surrogate_key);


--
-- Name: vehicle_transport_need uq_vehicle_transport_need_vehicle_id_transport_need_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_transport_need
    ADD CONSTRAINT uq_vehicle_transport_need_vehicle_id_transport_need_id UNIQUE (vehicle_id, transport_need_id);


--
-- Name: vehicle uq_vehicle_vin; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle
    ADD CONSTRAINT uq_vehicle_vin UNIQUE (vin);


--
-- Name: waypoint_cover_belltime uq_waypoint_cover_belltime_waypoint_id_cover_belltime_id; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover_belltime
    ADD CONSTRAINT uq_waypoint_cover_belltime_waypoint_id_cover_belltime_id UNIQUE (waypoint_cover_id, belltime_id);


--
-- Name: waypoint_cover uq_waypoint_cover_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover
    ADD CONSTRAINT uq_waypoint_cover_surrogate_key UNIQUE (surrogate_key);


--
-- Name: waypoint_master uq_waypoint_master_surrogate_key; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_master
    ADD CONSTRAINT uq_waypoint_master_surrogate_key UNIQUE (surrogate_key);


--
-- Name: vehicle_transport_need vehicle_transport_need_pkey; Type: CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_transport_need
    ADD CONSTRAINT vehicle_transport_need_pkey PRIMARY KEY (id);


--
-- Name: board pk_board; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.board
    ADD CONSTRAINT pk_board PRIMARY KEY (label);


--
-- Name: city pk_city; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.city
    ADD CONSTRAINT pk_city PRIMARY KEY (label);


--
-- Name: ethnicity pk_ethnicity; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.ethnicity
    ADD CONSTRAINT pk_ethnicity PRIMARY KEY (label);


--
-- Name: form_of_address pk_form_of_address; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.form_of_address
    ADD CONSTRAINT pk_form_of_address PRIMARY KEY (title);


--
-- Name: hazard_type pk_hazard_type; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.hazard_type
    ADD CONSTRAINT pk_hazard_type PRIMARY KEY (description);


--
-- Name: language pk_language; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.language
    ADD CONSTRAINT pk_language PRIMARY KEY (description);


--
-- Name: postal_code pk_postal_code; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.postal_code
    ADD CONSTRAINT pk_postal_code PRIMARY KEY (code);


--
-- Name: route_contact_relationship pk_route_contact_relationship; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.route_contact_relationship
    ADD CONSTRAINT pk_route_contact_relationship PRIMARY KEY (title);


--
-- Name: school_calendar pk_school_calendar; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.school_calendar
    ADD CONSTRAINT pk_school_calendar PRIMARY KEY (label);


--
-- Name: school_contact_relationship pk_school_contact_relationship; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.school_contact_relationship
    ADD CONSTRAINT pk_school_contact_relationship PRIMARY KEY (title);


--
-- Name: school_type pk_schooltype; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.school_type
    ADD CONSTRAINT pk_schooltype PRIMARY KEY (description);


--
-- Name: state_country pk_state_country; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.state_country
    ADD CONSTRAINT pk_state_country PRIMARY KEY (state_code);


--
-- Name: student_contact_relationship pk_student_contact_relationship; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.student_contact_relationship
    ADD CONSTRAINT pk_student_contact_relationship PRIMARY KEY (title);


--
-- Name: user_title pk_user_title; Type: CONSTRAINT; Schema: settings; Owner: edulog
--

ALTER TABLE ONLY settings.user_title
    ADD CONSTRAINT pk_user_title PRIMARY KEY (title);


--
-- Name: idx_transaction_activity_id; Type: INDEX; Schema: edta; Owner: edulog
--

CREATE INDEX idx_transaction_activity_id ON edta.transaction USING btree (activity_id);


--
-- Name: idx_transaction_billing_type_id; Type: INDEX; Schema: edta; Owner: edulog
--

CREATE INDEX idx_transaction_billing_type_id ON edta.transaction USING btree (billing_type_id);


--
-- Name: idx_transaction_date_of; Type: INDEX; Schema: edta; Owner: edulog
--

CREATE INDEX idx_transaction_date_of ON edta.transaction USING btree (date_of);


--
-- Name: idx_transaction_driver_info_id; Type: INDEX; Schema: edta; Owner: edulog
--

CREATE INDEX idx_transaction_driver_info_id ON edta.transaction USING btree (driver_info_id);


--
-- Name: idx_transaction_parent_id; Type: INDEX; Schema: edta; Owner: edulog
--

CREATE INDEX idx_transaction_parent_id ON edta.transaction USING btree (parent_id);


--
-- Name: geo_config_uq; Type: INDEX; Schema: geo_master; Owner: edulog
--

CREATE UNIQUE INDEX geo_config_uq ON geo_master.config USING btree (application, setting);


--
-- Name: geo_boundary_code_uq; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE UNIQUE INDEX geo_boundary_code_uq ON geo_plan.boundary USING btree (code);


--
-- Name: geo_boundary_geo_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_boundary_geo_idx ON geo_plan.boundary USING gist (geo);


--
-- Name: geo_landmark_name_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_landmark_name_idx ON geo_plan.landmark USING btree (name_of);


--
-- Name: geo_location_calc_geo_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_location_calc_geo_idx ON geo_plan.location USING gist (calc_geo);


--
-- Name: geo_location_opt_geo_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_location_opt_geo_idx ON geo_plan.location USING gist (opt_geo);


--
-- Name: geo_location_orig_geo_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_location_orig_geo_idx ON geo_plan.location USING gist (orig_geo);


--
-- Name: geo_node_geo_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_node_geo_idx ON geo_plan.node USING gist (geo);


--
-- Name: geo_segment_from_node_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_segment_from_node_idx ON geo_plan.segment USING btree (from_node);


--
-- Name: geo_segment_from_to_node_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_segment_from_to_node_idx ON geo_plan.segment USING btree (from_node, to_node);


--
-- Name: geo_segment_geo_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_segment_geo_idx ON geo_plan.segment USING gist (geo);


--
-- Name: geo_segment_geom_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_segment_geom_idx ON geo_plan.segment USING gist (geom_geoserver);


--
-- Name: geo_segment_to_node_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_segment_to_node_idx ON geo_plan.segment USING btree (to_node);


--
-- Name: geo_street_name_idx; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE INDEX geo_street_name_idx ON geo_plan.street USING btree (name_of);


--
-- Name: ui_boundary_group_code; Type: INDEX; Schema: geo_plan; Owner: edulog
--

CREATE UNIQUE INDEX ui_boundary_group_code ON geo_plan.boundary_group USING btree (code);


--
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: edulog
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- Name: cal_cal_event_id_uindex; Type: INDEX; Schema: rp_master; Owner: edulog
--

CREATE UNIQUE INDEX cal_cal_event_id_uindex ON rp_master.cal_cal_event USING btree (id);


--
-- Name: idx_avl_template_name_lower; Type: INDEX; Schema: rp_master; Owner: edulog
--

CREATE UNIQUE INDEX idx_avl_template_name_lower ON rp_master.avl_template USING btree (lower((name_of)::text));


--
-- Name: uq_cal_id_cal_event_id; Type: INDEX; Schema: rp_master; Owner: edulog
--

CREATE UNIQUE INDEX uq_cal_id_cal_event_id ON rp_master.cal_cal_event USING btree (cal_event_id, cal_id);


--
-- Name: idx_belltime_school_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_belltime_school_id_idx ON rp_plan.belltime USING btree (school_id);


--
-- Name: idx_cluster_belltime_belltime_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_cluster_belltime_belltime_id_idx ON rp_plan.cluster_belltime USING btree (belltime_id);


--
-- Name: idx_direction_step_path_cover_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_direction_step_path_cover_id_idx ON rp_plan.direction_step USING btree (path_cover_id);


--
-- Name: idx_direction_step_waypoint_cover_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_direction_step_waypoint_cover_id_idx ON rp_plan.direction_step USING btree (waypoint_cover_id);


--
-- Name: idx_hazard_zone_location_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_hazard_zone_location_id ON rp_plan.hazard_zone USING btree (location_id);


--
-- Name: idx_head_count_belltime_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_head_count_belltime_id ON rp_plan.head_count USING btree (belltime_id);


--
-- Name: idx_head_count_school_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_head_count_school_id ON rp_plan.head_count USING btree (school_id);


--
-- Name: idx_head_count_stop_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_head_count_stop_id ON rp_plan.head_count USING btree (stop_id);


--
-- Name: idx_head_count_waypoint_master_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_head_count_waypoint_master_id ON rp_plan.head_count USING btree (waypoint_master_id);


--
-- Name: idx_inactive_student_location_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_inactive_student_location_id_idx ON rp_plan.inactive_student USING btree (location_id);


--
-- Name: idx_medical_note_student_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_medical_note_student_id_idx ON rp_plan.medical_note USING btree (student_id);


--
-- Name: idx_need_description_lower; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE UNIQUE INDEX idx_need_description_lower ON rp_plan.need USING btree (lower((description)::text));


--
-- Name: idx_path_cover_path_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_path_cover_path_master_id_idx ON rp_plan.path_cover USING btree (path_master_id);


--
-- Name: idx_route_code; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_code ON rp_plan.route USING btree (code);


--
-- Name: idx_route_contact_contact_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_contact_contact_id_idx ON rp_plan.route_contact USING btree (contact_id);


--
-- Name: idx_route_contractor_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_contractor_id_idx ON rp_plan.route USING btree (contractor_id);


--
-- Name: idx_route_path_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_path_master_id_idx ON rp_plan.route USING btree (path_master_id);


--
-- Name: idx_route_run_route_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_run_route_id_idx ON rp_plan.route_run USING btree (route_id);


--
-- Name: idx_route_run_run_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_run_run_id_idx ON rp_plan.route_run USING btree (run_id);


--
-- Name: idx_route_vehicle_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_route_vehicle_id_idx ON rp_plan.route USING btree (vehicle_id);


--
-- Name: idx_school_cal_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_cal_id_idx ON rp_plan.school USING btree (cal_id);


--
-- Name: idx_school_code; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_code ON rp_plan.school USING btree (code);


--
-- Name: idx_school_contact_contact_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_contact_contact_id_idx ON rp_plan.school_contact USING btree (contact_id);


--
-- Name: idx_school_district_cal_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_district_cal_id_idx ON rp_plan.school_district USING btree (cal_id);


--
-- Name: idx_school_location_location_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_location_location_id_idx ON rp_plan.school_location USING btree (location_id);


--
-- Name: idx_school_operation_cover_belltime_id_arrival_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_operation_cover_belltime_id_arrival_idx ON rp_plan.school_operation_cover USING btree (belltime_id_arrival);


--
-- Name: idx_school_operation_cover_belltime_id_depart_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_operation_cover_belltime_id_depart_idx ON rp_plan.school_operation_cover USING btree (belltime_id_depart);


--
-- Name: idx_school_operation_cover_school_operation_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_operation_cover_school_operation_master_id_idx ON rp_plan.school_operation_cover USING btree (school_operation_master_id);


--
-- Name: idx_school_operation_master_grade_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_operation_master_grade_id_idx ON rp_plan.school_operation_master USING btree (grade_id);


--
-- Name: idx_school_operation_master_program_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_operation_master_program_id_idx ON rp_plan.school_operation_master USING btree (program_id);


--
-- Name: idx_school_school_district_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_school_school_district_id_idx ON rp_plan.school USING btree (school_district_id);


--
-- Name: idx_site_route_data_route_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_site_route_data_route_id_idx ON rp_plan.site_route_data USING btree (route_id);


--
-- Name: idx_site_run_data_run_id_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_site_run_data_run_id_id_idx ON rp_plan.site_run_data USING btree (run_id);


--
-- Name: idx_site_school_data_school_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_site_school_data_school_id_idx ON rp_plan.site_school_data USING btree (school_id);


--
-- Name: idx_site_stop_data_stop_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_site_stop_data_stop_id_idx ON rp_plan.site_stop_data USING btree (stop_id);


--
-- Name: idx_site_student_data_student_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_site_student_data_student_id_idx ON rp_plan.site_student_data USING btree (student_id);


--
-- Name: idx_stop_code_unique_upper; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE UNIQUE INDEX idx_stop_code_unique_upper ON rp_plan.stop USING btree (upper((code)::text));


--
-- Name: idx_stop_description; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_stop_description ON rp_plan.stop USING btree (description);


--
-- Name: idx_stop_government_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_stop_government_id ON rp_plan.stop USING btree (government_id);


--
-- Name: idx_stop_location_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_stop_location_id ON rp_plan.stop USING btree (location_id);


--
-- Name: idx_student_contact_contact_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_contact_contact_id_idx ON rp_plan.student_contact USING btree (contact_id);


--
-- Name: idx_student_district_eligibility_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_district_eligibility_id_idx ON rp_plan.student USING btree (district_eligibility_id);


--
-- Name: idx_student_district_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_district_id ON rp_plan.student USING btree (district_id);


--
-- Name: idx_student_edulog_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE UNIQUE INDEX idx_student_edulog_id ON rp_plan.student USING btree (edulog_id);


--
-- Name: idx_student_elg_code; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_elg_code ON rp_plan.student USING btree (elg_code);


--
-- Name: idx_student_first_name; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_first_name ON rp_plan.student USING btree (first_name);


--
-- Name: idx_student_government_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_government_id ON rp_plan.student USING btree (government_id);


--
-- Name: idx_student_iep; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_iep ON rp_plan.student USING btree (iep);


--
-- Name: idx_student_import_line_athena_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_import_line_athena_id_idx ON rp_plan.student_import_line USING btree (athena_id);


--
-- Name: idx_student_last_name; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_last_name ON rp_plan.student USING btree (last_name);


--
-- Name: idx_student_location_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_location_id ON rp_plan.student USING btree (location_id);


--
-- Name: idx_student_need_need_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_need_need_id_idx ON rp_plan.student_need USING btree (need_id);


--
-- Name: idx_student_need_student_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_need_student_id_idx ON rp_plan.student_need USING btree (student_id);


--
-- Name: idx_student_note_student_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_note_student_id_idx ON rp_plan.student_note USING btree (student_id);


--
-- Name: idx_student_school_operation_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_school_operation_master_id_idx ON rp_plan.student USING btree (school_operation_master_id);


--
-- Name: idx_student_transport_need_student_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_transport_need_student_id_idx ON rp_plan.student_transport_need USING btree (student_id);


--
-- Name: idx_student_transport_need_transport_need_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_student_transport_need_transport_need_id_idx ON rp_plan.student_transport_need USING btree (transport_need_id);


--
-- Name: idx_transport_def_cover_belltime_id_destination_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_cover_belltime_id_destination_idx ON rp_plan.transport_def_cover USING btree (belltime_id_destination);


--
-- Name: idx_transport_def_cover_belltime_id_origin_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_cover_belltime_id_origin_idx ON rp_plan.transport_def_cover USING btree (belltime_id_origin);


--
-- Name: idx_transport_def_cover_transport_def_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_cover_transport_def_master_id_idx ON rp_plan.transport_def_cover USING btree (transport_def_master_id);


--
-- Name: idx_transport_def_master_location_id_destination_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_master_location_id_destination_idx ON rp_plan.transport_def_master USING btree (location_id_destination);


--
-- Name: idx_transport_def_master_location_id_origin_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_master_location_id_origin_idx ON rp_plan.transport_def_master USING btree (location_id_origin);


--
-- Name: idx_transport_def_master_school_id_destination_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_master_school_id_destination_idx ON rp_plan.transport_def_master USING btree (school_id_destination);


--
-- Name: idx_transport_def_master_school_id_origin_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_def_master_school_id_origin_idx ON rp_plan.transport_def_master USING btree (school_id_origin);


--
-- Name: idx_transport_itinerary_transport_request_detail_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_itinerary_transport_request_detail_id_idx ON rp_plan.transport_itinerary USING btree (transport_request_detail_id);


--
-- Name: idx_transport_need_description_lower; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE UNIQUE INDEX idx_transport_need_description_lower ON rp_plan.transport_need USING btree (lower((description)::text));


--
-- Name: idx_transport_request_detail_transport_request_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_request_detail_transport_request_id_idx ON rp_plan.transport_request_detail USING btree (transport_request_id);


--
-- Name: idx_transport_request_location_id_requested_stop_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_request_location_id_requested_stop_idx ON rp_plan.transport_request USING btree (location_id_requested_stop);


--
-- Name: idx_transport_request_student_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_request_student_id_idx ON rp_plan.transport_request USING btree (student_id);


--
-- Name: idx_transport_request_transport_def_master_id_from_school_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_request_transport_def_master_id_from_school_idx ON rp_plan.transport_request USING btree (transport_def_master_id_from_school);


--
-- Name: idx_transport_request_transport_def_master_id_to_school_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_transport_request_transport_def_master_id_to_school_idx ON rp_plan.transport_request USING btree (transport_def_master_id_to_school);


--
-- Name: idx_trip_cover_transport_def_cover_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_trip_cover_transport_def_cover_id_idx ON rp_plan.trip_cover USING btree (transport_def_cover_id);


--
-- Name: idx_trip_leg_trip_cover_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_trip_leg_trip_cover_id_idx ON rp_plan.trip_leg USING btree (trip_cover_id);


--
-- Name: idx_trip_leg_waypoint_master_trip_leg_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_trip_leg_waypoint_master_trip_leg_id_idx ON rp_plan.trip_leg_waypoint_master USING btree (trip_leg_id);


--
-- Name: idx_trip_leg_waypoint_master_waypoint_master_id_destination; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_trip_leg_waypoint_master_waypoint_master_id_destination ON rp_plan.trip_leg_waypoint_master USING btree (waypoint_master_id_destination);


--
-- Name: idx_trip_leg_waypoint_master_waypoint_master_id_origin_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_trip_leg_waypoint_master_waypoint_master_id_origin_idx ON rp_plan.trip_leg_waypoint_master USING btree (waypoint_master_id_origin);


--
-- Name: idx_trip_master_transport_def_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_trip_master_transport_def_master_id_idx ON rp_plan.trip_master USING btree (transport_def_master_id);


--
-- Name: idx_vehicle_contractor_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_vehicle_contractor_id_idx ON rp_plan.vehicle USING btree (contractor_id);


--
-- Name: idx_vehicle_gps_unit_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_vehicle_gps_unit_id_idx ON rp_plan.vehicle USING btree (gps_unit_id);


--
-- Name: idx_vehicle_maintenance_id; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE UNIQUE INDEX idx_vehicle_maintenance_id ON rp_plan.vehicle_maintenance USING btree (id);


--
-- Name: idx_vehicle_maintenance_vehicle_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_vehicle_maintenance_vehicle_id_idx ON rp_plan.vehicle_maintenance USING btree (vehicle_id);


--
-- Name: idx_vehicle_transport_need_transport_need_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_vehicle_transport_need_transport_need_id_idx ON rp_plan.vehicle_transport_need USING btree (transport_need_id);


--
-- Name: idx_waypoint_cover_belltime_belltime_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_waypoint_cover_belltime_belltime_id_idx ON rp_plan.waypoint_cover_belltime USING btree (belltime_id);


--
-- Name: idx_waypoint_cover_path_cover_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_waypoint_cover_path_cover_id_idx ON rp_plan.waypoint_cover USING btree (path_cover_id);


--
-- Name: idx_waypoint_cover_waypoint_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_waypoint_cover_waypoint_master_id_idx ON rp_plan.waypoint_cover USING btree (waypoint_master_id);


--
-- Name: idx_waypoint_master_location_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_waypoint_master_location_id_idx ON rp_plan.waypoint_master USING btree (location_id);


--
-- Name: idx_waypoint_master_path_master_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_waypoint_master_path_master_id_idx ON rp_plan.waypoint_master USING btree (path_master_id);


--
-- Name: idx_waypoint_master_route_run_id_idx; Type: INDEX; Schema: rp_plan; Owner: edulog
--

CREATE INDEX idx_waypoint_master_route_run_id_idx ON rp_plan.waypoint_master USING btree (route_run_id);


--
-- Name: run_max_duration_view _RETURN; Type: RULE; Schema: rp_plan; Owner: edulog
--

CREATE OR REPLACE VIEW rp_plan.run_max_duration_view AS
 SELECT sub.run_id,
    (max(sub.dur) > sub.max_dur) AS over_max_duration
   FROM ( SELECT run.id AS run_id,
            path_cover.cover,
            (max(waypoint_cover.time_at) - min(waypoint_cover.time_at)) AS dur,
            ('00:00:01'::interval * (run.max_duration)::double precision) AS max_dur
           FROM ((((((rp_plan.waypoint_master
             LEFT JOIN rp_plan.waypoint_cover ON ((waypoint_master.id = waypoint_cover.waypoint_master_id)))
             LEFT JOIN rp_plan.path_cover ON ((path_cover.id = waypoint_cover.path_cover_id)))
             LEFT JOIN rp_plan.route_run ON ((route_run.id = waypoint_master.route_run_id)))
             LEFT JOIN rp_plan.stop ON ((stop.location_id = waypoint_master.location_id)))
             LEFT JOIN rp_plan.location ON ((stop.location_id = location.id)))
             LEFT JOIN rp_plan.run ON ((route_run.run_id = run.id)))
          WHERE (route_run.run_id IS NOT NULL)
          GROUP BY run.id, path_cover.cover
          ORDER BY run.id) sub
  GROUP BY sub.run_id, sub.max_dur
  ORDER BY sub.run_id;


--
-- Name: transaction fk_activity_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.transaction
    ADD CONSTRAINT fk_activity_id FOREIGN KEY (activity_id) REFERENCES edta.activity(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: driver_info fk_billing_type_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_billing_type_id FOREIGN KEY (billing_type_id) REFERENCES edta.billing_type(id) ON DELETE RESTRICT;


--
-- Name: transaction fk_billing_type_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.transaction
    ADD CONSTRAINT fk_billing_type_id FOREIGN KEY (billing_type_id) REFERENCES edta.billing_type(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: driver_info fk_department; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_department FOREIGN KEY (department_id) REFERENCES edta.department(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_driver_class; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_driver_class FOREIGN KEY (driver_class_id) REFERENCES edta.driver_class(id) ON DELETE RESTRICT;


--
-- Name: certification fk_driver_info_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.certification
    ADD CONSTRAINT fk_driver_info_id FOREIGN KEY (driver_info_id) REFERENCES edta.driver_info(id) ON DELETE CASCADE;


--
-- Name: training fk_driver_info_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.training
    ADD CONSTRAINT fk_driver_info_id FOREIGN KEY (driver_info_id) REFERENCES edta.driver_info(id) ON DELETE CASCADE;


--
-- Name: driver_skill fk_driver_info_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_skill
    ADD CONSTRAINT fk_driver_info_id FOREIGN KEY (driver_info_id) REFERENCES edta.driver_info(id) ON DELETE CASCADE;


--
-- Name: image fk_driver_info_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.image
    ADD CONSTRAINT fk_driver_info_id FOREIGN KEY (driver_info_id) REFERENCES edta.driver_info(id) ON DELETE CASCADE;


--
-- Name: transaction fk_driver_info_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.transaction
    ADD CONSTRAINT fk_driver_info_id FOREIGN KEY (driver_info_id) REFERENCES edta.driver_info(id) ON DELETE CASCADE;


--
-- Name: driver_info fk_emp_class_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_emp_class_id FOREIGN KEY (emp_class_id) REFERENCES edta.emp_class(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_emp_district_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_emp_district_id FOREIGN KEY (district_id) REFERENCES edta.district(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_emp_group_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_emp_group_id FOREIGN KEY (emp_group_id) REFERENCES edta.emp_group(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_grade; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_grade FOREIGN KEY (grade_id) REFERENCES edta.grade(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_level; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_level FOREIGN KEY (level_id) REFERENCES edta.level(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_license_class; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_license_class FOREIGN KEY (license_class_id) REFERENCES edta.license_class(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_scale_hour_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_scale_hour_id FOREIGN KEY (scale_hour_id) REFERENCES edta.scale_hour(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_seniority_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_seniority_id FOREIGN KEY (seniority_id) REFERENCES edta.seniority(id) ON DELETE RESTRICT;


--
-- Name: driver_skill fk_skill_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_skill
    ADD CONSTRAINT fk_skill_id FOREIGN KEY (skill_id) REFERENCES edta.skill(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_state_code_contact; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_state_code_contact FOREIGN KEY (state_code_contact) REFERENCES edta.state(code) ON DELETE RESTRICT;


--
-- Name: driver_info fk_state_code_license; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_state_code_license FOREIGN KEY (state_code_license) REFERENCES edta.state(code) ON DELETE RESTRICT;


--
-- Name: driver_info fk_union_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_union_id FOREIGN KEY (union_id) REFERENCES edta."union"(id) ON DELETE RESTRICT;


--
-- Name: driver_info fk_work_group_id; Type: FK CONSTRAINT; Schema: edta; Owner: edulog
--

ALTER TABLE ONLY edta.driver_info
    ADD CONSTRAINT fk_work_group_id FOREIGN KEY (work_group_id) REFERENCES edta.work_group(id) ON DELETE RESTRICT;


--
-- Name: address address_location_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.address
    ADD CONSTRAINT address_location_id_fkey FOREIGN KEY (location_id) REFERENCES geo_plan.location(id);


--
-- Name: boundary_group_mapping boundary_group_mapping_boundary_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary_group_mapping
    ADD CONSTRAINT boundary_group_mapping_boundary_id_fkey FOREIGN KEY (boundary_id) REFERENCES geo_plan.boundary(id);


--
-- Name: boundary_group_mapping boundary_group_mapping_group_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.boundary_group_mapping
    ADD CONSTRAINT boundary_group_mapping_group_id_fkey FOREIGN KEY (boundary_group_id) REFERENCES geo_plan.boundary_group(id);


--
-- Name: landmark landmark_location_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.landmark
    ADD CONSTRAINT landmark_location_id_fkey FOREIGN KEY (location_id) REFERENCES geo_plan.location(id);


--
-- Name: legal_description legal_description_location_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.legal_description
    ADD CONSTRAINT legal_description_location_id_fkey FOREIGN KEY (location_id) REFERENCES geo_plan.location(id);


--
-- Name: location location_street_segment_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.location
    ADD CONSTRAINT location_street_segment_id_fkey FOREIGN KEY (street_segment_id) REFERENCES geo_plan.street_segment(id);


--
-- Name: mile_marker mile_marker_location_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.mile_marker
    ADD CONSTRAINT mile_marker_location_id_fkey FOREIGN KEY (location_id) REFERENCES geo_plan.location(id);


--
-- Name: segment segment_from_node_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.segment
    ADD CONSTRAINT segment_from_node_fkey FOREIGN KEY (from_node) REFERENCES geo_plan.node(id);


--
-- Name: segment segment_to_node_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.segment
    ADD CONSTRAINT segment_to_node_fkey FOREIGN KEY (to_node) REFERENCES geo_plan.node(id);


--
-- Name: street_segment street_segment_segment_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.street_segment
    ADD CONSTRAINT street_segment_segment_id_fkey FOREIGN KEY (segment_id) REFERENCES geo_plan.segment(id);


--
-- Name: street_segment street_segment_street_id_fkey; Type: FK CONSTRAINT; Schema: geo_plan; Owner: edulog
--

ALTER TABLE ONLY geo_plan.street_segment
    ADD CONSTRAINT street_segment_street_id_fkey FOREIGN KEY (street_id) REFERENCES geo_plan.street(id);


--
-- Name: template fk_i_type_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template
    ADD CONSTRAINT fk_i_type_id FOREIGN KEY (i_type_id) REFERENCES ivin.i_type(id);


--
-- Name: template_zone fk_i_zone_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_zone
    ADD CONSTRAINT fk_i_zone_id FOREIGN KEY (i_zone_id) REFERENCES ivin.i_zone(id);


--
-- Name: inspection_zone fk_i_zone_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_zone
    ADD CONSTRAINT fk_i_zone_id FOREIGN KEY (i_zone_id) REFERENCES ivin.i_zone(id);


--
-- Name: i_zone fk_image_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.i_zone
    ADD CONSTRAINT fk_image_id FOREIGN KEY (image_id) REFERENCES ivin.image(id);


--
-- Name: template_point fk_image_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point
    ADD CONSTRAINT fk_image_id FOREIGN KEY (image_id) REFERENCES ivin.image(id);


--
-- Name: inspection_point fk_image_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_point
    ADD CONSTRAINT fk_image_id FOREIGN KEY (image_id) REFERENCES ivin.image(id);


--
-- Name: inspection_zone fk_inspection_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_zone
    ADD CONSTRAINT fk_inspection_id FOREIGN KEY (inspection_id) REFERENCES ivin.inspection(id);


--
-- Name: inspection_point fk_inspection_zone_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_point
    ADD CONSTRAINT fk_inspection_zone_id FOREIGN KEY (inspection_zone_id) REFERENCES ivin.inspection_zone(id);


--
-- Name: template_zone fk_template_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_zone
    ADD CONSTRAINT fk_template_id FOREIGN KEY (template_id) REFERENCES ivin.template(id);


--
-- Name: inspection fk_template_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection
    ADD CONSTRAINT fk_template_id FOREIGN KEY (template_id) REFERENCES ivin.template(id);


--
-- Name: template_point_validation_type fk_template_point_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation_type
    ADD CONSTRAINT fk_template_point_id FOREIGN KEY (template_point_id) REFERENCES ivin.template_point(id);


--
-- Name: inspection_point fk_template_point_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_point
    ADD CONSTRAINT fk_template_point_id FOREIGN KEY (template_point_id) REFERENCES ivin.template_point(id);


--
-- Name: inspection_point fk_template_point_validation_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.inspection_point
    ADD CONSTRAINT fk_template_point_validation_id FOREIGN KEY (template_point_validation_id) REFERENCES ivin.template_point_validation(id);


--
-- Name: template_point_validation fk_template_point_validation_type_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation
    ADD CONSTRAINT fk_template_point_validation_type_id FOREIGN KEY (template_point_validation_type_id) REFERENCES ivin.template_point_validation_type(id);


--
-- Name: template_point fk_template_zone_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point
    ADD CONSTRAINT fk_template_zone_id FOREIGN KEY (template_zone_id) REFERENCES ivin.template_zone(id);


--
-- Name: template_point_validation_type fk_validation_type_id; Type: FK CONSTRAINT; Schema: ivin; Owner: edulog
--

ALTER TABLE ONLY ivin.template_point_validation_type
    ADD CONSTRAINT fk_validation_type_id FOREIGN KEY (validation_type_id) REFERENCES ivin.validation_type(id);


--
-- Name: cal_cal_event cal_cal_event_cal_event_id_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal_cal_event
    ADD CONSTRAINT cal_cal_event_cal_event_id_fk FOREIGN KEY (cal_event_id) REFERENCES rp_master.cal_event(id);


--
-- Name: cal_cal_event cal_cal_event_cal_id_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.cal_cal_event
    ADD CONSTRAINT cal_cal_event_cal_id_fk FOREIGN KEY (cal_id) REFERENCES rp_master.cal(id);


--
-- Name: access_domain fk_access_domain_access; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access_domain
    ADD CONSTRAINT fk_access_domain_access FOREIGN KEY (access_id) REFERENCES rp_master.access(id);


--
-- Name: access_school fk_access_school_access; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.access_school
    ADD CONSTRAINT fk_access_school_access FOREIGN KEY (access_id) REFERENCES rp_master.access(id);


--
-- Name: avl_event fk_avl_event_avl_template_id; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.avl_event
    ADD CONSTRAINT fk_avl_event_avl_template_id FOREIGN KEY (avl_template_id) REFERENCES rp_master.avl_template(id);


--
-- Name: plan_rollover_log_items plan_rollover_log_items_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.plan_rollover_log_items
    ADD CONSTRAINT plan_rollover_log_items_fk FOREIGN KEY (plan_rollover_id) REFERENCES rp_master.plan_rollover(id);


--
-- Name: user_profile_template user_profile_template_access; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template
    ADD CONSTRAINT user_profile_template_access FOREIGN KEY (access_id) REFERENCES rp_master.access(id);


--
-- Name: user_profile_template user_profile_template_domain_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template
    ADD CONSTRAINT user_profile_template_domain_fk FOREIGN KEY (domain_id) REFERENCES rp_plan.domain(id);


--
-- Name: user_profile user_profile_template_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile
    ADD CONSTRAINT user_profile_template_fk FOREIGN KEY (user_profile_template_id) REFERENCES rp_master.user_profile_template(id);


--
-- Name: user_profile_template user_profile_template_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile_template
    ADD CONSTRAINT user_profile_template_fk FOREIGN KEY (role_permissions_id) REFERENCES rp_master.role_permissions(id);


--
-- Name: user_profile user_profile_user_fk; Type: FK CONSTRAINT; Schema: rp_master; Owner: edulog
--

ALTER TABLE ONLY rp_master.user_profile
    ADD CONSTRAINT user_profile_user_fk FOREIGN KEY (user_id) REFERENCES rp_master."user"(id);


--
-- Name: student_import_line athena_id_studimp_fk; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_import_line
    ADD CONSTRAINT athena_id_studimp_fk FOREIGN KEY (athena_id) REFERENCES rp_plan.student(id) ON DELETE CASCADE;


--
-- Name: belltime fk_belltime_school_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.belltime
    ADD CONSTRAINT fk_belltime_school_id FOREIGN KEY (school_id) REFERENCES rp_plan.school(id);


--
-- Name: cluster_belltime fk_cluster_belltime_belltime_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster_belltime
    ADD CONSTRAINT fk_cluster_belltime_belltime_id FOREIGN KEY (belltime_id) REFERENCES rp_plan.belltime(id);


--
-- Name: cluster_belltime fk_cluster_belltime_cluster_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.cluster_belltime
    ADD CONSTRAINT fk_cluster_belltime_cluster_id FOREIGN KEY (cluster_id) REFERENCES rp_plan.cluster(id);


--
-- Name: direction_step fk_direction_step_path_cover_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.direction_step
    ADD CONSTRAINT fk_direction_step_path_cover_id FOREIGN KEY (path_cover_id) REFERENCES rp_plan.path_cover(id);


--
-- Name: direction_step fk_direction_step_waypoint_cover_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.direction_step
    ADD CONSTRAINT fk_direction_step_waypoint_cover_id FOREIGN KEY (waypoint_cover_id) REFERENCES rp_plan.waypoint_cover(id);


--
-- Name: student fk_district_eligibility_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT fk_district_eligibility_id FOREIGN KEY (district_eligibility_id) REFERENCES rp_plan.district_eligibility(id);


--
-- Name: hazard_zone fk_hazard_zone_location_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.hazard_zone
    ADD CONSTRAINT fk_hazard_zone_location_id FOREIGN KEY (location_id) REFERENCES rp_plan.location(id);


--
-- Name: head_count fk_head_count_belltime_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.head_count
    ADD CONSTRAINT fk_head_count_belltime_id FOREIGN KEY (belltime_id) REFERENCES rp_plan.belltime(id);


--
-- Name: head_count fk_head_count_school_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.head_count
    ADD CONSTRAINT fk_head_count_school_id FOREIGN KEY (school_id) REFERENCES rp_plan.school(id);


--
-- Name: head_count fk_head_count_stop_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.head_count
    ADD CONSTRAINT fk_head_count_stop_id FOREIGN KEY (stop_id) REFERENCES rp_plan.stop(id);


--
-- Name: head_count fk_head_count_waypoint_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.head_count
    ADD CONSTRAINT fk_head_count_waypoint_master_id FOREIGN KEY (waypoint_master_id) REFERENCES rp_plan.waypoint_master(id);


--
-- Name: inactive_student fk_inactive_student_location_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.inactive_student
    ADD CONSTRAINT fk_inactive_student_location_id FOREIGN KEY (location_id) REFERENCES rp_plan.location(id);


--
-- Name: medical_note fk_medical_note_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.medical_note
    ADD CONSTRAINT fk_medical_note_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: path_cover fk_path_cover_path_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.path_cover
    ADD CONSTRAINT fk_path_cover_path_master_id FOREIGN KEY (path_master_id) REFERENCES rp_plan.path_master(id);


--
-- Name: route_contact fk_route_contact_contact_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_contact
    ADD CONSTRAINT fk_route_contact_contact_id FOREIGN KEY (contact_id) REFERENCES rp_plan.contact(id);


--
-- Name: route_contact fk_route_contact_route_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_contact
    ADD CONSTRAINT fk_route_contact_route_id FOREIGN KEY (route_id) REFERENCES rp_plan.route(id);


--
-- Name: route fk_route_contractor_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route
    ADD CONSTRAINT fk_route_contractor_id FOREIGN KEY (contractor_id) REFERENCES rp_plan.contractor(id);


--
-- Name: route fk_route_path_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route
    ADD CONSTRAINT fk_route_path_master_id FOREIGN KEY (path_master_id) REFERENCES rp_plan.path_master(id);


--
-- Name: route_run fk_route_run_route_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_run
    ADD CONSTRAINT fk_route_run_route_id FOREIGN KEY (route_id) REFERENCES rp_plan.route(id);


--
-- Name: route_run fk_route_run_run_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route_run
    ADD CONSTRAINT fk_route_run_run_id FOREIGN KEY (run_id) REFERENCES rp_plan.run(id);


--
-- Name: route fk_route_vehicle_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.route
    ADD CONSTRAINT fk_route_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES rp_plan.vehicle(id);


--
-- Name: school_contact fk_school_contact_contact_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_contact
    ADD CONSTRAINT fk_school_contact_contact_id FOREIGN KEY (contact_id) REFERENCES rp_plan.contact(id);


--
-- Name: school_contact fk_school_contact_school_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_contact
    ADD CONSTRAINT fk_school_contact_school_id FOREIGN KEY (school_id) REFERENCES rp_plan.school(id);


--
-- Name: school_location fk_school_location_location_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_location
    ADD CONSTRAINT fk_school_location_location_id FOREIGN KEY (location_id) REFERENCES rp_plan.location(id);


--
-- Name: school_location fk_school_location_school_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_location
    ADD CONSTRAINT fk_school_location_school_id FOREIGN KEY (school_id) REFERENCES rp_plan.school(id);


--
-- Name: school_operation_cover fk_school_operation_belltime_id_arrival; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_cover
    ADD CONSTRAINT fk_school_operation_belltime_id_arrival FOREIGN KEY (belltime_id_arrival) REFERENCES rp_plan.belltime(id);


--
-- Name: school_operation_cover fk_school_operation_belltime_id_depart; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_cover
    ADD CONSTRAINT fk_school_operation_belltime_id_depart FOREIGN KEY (belltime_id_depart) REFERENCES rp_plan.belltime(id);


--
-- Name: school_operation_cover fk_school_operation_cover_school_operation_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_cover
    ADD CONSTRAINT fk_school_operation_cover_school_operation_master_id FOREIGN KEY (school_operation_master_id) REFERENCES rp_plan.school_operation_master(id);


--
-- Name: school_operation_master_boundary fk_school_operation_master_boundary_school_operation_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master_boundary
    ADD CONSTRAINT fk_school_operation_master_boundary_school_operation_master_id FOREIGN KEY (school_operation_master_id) REFERENCES rp_plan.school_operation_master(id);


--
-- Name: school_operation_master fk_school_operation_master_grade_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master
    ADD CONSTRAINT fk_school_operation_master_grade_id FOREIGN KEY (grade_id) REFERENCES rp_plan.grade(id);


--
-- Name: school_operation_master fk_school_operation_master_program_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master
    ADD CONSTRAINT fk_school_operation_master_program_id FOREIGN KEY (program_id) REFERENCES rp_plan.program(id);


--
-- Name: school_operation_master fk_school_operation_master_school_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_operation_master
    ADD CONSTRAINT fk_school_operation_master_school_id FOREIGN KEY (school_id) REFERENCES rp_plan.school(id);


--
-- Name: school fk_school_school_district_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school
    ADD CONSTRAINT fk_school_school_district_id FOREIGN KEY (school_district_id) REFERENCES rp_plan.school_district(id);


--
-- Name: site_school_data fk_school_user_school_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_school_data
    ADD CONSTRAINT fk_school_user_school_id FOREIGN KEY (school_id) REFERENCES rp_plan.school(id);


--
-- Name: site_route_data fk_site_route_data_route_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_route_data
    ADD CONSTRAINT fk_site_route_data_route_id FOREIGN KEY (route_id) REFERENCES rp_plan.route(id);


--
-- Name: site_run_data fk_site_run_data_run_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_run_data
    ADD CONSTRAINT fk_site_run_data_run_id FOREIGN KEY (run_id) REFERENCES rp_plan.run(id);


--
-- Name: site_student_data fk_site_student_data_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_student_data
    ADD CONSTRAINT fk_site_student_data_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: site_trip_data fk_site_trip_data_trip_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_trip_data
    ADD CONSTRAINT fk_site_trip_data_trip_master_id FOREIGN KEY (trip_master_id) REFERENCES rp_plan.trip_master(id);


--
-- Name: stop fk_stop_location_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.stop
    ADD CONSTRAINT fk_stop_location_id FOREIGN KEY (location_id) REFERENCES rp_plan.location(id);


--
-- Name: site_stop_data fk_stop_user_stop_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.site_stop_data
    ADD CONSTRAINT fk_stop_user_stop_id FOREIGN KEY (stop_id) REFERENCES rp_plan.stop(id);


--
-- Name: student_contact fk_student_contact_contact_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_contact
    ADD CONSTRAINT fk_student_contact_contact_id FOREIGN KEY (contact_id) REFERENCES rp_plan.contact(id);


--
-- Name: student_contact fk_student_contact_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_contact
    ADD CONSTRAINT fk_student_contact_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: student fk_student_location_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT fk_student_location_id FOREIGN KEY (location_id) REFERENCES rp_plan.location(id);


--
-- Name: student_need fk_student_need_need_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_need
    ADD CONSTRAINT fk_student_need_need_id FOREIGN KEY (need_id) REFERENCES rp_plan.need(id);


--
-- Name: student_need fk_student_need_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_need
    ADD CONSTRAINT fk_student_need_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: student_note fk_student_note_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_note
    ADD CONSTRAINT fk_student_note_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: student fk_student_school_operation_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student
    ADD CONSTRAINT fk_student_school_operation_master_id FOREIGN KEY (school_operation_master_id) REFERENCES rp_plan.school_operation_master(id);


--
-- Name: student_transport_need fk_student_transport_need_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_transport_need
    ADD CONSTRAINT fk_student_transport_need_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: student_transport_need fk_student_transport_need_transport_need_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.student_transport_need
    ADD CONSTRAINT fk_student_transport_need_transport_need_id FOREIGN KEY (transport_need_id) REFERENCES rp_plan.transport_need(id);


--
-- Name: transport_def_cover fk_transport_def_cover_belltime_id_destination; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_cover
    ADD CONSTRAINT fk_transport_def_cover_belltime_id_destination FOREIGN KEY (belltime_id_destination) REFERENCES rp_plan.belltime(id);


--
-- Name: transport_def_cover fk_transport_def_cover_belltime_id_origin; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_cover
    ADD CONSTRAINT fk_transport_def_cover_belltime_id_origin FOREIGN KEY (belltime_id_origin) REFERENCES rp_plan.belltime(id);


--
-- Name: transport_def_cover fk_transport_def_cover_transport_def_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_cover
    ADD CONSTRAINT fk_transport_def_cover_transport_def_master_id FOREIGN KEY (transport_def_master_id) REFERENCES rp_plan.transport_def_master(id);


--
-- Name: transport_def_master fk_transport_def_master_location_id_destination; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master
    ADD CONSTRAINT fk_transport_def_master_location_id_destination FOREIGN KEY (location_id_destination) REFERENCES rp_plan.location(id);


--
-- Name: transport_def_master fk_transport_def_master_location_id_origin; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master
    ADD CONSTRAINT fk_transport_def_master_location_id_origin FOREIGN KEY (location_id_origin) REFERENCES rp_plan.location(id);


--
-- Name: transport_def_master fk_transport_def_master_school_id_destination; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master
    ADD CONSTRAINT fk_transport_def_master_school_id_destination FOREIGN KEY (school_id_destination) REFERENCES rp_plan.school(id);


--
-- Name: transport_def_master fk_transport_def_master_school_id_origin; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_def_master
    ADD CONSTRAINT fk_transport_def_master_school_id_origin FOREIGN KEY (school_id_origin) REFERENCES rp_plan.school(id);


--
-- Name: transport_itinerary fk_transport_itinerary_transport_request_detail_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_itinerary
    ADD CONSTRAINT fk_transport_itinerary_transport_request_detail_id FOREIGN KEY (transport_request_detail_id) REFERENCES rp_plan.transport_request_detail(id);


--
-- Name: transport_request_detail fk_transport_request_detail_transport_request_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request_detail
    ADD CONSTRAINT fk_transport_request_detail_transport_request_id FOREIGN KEY (transport_request_id) REFERENCES rp_plan.transport_request(id);


--
-- Name: transport_request fk_transport_request_location_id_requested_stop; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request
    ADD CONSTRAINT fk_transport_request_location_id_requested_stop FOREIGN KEY (location_id_requested_stop) REFERENCES rp_plan.location(id);


--
-- Name: transport_request fk_transport_request_student_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request
    ADD CONSTRAINT fk_transport_request_student_id FOREIGN KEY (student_id) REFERENCES rp_plan.student(id);


--
-- Name: transport_request fk_transport_request_transport_def_master_id_from_school; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request
    ADD CONSTRAINT fk_transport_request_transport_def_master_id_from_school FOREIGN KEY (transport_def_master_id_from_school) REFERENCES rp_plan.transport_def_master(id);


--
-- Name: transport_request fk_transport_request_transport_def_master_id_to_school; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.transport_request
    ADD CONSTRAINT fk_transport_request_transport_def_master_id_to_school FOREIGN KEY (transport_def_master_id_to_school) REFERENCES rp_plan.transport_def_master(id);


--
-- Name: trip_cover fk_trip_cover_transport_def_cover_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_cover
    ADD CONSTRAINT fk_trip_cover_transport_def_cover_id FOREIGN KEY (transport_def_cover_id) REFERENCES rp_plan.transport_def_cover(id);


--
-- Name: trip_leg fk_trip_leg_trip_cover_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg
    ADD CONSTRAINT fk_trip_leg_trip_cover_id FOREIGN KEY (trip_cover_id) REFERENCES rp_plan.trip_cover(id);


--
-- Name: trip_leg_waypoint_master fk_trip_leg_waypoint_master_trip_leg_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master
    ADD CONSTRAINT fk_trip_leg_waypoint_master_trip_leg_id FOREIGN KEY (trip_leg_id) REFERENCES rp_plan.trip_leg(id);


--
-- Name: trip_leg_waypoint_master fk_trip_leg_waypoint_master_waypoint_master_id_destination; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master
    ADD CONSTRAINT fk_trip_leg_waypoint_master_waypoint_master_id_destination FOREIGN KEY (waypoint_master_id_destination) REFERENCES rp_plan.waypoint_master(id);


--
-- Name: trip_leg_waypoint_master fk_trip_leg_waypoint_master_waypoint_master_id_origin; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_leg_waypoint_master
    ADD CONSTRAINT fk_trip_leg_waypoint_master_waypoint_master_id_origin FOREIGN KEY (waypoint_master_id_origin) REFERENCES rp_plan.waypoint_master(id);


--
-- Name: trip_master fk_trip_master_transport_def_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.trip_master
    ADD CONSTRAINT fk_trip_master_transport_def_master_id FOREIGN KEY (transport_def_master_id) REFERENCES rp_plan.transport_def_master(id);


--
-- Name: vehicle fk_vehicle_contractor_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle
    ADD CONSTRAINT fk_vehicle_contractor_id FOREIGN KEY (contractor_id) REFERENCES rp_plan.contractor(id);


--
-- Name: vehicle fk_vehicle_gps_unit_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle
    ADD CONSTRAINT fk_vehicle_gps_unit_id FOREIGN KEY (gps_unit_id) REFERENCES rp_plan.gps_unit(id);


--
-- Name: vehicle_maintenance fk_vehicle_maintenance_vehicle_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_maintenance
    ADD CONSTRAINT fk_vehicle_maintenance_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES rp_plan.vehicle(id);


--
-- Name: vehicle_transport_need fk_vehicle_transport_need_transport_need_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_transport_need
    ADD CONSTRAINT fk_vehicle_transport_need_transport_need_id FOREIGN KEY (transport_need_id) REFERENCES rp_plan.transport_need(id);


--
-- Name: vehicle_transport_need fk_vehicle_transport_need_vehicle_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.vehicle_transport_need
    ADD CONSTRAINT fk_vehicle_transport_need_vehicle_id FOREIGN KEY (vehicle_id) REFERENCES rp_plan.vehicle(id);


--
-- Name: waypoint_cover_belltime fk_waypoint_cover_belltime_belltime_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover_belltime
    ADD CONSTRAINT fk_waypoint_cover_belltime_belltime_id FOREIGN KEY (belltime_id) REFERENCES rp_plan.belltime(id);


--
-- Name: waypoint_cover_belltime fk_waypoint_cover_belltime_waypoint_cover_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover_belltime
    ADD CONSTRAINT fk_waypoint_cover_belltime_waypoint_cover_id FOREIGN KEY (waypoint_cover_id) REFERENCES rp_plan.waypoint_cover(id);


--
-- Name: waypoint_cover fk_waypoint_cover_path_cover_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover
    ADD CONSTRAINT fk_waypoint_cover_path_cover_id FOREIGN KEY (path_cover_id) REFERENCES rp_plan.path_cover(id);


--
-- Name: waypoint_cover fk_waypoint_cover_waypoint_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_cover
    ADD CONSTRAINT fk_waypoint_cover_waypoint_master_id FOREIGN KEY (waypoint_master_id) REFERENCES rp_plan.waypoint_master(id);


--
-- Name: waypoint_master fk_waypoint_master_location_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_master
    ADD CONSTRAINT fk_waypoint_master_location_id FOREIGN KEY (location_id) REFERENCES rp_plan.location(id);


--
-- Name: waypoint_master fk_waypoint_master_path_master_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_master
    ADD CONSTRAINT fk_waypoint_master_path_master_id FOREIGN KEY (path_master_id) REFERENCES rp_plan.path_master(id);


--
-- Name: waypoint_master fk_waypoint_master_route_run_id; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.waypoint_master
    ADD CONSTRAINT fk_waypoint_master_route_run_id FOREIGN KEY (route_run_id) REFERENCES rp_plan.route_run(id);


--
-- Name: school school_cal_id_fk; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school
    ADD CONSTRAINT school_cal_id_fk FOREIGN KEY (cal_id) REFERENCES rp_master.cal(id);


--
-- Name: school_district school_district_cal_id_fk; Type: FK CONSTRAINT; Schema: rp_plan; Owner: edulog
--

ALTER TABLE ONLY rp_plan.school_district
    ADD CONSTRAINT school_district_cal_id_fk FOREIGN KEY (cal_id) REFERENCES rp_master.cal(id);


--
-- PostgreSQL database dump complete
--

