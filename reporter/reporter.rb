#!/usr/bin/env ruby

require "json"
require "excon"
require "time"
require "pg"
require "sequel"
require  "slack-ruby-client"

# Ensure all data processing is in UTC.
ENV["TZ"] = "UTC"

class PDREPORT

  # Reads required config from environment variables.
  def env!(k)
    v = ENV[k]
    if !v
      $stderr.puts("Must set #{k} in environment")
      Kernel.exit(1)
    end
    v
  end

  # Logs a key-prefixed, name=value line.
  def log(key, data={})
    data_str = data.map { |(k,v)| "#{k}=#{v}" }.join(" ")
    $stdout.puts("#{key}#{" " + data_str if data_str}")
  end

  # Connections to the Postgres DB
  attr_accessor :db
  # Connections to the Slack API
  attr_accessor :client

  # Initialize by reading config and establishing DB
  def initialize
    # Read config.
    database_url = env!("DATABASE_URL")

    Slack.configure do |config|
      config.token = 'xoxb-2171751220-375748927301-YQmfMTSyxkfLd6ejs2gj7xvn'
    end

    # Establish DB connection
    @db = Sequel.connect(database_url)

    #Establish Slack client
    self.client = Slack::Web::Client.new
  end

  def get_schedule_id_from_schedule_name(schedule_name)
    results = db.fetch "SELECT id from schedules where name = '#{schedule_name}';"
    results.map(:id)[0]
  end

  def get_user_ids_from_schedule_id(schedule_id)
    results = db.fetch "select user_id from user_schedule where schedule_id = '#{schedule_id}';"
    results.map(:user_id).to_a
  end

  def get_user_names_from_user_ids(user_ids)
    user_names = user_ids.map { |i| "'" + i.to_s + "'"}.join(',').strip
    results = db.fetch "select users.name, users.id from users where users.id in (#{user_names});"
    results.map(:name).to_a
  end

  def get_user_name_from_user_id(user_id)
    results = db.fetch "select users.name, users.id from users where users.id in ('#{user_id}');"
    results.map(:name).to_a[0]
  end

  def get_all_user_ids
    results = db.fetch "select users.name, users.id from users;"
    results.map
  end

  def get_all_historical_user_ids
    results = db.fetch "select DISTINCT(user_id) from log_entries;"
    results.map
  end

  def get_service_name_from_service_id(service_id)
    results = db.fetch "select service.name from service where service.id = 'service_id';"
    results.map(:name)[0]
  end

  def get_incident_from_incident_id(incident_id)
    query = "select incidents.id, incidents.html_url,incidents.incident_key, incidents.service_id from incidents where incidents.id = '#{incident_id}'"
    results = db.fetch "#{query}"
    results.map.to_a
  end

  def get_incidents_from_user_id(user_id, start_date=nil, end_date=nil, timezone)
    #log_entries are fucking this up later in the pipe because multiple time entries exist for each notify step per incident and user
    #this needs the timezone relooked at
    if end_date == nil
      end_date = "now()"
    end

    query =
    "select
          log_entries.incident_id,
          log_entries.user_id,
          log_entries.created_at at time zone '#{timezone}' as local_created_at
        from
          log_entries
        where
          log_entries.created_at > '#{start_date}' and  -- furthest from now()
          log_entries.created_at < '#{end_date}' and  -- closest to now()
          log_entries.type = 'notify_log_entry' and
          log_entries.user_id = '#{user_id}';"
      results = db.fetch "#{query}"
      results.map  ###
  end

  def get_unique_incidents_from_user_id(user_id)
    query =
    "select
          log_entries.incident_id
       from
          log_entries
        where
          log_entries.user_id = '#{user_id}';"
      results = db.fetch "#{query}"
      results.map(:incident_id).uniq
  end

  #could be implemented as a more complex query, but this is nice and simple
  def check_if_incident_is_between(incident_id, start_date, end_date)
    #p "#{start_date}"
    #p "#{end_date}"
    query = "select EXISTS (select incidents.id from incidents where incidents.id = '#{incident_id}' and incidents.created_at > '#{start_date}' and incidents.created_at < '#{end_date}')"
    #puts "#{query}"
    results = db.fetch "#{query}"
    huh = "#{results.map(:exists)[0]}"
    if huh.eql? "true"
      return true
    else
      return false
    end
    # if results.map(:exists) == "false"
    #    return false
    #  else
    #    return true
    #  end
  end

  def check_off_hours(incident_id)
    #need to add in every weekend as well

    query = "select incidents.created_at from incidents where incidents.id = '#{incident_id}'"
    results = db.fetch "#{query}"

    incident_time = DateTime.parse("#{results.map.to_a[0][:created_at]}").new_offset('-08:00')

    puts "incident_time: #{incident_time}"
    if (incident_time.hour < 8 or incident_time.hour > 18) || (incident_time.wday == 0 or incident_time.wday == 6)
      return true
    else
      return false
    end
  end

  def fatigue(user_id, start_date=nil, end_date, timezone, silent)
    detailed_incidents = []
    off_hours_count = 0
    text = "These were the incidents worked through: \n"
    name = get_user_name_from_user_id(user_id)

    if name == nil
      name = "(A Lost Hero)"
    end

    incidents = get_incidents_from_user_id(user_id, start_date, end_date, timezone)

    if incidents.count <= 0 || user_id == nil
      return
    end

    ### you gotta sit down and read how to utilize ruby maps better than this.  it seems wrong to build an array from a map in order to get unique elements
    ug_bad = []

    incidents.each{|stfu|
      ug_bad.push(stfu[:incident_id])
    }

    ug_bad.uniq.each{|incident|
      get_incident_from_incident_id("#{incident}").each{ | details |
          detailed_incidents.push(":boom:<#{details[:html_url]}|#{details[:incident_key]}>")
        }
    }

   ug_bad.uniq.each{|incident|
     if check_off_hours("#{incident}")
       off_hours_count += 1
     end
}
    title = "#{name} was alerted by #{detailed_incidents.uniq.count} unique incidents between #{start_date} and #{end_date}\n#{off_hours_count} Alerts were during off hours"
    csv = "#{name},#{detailed_incidents.uniq.count},#{start_date},#{end_date},#{off_hours_count}"
    detailed_incidents.uniq.each{ |incident|
      text += "#{incident}\n"
    }

    if silent
      puts "#{csv}"
      #puts "#{title}"
      #puts "#{text}"
    else
      #puts "#{text}"
      #send_slack('#sys-eng-notifications', "#{title}", "#{text}")
     end
   end

  def send_slack(channel, title, text)

    client.chat_postMessage(
      channel: "#{channel}",
      as_user: true,
      attachments: [
        {
          title: "#{title}",
          text: "#{text}",
          color: '#7CD197'
        }
      ]
    )

  end

  #returns time in seconds
  def calculate_TTR(incident_id)

    query = "select log_entries.created_at from log_entries where log_entries.incident_id = '#{incident_id}' and log_entries.type != 'annotate_log_entry';"
    results = db.fetch "#{query}"
    ttr = results.map(:created_at).max - results.map(:created_at).min
  end

  def shift_report(team, start_date, end_date, silent)
    #gets a list of unique incidents between dates and sorts them into two arrays

    log("reporting on #{team} between #{start_date} through #{end_date} ")
    schedule_id = get_schedule_id_from_schedule_name("#{team}")

    get_user_ids_from_schedule_id(schedule_id).each{|user_id|
      off_hours_page = []
      business_hours_page = []
      off_hours_resolve_time = 0
      business_hours_resolve_time = 0

      get_unique_incidents_from_user_id(user_id).each{|incident|
        if check_if_incident_is_between(incident, "#{start_date}", "#{end_date}")
          if check_off_hours(incident)
            off_hours_page.push(incident)
            off_hours_resolve_time += calculate_TTR(incident)
          else
            business_hours_page.push(incident)
            business_hours_resolve_time += calculate_TTR(incident)
          end
        end

      }

      name = get_user_name_from_user_id(user_id)
      total_pages = off_hours_page.count + business_hours_page.count
      title = "#{name} was alerted by #{total_pages} unique incidents between #{start_date} and #{end_date}\n#{off_hours_page.count} Alerts were during off hours\n"

      on_b_h = business_hours_resolve_time/60/60
      off_b_h = off_hours_resolve_time/60/60

      time_spent_in_incidents = (on_b_h + off_b_h).round(2)
      puts "#{title}"

      detailed_incidents = []
      text = ""

      off_hours_page.each{ |incident|
      get_incident_from_incident_id("#{incident}").each{ | details |
          detailed_incidents.push(":boom:<#{details[:html_url]}|#{details[:incident_key]}>")
      }
    }
      business_hours_page.each{|incident|
      get_incident_from_incident_id("#{incident}").each{ | details |
          detailed_incidents.push(":boom:<#{details[:html_url]}|#{details[:incident_key]}>")
      }
}
      detailed_incidents.each{ |incident|
        text += "#{incident}\n"
      }
      puts "#{text}"
      #send_slack('#sys-eng-notifications', "#{title}", "#{text}")
    }
  end

  def active_company_report(start_date, end_date)
    users = get_all_user_ids
    users.each{ |user|
       fatigue("#{user.to_a[1][1]}", "#{start_date}" , "#{end_date}", 'America/Los_Angeles')
     }
  end

  def historical_company_report(start_date, end_date)
    users = get_all_historical_user_ids
    users.each{ |user|
       fatigue("#{user.to_a[0][1]}", "#{start_date}" , "#{end_date}", 'America/Los_Angeles', true)
     }
  end
