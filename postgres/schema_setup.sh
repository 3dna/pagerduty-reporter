## psql required to get this going. its easier to go to hostname:8080 and use the web interface to get the sql in if you dont have psql installed locally IMO

#!/bin/bash
psql -d pagerduty -U postgres -f schemas.sql
