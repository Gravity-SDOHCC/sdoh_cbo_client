# Gravity SDOH CBO Client Reference Implementation

This is a reference implementation for the Communinity Base Organization (CBO) system as defined in the [Gravity SDOHCC Implementation Guide](https://build.fhir.org/ig/HL7/fhir-sdoh-clinicalcare/CapabilityStatement-SDOHCC-CoordinationPlatform.html#title)

This CBO RI behaves as  ‘Light’ referral recipient. It acts as client, querying for tasks on the initiating Referral Sources or Coordination Platforms and creating any resulting Procedure records within the server they received the request from.



## Prerequisites
- ruby 2.7.5
- postgresql
- memcache
- Node.js 14.0.0 or higher
- Yarn 1.22.0 or higher

## Built With
- Rails 7
- Bootstrap 5
- Stimulus
- ActionCable


## Running Locally
- start postgresql and memcache on your sysmtem. This is important as the app will not
run without.
- run `rake db:create` then `rake db:migrate` to create and migrate the database. This is only necessary for the first time.
- run `rails s` to start the app. The app will be availabe at http://localhost:3000

## Running with Docker
A `docker-compose.yml` is provided to build and run the app with PostgreSQL using Docker Compose.
This `docker-compose.yml`  file defines two services: `app` and `db`. The `app` ervice builds the application using the Dockerfile, exposes port 3000, and sets environment variables for the database connection. The `db` service uses the official PostgreSQL image and configures the user, password, and database name. Additionally, a named volume is used to persist PostgreSQL data.

To start the application, simply run `docker-compose up`. The app will be availabe at http://localhost:3000.

>> When editing the code, you might want to run `docker-compose build` first to rebuild the image, then run `docker-compose up`. If you are running into issues regarding assets not present in the asset pipeline, consider clearing your precompiled assets `rm -rf public/assets` and rebuilding the Docker image `docker-compose build`.

Press `control + c` or `ctrl + c` to stop the app.

## Using the App (Demo)
This CBO client is configured to work with the [Gravity CP FHIR server RI]() or [Gravity CP FHIR server](),
but can also integrate with other CP/EHR FHIR servers for testing.
