#!env ruby
require 'json'
require 'open-uri'
require 'todoist'
require 'yaml'
require 'digest/sha1'

config = YAML.load(open('./config.yml'))

REDMINE_API_KEY = config['redmine-api-key']
TODOIST_API_KEY = config['todoist-api-key']

Todoist::Base.setup(TODOIST_API_KEY, true)

project = Todoist::Project.all.find{|p| p.name == config['todoist-project']}

redmineTasks = JSON.parse(open("#{config['redmine-base-url']}/issues.json?key=#{REDMINE_API_KEY}&limit=50&#{config["redmine-issues-query-parameters"]}").read.force_encoding("UTF-8"))

localMap = JSON.parse(open("tasks.json").read) rescue {}

stillOpen = {}
newLocalMap = {}
newLocalMap['hashes'] = {}

serverTasks = project.tasks

redmineTasks['issues'].each do |issue|
  stillOpen[issue['id']] = true

  task = serverTasks.find{|t| t.id == localMap[issue['id'].to_s]}
  update_date = true
  if task && localMap['hashes'][issue['id'].to_s] == Digest::SHA1.hexdigest(issue.to_json)
    effective_due = nil
    update_date = false
  else
    effective_due = issue['due_date']
    expected_done = issue['custom_fields'].find{|cf| cf['name'] == 'Expected Done By'}
    expected_done = expected_done['value'] if expected_done
    if expected_done && expected_done.length > 0
      if effective_due && Time.parse(expected_done) > Time.parse(effective_due)
        effective_due = expected_done
      end
    end
  end

  if effective_due.to_s.empty?
    effective_due = nil
  else
    effective_due = Time.parse(effective_due)
  end

  tags = []
  tags << config["todoist-tag"] unless config["todoist-tag"].to_s.empty?
  if config['redmine-project-label-map'] && config['redmine-project-label-map'][issue['project']['name']]
    tags << config['redmine-project-label-map'][issue['project']['name']]
  end

  status_tag = config['redmine-status-label-map'][issue['status']['name']] if config['redmine-status-label-map']
  tags << status_tag unless status_tag.to_s.empty?

  if update_date && config["redmine-always-due-today"] && config['redmine-always-due-today'].include?(issue['status']['name'])
    effective_due = Time.now
  end

  content = ([issue['subject'].gsub("@",".@"), "[R#{issue['id']}](#{config['redmine-base-url']}/issues/#{issue['id']})"] + tags).join(" ")
  priority_map = config['todoist-priority-map'] || {}
  priority = priority_map[issue['priority']['name']] || 1

  task = serverTasks.find{|t| t.id == localMap[issue['id'].to_s]}
  params = {}
  params["priority"] = priority
  if effective_due
    params['date_string'] = effective_due.strftime("%-d %b %Y")
  end
  if task && !task.complete?
    params["id"] = task.id
    params["content"] = content

    result = Todoist::Base.get('/updateItem', :query => params)

    newLocalMap[issue['id']] = localMap[issue['id'].to_s]
  else
    task = Todoist::Task.create(content, project, params)
    newLocalMap[issue['id'].to_s] = task.id
  end
  newLocalMap['hashes'][issue['id'].to_s] = Digest::SHA1.hexdigest(issue.to_json)
end

open("tasks.json", "w") do |file|
  file.write newLocalMap.to_json
end

remoteMap = newLocalMap.invert

serverTasks.each do |task|
  if remoteMap[task.id].nil? && task.content.include?(config['redmine-base-url'])
    begin
      Todoist::Task.complete([task.id])
    rescue => exc
    end
  end
end


#require 'icalendar'

#shows = Icalendar.parse(open("http://trakt.tv/calendars/my/shows.ics?slurm=7a0de2168e36b1250fb6b18d43e0f10c"))
#cal = shows.first
#shows = JSON.parse(open("shows.json").read) rescue {}

#project = Todoist::Project.all.find{|p| p.name == 'TV Shows'}
#tasks = project.tasks
#cal.events.each do |evt|
#  next if evt.dtstart < DateTime.now
#  existingTaskId = shows[evt.url.to_s]
#  task = tasks.find{|t| t.id == existingTaskId}
#  if task
#    #Todoist::Base.get("/updateItem", :query => {"content" => "Download #{evt.summary} #{evt.url}", "date_string" => evt.dtend.strftime("%-d %b %Y %H:%M %P"), "id" => task.id})
#  else
#    #task = Todoist::Task.create("Download #{evt.summary} #{evt.url}", project, {"date_string" => evt.dtend.strftime("%-d %b %Y %H:%M %P")})
#    #shows[evt.url.to_s] = task.id.to_i
#  end
#end
#open("shows.json","w") do |file|
#  file.write shows.to_json
#end
