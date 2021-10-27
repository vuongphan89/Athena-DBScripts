---------------------------------------------------------
--- Script check validation Athena's data after setup ---
---------------------------------------------------------

--- Check General Database Information ---
select 'public' as schema, 'flyway_schema_history' as table, 'Database version must be latest and the same with routing deployment' as Check_Description, (select version from public.flyway_schema_history fsh order by installed_rank desc limit 1) as result
union all

--- Check Geocode Service's Requirement Data --  
select 'geo_master', 'config', 'Center Latitude must not be blank', (select value from geo_master.config c where c.setting = 'CENTER_LAT')
union  all
select 'geo_master', 'config', 'Center Longitude must not be blank', (select value from geo_master.config c where c.setting = 'CENTER_LNG')
union  all
select 'geo_master', 'config', 'Edit zoom must not be blank', (select value from geo_master.config c where c.setting = 'EDIT_ZOOM')
union  all
select 'geo_master', 'config', 'Init zoom must not be blank', (select value from geo_master.config c where c.setting = 'INIT_ZOOM')
union  all
select 'geo_master', 'config', 'Threshold distance must not be blank', (select value from geo_master.config c where c.setting = 'THRESHOLD_DISTANCE')
union  all
select 'geo_master', 'config', 'S3 Bucket must not be blank', (select value from geo_master.config c where c.setting = 'S3_BUCKET')
union  all
select 'geo_plan', 'boundary_group', '1 - ATTENDANCE system code must not be existed', (select c.id || ' - ' || c.code from geo_plan.boundary_group c where c.code = 'ATTENDANCE' and c.id = 1)
union  all
select 'geo_plan', 'boundary_group', '2 - WALK system code must not be existed', (select c.id || ' - ' || c.code from geo_plan.boundary_group c where c.code = 'WALK' and c.id = 2)
union  all
select 'geo_plan', 'boundary_group', '3 - HAZARD system code must not be existed', (select c.id || ' - ' || c.code from geo_plan.boundary_group c where c.code = 'HAZARD' and c.id = 3)
union  all
select 'geo_plan', 'boundary_group', '4 - PREMISE system code must not be existed', (select c.id || ' - ' || c.code from geo_plan.boundary_group c where c.code = 'PREMISE' and c.id = 4)
union  all
select 'geo_plan', 'boundary_group', '5 - PARKING system code must not be existed', (select c.id || ' - ' || c.code from geo_plan.boundary_group c where c.code = 'PARKING' and c.id = 5)
union  all
select 'geo_plan', 'boundary_group', '[6,99] - <<booked>> - 94 system code must be booked for next system code', (select '[6,99] - <<booked>> - ' || count(c.id)  from geo_plan.boundary_group c where c.description = 'Input description' and c.id between 6 and 99 group by c.description having count(id) = 94)


--- Check EDTA Service's Requirement Data --  
union  all
select 'edta', 'activity', 'Total records should be greater than 0', (select count(id)::text from edta.activity a)
union  all
select 'edta', 'billing_type', 'Total records should be greater than 0', (select count(id)::text from edta.billing_type a)
union  all
select 'edta', 'department', 'Total records should be greater than 0', (select count(id)::text from edta.department a)
union  all
select 'edta', 'district', 'Total records should be greater than 0', (select count(id)::text from edta.district a)
union  all
select 'edta', 'driver_class', 'Total records should be greater than 0', (select count(id)::text from edta.driver_class a)
union  all
select 'edta', 'emp_class', 'Total records should be greater than 0', (select count(id)::text from edta.emp_class a)
union  all
select 'edta', 'emp_group', 'Total records should be greater than 0', (select count(id)::text from edta.emp_group a)
union  all
select 'edta', 'grade', 'Total records should be greater than 0', (select count(id)::text from edta.grade a)
union  all
select 'edta', 'level', 'Total records should be greater than 0', (select count(id)::text from edta."level" a)
union  all
select 'edta', 'license_class', 'Total records should be greater than 0', (select count(id)::text from edta.license_class a)
union  all
select 'edta', 'scale_hour', 'Total records should be greater than 0', (select count(id)::text from edta.scale_hour a)
union  all
select 'edta', 'skill', 'Total records should be greater than 0', (select count(id)::text from edta.skill a)
union  all
select 'edta', 'state', 'Total records must be greater than 0', (select count(distinct code)::text from edta.state a)
union  all
select 'edta', 'union', 'Total records should be greater than 0', (select count(id)::text from edta."union" a)
union  all
select 'edta', 'work_group', 'Total records should be greater than 0', (select count(id)::text from edta.work_group a)
union  all
select 'edta', 'v_current_trecord', 'View must be existed', exists(select 1 from information_schema."views" v where table_schema = 'edta' and table_name = 'v_current_trecord')::text
union  all
select 'edta', 'v_current_trecord_for_driver', 'View must be existed', exists(select 1 from information_schema."views" v where table_schema = 'edta' and table_name = 'v_current_trecord_for_driver')::text
union  all
select 'edta', 'v_daily_summary_on_current_trecord', 'View must be existed', exists(select 1 from information_schema."views" v where table_schema = 'edta' and table_name = 'v_daily_summary_on_current_trecord')::text
union  all
select 'edta', 'v_daily_total_on_daily_summary', 'View must be existed', exists(select 1 from information_schema."views" v where table_schema = 'edta' and table_name = 'v_daily_total_on_daily_summary')::text
union  all
select 'edta', 'v_pay_period_on_daily_total', 'View must be existed', exists(select 1 from information_schema."views" v where table_schema = 'edta' and table_name = 'v_pay_period_on_daily_total')::text
union  all
select 'edta', 'v_transaction', 'View must be existed', exists(select 1 from information_schema."views" v where table_schema = 'edta' and table_name = 'v_transaction')::text

