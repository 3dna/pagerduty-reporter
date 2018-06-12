#pagerduty-reporter

* Postgres container
* pd2pg modified to work with v2 of the pagerduty api
* Reporter

Credentials are all stored in 1password, under syseng


# Postgres container
docker-compose up -d

It's nothing fancy.  You just spin it up with the credentials, import the sql in the folder and run it using docker-compose up -d.  You can get to the web portal interface at servername:8080

# pd2pg
docker-compose up 

pd2pg imports data from the PagerDuty API into a Postgres database for
easy querying and analysis.

It's forked from stripe- they were not maintaining it publically all too well.

This needs to be run on some regular interval to update the db.

# Reporter (pg2things)

Just some code which uses sequal to do some raw sql queries (it's what @awesinine is most familiar with).  It's not completed and the reports are going to be dialed-in over time.  The PD data we have is really bad so some additional structure is being put into place to make the reporting useful / accurate (https://trello.com/c/MLewDbfJ/2576-poorly-reportable-incident-information-needs-to-be-made-clearly-reportable)

The basic gist is that there should be some common reports which get spit out to csv / slack / datadog.  currently this is only spitting out to slack.
