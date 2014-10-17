require 'json'
require 'open-uri'
require 'todoist'
require 'yaml'

config = YAML.load(open('./config.yml'))

REDMINE_API_KEY = config['redmine-api-key']
TODOIST_API_KEY = config['todoist-api-key']

Todoist::Base.setup(TODOIST_API_KEY, true)

project = Todoist::Project.all.find{|p| p.name == config['todoist-project']}

redmineTasks = JSON.parse(open("#{config['redmine-base-url']}/issues.json?key=#{REDMINE_API_KEY}&limit=50&#{config["redmine-issues-query-parameters"]}").read.force_encoding("UTF-8"))

localMap = JSON.parse(open("tasks.json").read) rescue {}

stillOpen = {}
newLocalMap = {}

serverTasks = project.tasks

redmineTasks['issues'].each do |issue|
  stillOpen[issue['id']] = true

  effective_due = issue['due_date']
  expected_done = issue['custom_fields'].find{|cf| cf['name'] == 'Expected Done By'}
  expected_done = expected_done['value'] if expected_done
  if expected_done && expected_done.length > 0
    if effective_due && Time.parse(expected_done) > Time.parse(effective_due)
      effective_due = expected_done
    end
  end

  effective_due = Time.parse(effective_due) unless effective_due.to_s.empty?

  tags = []
  tags << config["todoist-tag"] unless config["todoist-tag"].to_s.empty?

  status_tag = config['redmine-status-label-map'][issue['status']['name']] if config['redmine-status-label-map']
  tags << status_tag unless status_tag.to_s.empty?

  if config["redmine-always-due-today"] && config['redmine-always-due-today'].include?(issue['status']['name'])
    effective_due = Time.now
  end

  content = ([issue['subject'], "#{config['redmine-base-url']}/issues/#{issue['id']}"] + tags).join(" ")
  puts issue['priority']
  priority_map = config['todoist-priority-map'] || {}
  priority = priority_map[issue['priority']['name']] || 1

  task = serverTasks.find{|t| t.id == localMap[issue['id'].to_s]}
  if task && !task.complete?
    puts "Updating task #{issue['id']}"
    result = Todoist::Base.get('/updateItem', :query => {
        "id" => task.id,
        "content" => content,
        "priority" => priority,
        "date_string" => effective_due ? effective_due.strftime("%a %b %d %Y 17:00:00") : nil,
        "due_date" => effective_due ? effective_due.strftime("%Y-%m-%dT17:00") : nil
      })

    newLocalMap[issue['id']] = localMap[issue['id'].to_s]
  else
    puts "Creating #{content}"
    task = Todoist::Task.create(content, project, {
      "priority" => priority,
      "date_string" => effective_due ? effective_due.strftime("%a %b %d %Y 17:00:00") : nil
      })
    newLocalMap[issue['id'].to_s] = task.id
  end
end

open("tasks.json", "w") do |file|
  file.write newLocalMap.to_json
end

remoteMap = newLocalMap.invert

serverTasks.each do |task|
  if remoteMap[task.id].nil? && task.content.include?(config['redmine-base-url'])
    puts "Completing #{task.id}"
    begin
      Todoist::Task.complete([task.id])
    rescue => exc
    end
  end
end

puts "Done."