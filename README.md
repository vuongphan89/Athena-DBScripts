# Athena DB Scripts

SQL and Bash Scripts for init Athena Databases of new Athena Environment

## Usage

Access into a server that can run bash script, psql script and can connect into Athena PostgreSQL Database (AWS RDS if we use Athena IaC).
Make sure you have correct previlige in this GitHub Repo for cloning it in the server.

Download Script `./init-data.sh`

Run Script with the appropriate parameters. Ex: `./init-data.sh db_host postgres_user_password`


## How it works

These are the main steps of the script for create initialization schema & data for Athena Project:
- Stop all Running Backend Services to free the connection on Database.
- Create a clean "Athena" Database with postgis extension.
- Clone the Athena-DBScripts Repo
- Execute sql script to init data for Athena
    + `athena.base.sql`: add base schema for Athena
    + `geocode_settings.sql`: add geocode settings
    + `nit_ivin_geo_defaults.sql`: add ivin defaults
    + `authen.clean.sql`: clean authentication related tables.
    + `authen.base.sql`: add base data & DB Schema for authentication
    + `super_admin.user.sql`: create default super-admin user which created in Karros MissionControl.

- Update owner for Athena Schema: we need to update the owner to `edulog` - the db user used by Backend Services - on all Athena DB for Backend Services connect to DB.
- Start all Backend Services for using new fresh schema of Athena DB.

