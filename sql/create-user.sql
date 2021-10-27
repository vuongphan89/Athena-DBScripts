WITH uID As (INSERT INTO rp_master."user" (person_id, first_name, middle_name, last_name, active, email, department, "position", user_id_manager, password_changed_at, user_id,  time_changed)
        VALUES (uuid_in(md5(random()::text || clock_timestamp()::text)::cstring), 'First1', '', 'Name1', true, 'firstname1@karrostech.com', 'Administration', 'Principal', NULL, now(), 'SYSTEM', now())		
	RETURNING rp_master."user".id)
INSERT INTO rp_master.user_profile ( user_id, user_profile_template_id, active, user_id_changed, time_changed)VALUES ((select id from uID) , 1, true, 'SYSTEM', now());