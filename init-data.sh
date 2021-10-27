#!/bin/bash -xe

# VARIABLES #
db_host=$1
pg_password=$2
pg_master_user="postgres"
user="edulog"
db_name="Athena"
schema=""

# EXPORT ENVIRONMENT VARIABLES
export PGPASSWORD=$pg_password;

# EXECUTES #

#  CLEAN CURRENT DATABASE IF NEEDED
## STOP ALL RUNNING SERVICES
echo "=> Stop all Backend Services"
/usr/local/bin/stop-athena-services

## DROP DATABASE
echo "=> Drop current Database"
psql -U $pg_master_user -h $db_host -c "DROP DATABASE \"${db_name}\";"
## RECREATE DATABASE AND ADD EXTENSION
echo "=> Recreate Database"
psql -U $pg_master_user -h $db_host -c "CREATE DATABASE \"${db_name}\";" 
psql -U $pg_master_user -h $db_host -c "CREATE EXTENSION postgis;" $db_name

# LOAD INIT DATA 
## DOWNLOAD BASE SQL SCRIPTS
mkdir -p /tmp/base_db
cd /tmp/base_db
git clone git@github.com:eduloginc/Athena-DBScripts.git

## IMPORT DATA
cd sql
psql -U postgres -h $db_host -d "Athena" -f athena.base.sql
psql -U postgres -h $db_host -d "Athena" -f geocode_settings.sql
psql -U postgres -h $db_host -d "Athena" -f init_ivin_geo_defaults.sql
psql -U postgres -h $db_host -d "Athena" -f authen.clean.sql
psql -U postgres -h $db_host -d "Athena" -f authen.base.sql
psql -U postgres -h $db_host -d "Athena" -f super_admin.user.sql

## UPDATE OWNER FOR ATHENA SCHEMAS
# geo_plan | public | rp_master | rp_plan | settings
schema="geo_plan"
for table in `psql -U $pg_master_user -h $db_host -tc "select tablename from pg_tables where schemaname = '${schema}';" ${db_name}` ; do  psql -U $pg_master_user -h $db_host -c "alter table ${schema}.${table} owner to ${user}" ${db_name} ; done

schema="public"
for table in `psql -U $pg_master_user -h $db_host -tc "select tablename from pg_tables where schemaname = '${schema}';" ${db_name}` ; do  psql -U $pg_master_user -h $db_host -c "alter table ${schema}.${table} owner to ${user}" ${db_name} ; done

schema="rp_master"
for table in `psql -U $pg_master_user -h $db_host -tc "select tablename from pg_tables where schemaname = '${schema}';" ${db_name}` ; do  psql -U $pg_master_user -h $db_host -c "alter table ${schema}.${table} owner to ${user}" ${db_name} ; done

schema="rp_plan"
for table in `psql -U $pg_master_user -h $db_host -tc "select tablename from pg_tables where schemaname = '${schema}';" ${db_name}` ; do  psql -U $pg_master_user -h $db_host -c "alter table ${schema}.${table} owner to ${user}" ${db_name} ; done

schema="settings"
for table in `psql -U $pg_master_user -h $db_host -tc "select tablename from pg_tables where schemaname = '${schema}';" ${db_name}` ; do  psql -U $pg_master_user -h $db_host -c "alter table ${schema}.${table} owner to ${user}" ${db_name} ; done

# Update previleges for user in DB
psql -U postgres -h $db_host -d "Athena" -f permissions.base.sql

echo "=> Restart Athena Services"
/usr/local/bin/restart-athena-services