end

#just ballparking it
def monthly_report()
  for year in 2012..2018 do
    for month in 01..12 do
      PDREPORT.new.historical_company_report("#{year}-#{month}-01", "#{year}-#{month}-28")
    end
  end
end

#monthly_report

# PDREPORT.new.shift_report('Email Pause', '2018-06-04 12:00:00+00', '2018-06-06 12:00:00 PST', true)
# PDREPORT.new.shift_report('Incident Management - Primary', '2018-06-04 12:00:00+00', '2018-06-08 12:00:00+00', true)
# PDREPORT.new.shift_report('Incident Management - Secondary', '2018-06-04 12:00:00+00', '2018-06-06 12:00:00+00', true)
# PDREPORT.new.shift_report('Labour Election Schedule', '2018-06-04 12:00:00+00', '2018-06-08 12:00:00+00', true)
# PDREPORT.new.shift_report('NationBuilder Live Back-up', '2018-06-04 12:00:00+00', '2018-06-06 12:00:00+00', true)
# PDREPORT.new.shift_report('Panic', '2018-06-04 12:00:00+00', '2018-06-08 12:00:00+00', true)
# PDREPORT.new.shift_report('Panic Secondary', '2018-06-04 12:00:00+00', '2018-06-06 12:00:00+00', true)

