#!/bin/bash
psql -d pagerduty -U postgres -f schemas.sql
