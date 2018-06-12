
# Setup
* in docker-compose.yml:
* * update `PAGERDUTY_API_KEY` (values in 1password)
* * update `DATABASE_URL` to `postgres://postgres:ffs@db:5432/pagerduty` where `db` = the hostname of the postgres server

# Running
* docker-compose build
* docker-compose up