# PDREPORT.new.shift_report('SYSENG Business Hours Schedule', '2018-06-04 12:00:00+00', '2018-06-06 12:00:00+00', true)
# PDREPORT.new.shift_report('Systems Engineering Non-Emergency', '2018-06-04 12:00:00+00', '2018-06-08 12:00:00+00', true)


#PDREPORT.new.shift_report('Ops (SysEng)', '2018-06-08 12:00:00+00', '2018-06-011 12:00:00+00', true)
#PDREPORT.new.shift_report('Ops Panic Secondary', '2018-06-08 12:00:00+00', '2018-06-011 12:00:00+00', true)


PDREPORT.new.shift_report('Panic', '2018-06-08 12:00:00+00', '2018-06-011 12:00:00+00', true)
PDREPORT.new.shift_report('Panic Secondary', '2018-06-08 12:00:00+00', '2018-06-011 12:00:00+00', true)







# PDREPORT.new.shift_report('Ops (SysEng)', '2016-06-04 12:00:00+00', '2018-08-06 12:00:00+00', true)
# PDREPORT.new.shift_report('Ops Panic Secondary', '2016-06-04 12:00:00+00', '2018-08-06 12:00:00+00', true)
#puts PDREPORT.new.get_incidents_from_user_id_better('PVNG7WS').map(:incident_id).uniq.count

#PDREPORT.new.check_if_incident_is_between('PM9ALXB','2012-01-01', '2018-06-06')
#puts PDREPORT.new.get_unique_incidents_from_user_id('PVNG7WS')
#PDREPORT.new.get_unique_incidents_from_user_id('PVNG7WS').uniq.each{|incident|
#   #puts "#{incident}"
#   puts PDREPORT.new.calculate_TTR("#{incident}")
#}

#PDREPORT.new.calculate_TTR('PM9ALXB').each_cons(2) {|a,b| p "#{a} = #{b}"}
#monthly_report
#puts PDREPORT.new.check_off_hours('PM9ALXB')
#PDREPORT.new.active_company_report('2012-01-01', '2018-06-06')
#PDREPORT.new.shift_report('Ops (SysEng)', '2015-01-01', '2018-06-06', true)
#PDREPORT.new.shift_report('Ops Panic Secondary', '2015-01-01', '2018-06-06',true )
#PDREPORT.new.company_report('2015-01-01', '2018-06-06')

#PDREPORT.new.get_all_historical_user_ids

# PDREPORT.new.report('Panic', 5)
# PDREPORT.new.report('Panic Secondary', 5)

##Last X days majority of pages (service)