--- Check IVIN Service's Requirement Data --  
union  all
select 'ivin', 'i_type', '1 - Pre-Trip must be existed', (select id || ' - ' || name_of from ivin.i_type a where name_of = 'Pre-Trip' and id = 1)
union  all
select 'ivin', 'i_type', '2 - Post-Trip must be existed', (select id || ' - ' || name_of from ivin.i_type a where name_of = 'Post-Trip' and id = 2)
union  all
select 'ivin', 'i_type', '3 - Maintenance must be existed', (select id || ' - ' || name_of from ivin.i_type a where name_of = 'Maintenance' and id = 3)

union  all
select 'ivin', 'i_zone', '1 - Front Lights Mirrors Signals - 1 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Front Lights Mirrors Signals' and id = 1 and image_id = 1)
union  all
select 'ivin', 'i_zone', '2 - Front Open Hood - 2 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Front Open Hood' and id = 2 and image_id = 2)
union  all
select 'ivin', 'i_zone', '3 - Front Windows - 3 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Front Windows' and id = 3 and image_id = 3)
union  all
select 'ivin', 'i_zone', '4 - Left Side Doors Mirrors Signals - 4 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Left Side Doors Mirrors Signals' and id = 4 and image_id = 4)
union  all
select 'ivin', 'i_zone', '5 - Left Side Stop Arm Panel - 5 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Left Side Stop Arm Panel' and id = 5 and image_id = 5)
union  all
select 'ivin', 'i_zone', '6 - Left Side Wheels and Tires - 6 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Left Side Wheels and Tires' and id = 6 and image_id = 6)
union  all
select 'ivin', 'i_zone', '7 - Right Side Doors Mirrors Signals - 7 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Right Side Doors Mirrors Signals' and id = 7 and image_id = 7)
union  all
select 'ivin', 'i_zone', '8 - Right Side Wheels and Tires - 8 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Right Side Wheels and Tires' and id = 8 and image_id = 8)
union  all
select 'ivin', 'i_zone', '9 - Right Side Windows - 9 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Right Side Windows' and id = 9 and image_id = 9)
union  all
select 'ivin', 'i_zone', '10 - Rear Emergency Door - 10 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Rear Emergency Door' and id = 10 and image_id = 10)
union  all
select 'ivin', 'i_zone', '11 - Rear Exhaust - 11 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Rear Exhaust' and id = 11 and image_id = 11)
union  all
select 'ivin', 'i_zone', '12 - Rear Lights Mirrors Signals - 12 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Rear Lights Mirrors Signals' and id = 12 and image_id = 12)
union  all
select 'ivin', 'i_zone', '13 - Interior1 - 13 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Interior1' and id = 13 and image_id = 13)
union  all
select 'ivin', 'i_zone', '14 - Interior2 - 14 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Interior2' and id = 14 and image_id = 14)
union  all
select 'ivin', 'i_zone', '15 - Interior3 - 15 must be existed', (select id || ' - ' || description || ' - ' || image_id from ivin.i_zone a where description = 'Interior3' and id = 15 and image_id = 15)
union  all
select 'ivin', 'validation_type', '1 - Green must be existed', (select id || ' - ' || description from ivin.validation_type a where description = 'Green' and id = 1)
union  all
select 'ivin', 'validation_type', '2 - Yellow must be existed', (select id || ' - ' || description from ivin.validation_type a where description = 'Yellow' and id = 2)
union  all
select 'ivin', 'validation_type', '3 - Red must be existed', (select id || ' - ' || description from ivin.validation_type a where description = 'Red' and id = 3)
