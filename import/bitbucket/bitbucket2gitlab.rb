#!/usr/bin/env ruby

require 'json'
require 'net/http'

################################################################
## Modify the following global variables to match yout setup. ##
################################################################
## GitLab host without the 'http(s)://' prefix. This is your FQDN.
@host="host"
@base_url="https://#{@host}/"

## Add your credentials here
@token=gitlab_key('user','password')

## Note the %2F to separate namespace and project.
## For example if your project will be named https://example.com/foo/bar,
## replace below with 'foo%2Fbar'.
@group='my-group'
@project='my-project'
@full_project_namespace="#{@group}%2F#{@project}"

## Change to 80 if you are not going to use ssl (although you should).
@http = Net::HTTP.new("#{@host}",443)

## Set to false if you are not going to use ssl (although you should).
@http.use_ssl=true

#########################
## Kick off the import ##
#########################
@milestones=get_milestones()
@members=get_members()
import(load_bitbucket())

def load_bitbucket()
  JSON.parse(IO.read('db-1.0.json'))
end

def import(bitbucket_json)
  id_map={}
  bitbucket_json['issues'].each do |issue|
	break
    issue_id=issue['id']
	labels=['bb2gl']

	# Labels!
	if(issue['kind'] == 'enhancement' or issue['kind'] == 'task')
		labels.push 'Enhancement'
	elsif(issue['kind'] == 'bug')
		labels.push 'Bug'
	elsif(issue['kind'] == 'proposal')
		labels.push 'Suggestion'
	end
	
	if(issue['priority'] == 'blocker' or issue['priority'] == 'critical' or issue['priority'] == 'major')
		labels.push 'Critical'
	end
	
	# Custom comparisons
	if(issue['component'] == 'Core/Cosmetics')
		labels.push 'Cosmetic'
	else
		labels.push 'Code'
	end
	
	# Assignee
	if issue['assignee'] == 'my_odd_user_1'
		assignee=get_member_id('OddUsersNewName')
	elsif issue['assignee'] == 'otherOddUser'
		assignee=get_member_id('OddUserOtherName')
	else
		assignee=get_member_id(issue['asignee'])
	end
	
	# Milestone
	milestone=''

	if issue['milestone'] == '1.0.x [SSO]'
		milestone = get_milestone_id("v1.0.0")
	elsif issue['milestone'] == '1.1.x [SSO-SLS]'
		milestone = get_milestone_id("v1.1.0")
	elsif issue['milestone'] == '1.2.x [EMails]'
		milestone = get_milestone_id("v1.2.0")
	elsif issue['milestone'] == '1.3.x [Laravel]'
		milestone = get_milestone_id("v1.3.0")
	elsif issue['milestone'] == '2.0 [Admin]'
		milestone = get_milestone_id("v2.0.0")
	elsif issue['milestone'] == '2.1.x [Teamspeak]'
		milestone = get_milestone_id("v2.1.0")
	elsif issue['milestone'] == '2.2.x [Laravel 5.1, Mship Bans]'
		if issue['status'] == 'resolved'
			milestone = get_milestone_id("v2.2.0")
		else
			labels.push 'Soon'
		end
	elsif issue['milestone'] == '2.2.1 [Code Improvements]'
		milestone = get_milestone_id("v2.2.1")
	elsif issue['milestone'] == '2.x.x'
		labels.push 'Future'
		labels.push 'Suggestion'
	elsif issue['milestone'] == 'x.0.x [AIS]'
		labels.push 'Future'
		labels.push 'Suggestion'
	elsif issue['milestone'] == 'x.0.x [Site]'
		labels.push 'Future'
		labels.push 'Suggestion'
	elsif issue['milestone'] == 'x.0.x [Training]'
		labels.push 'Future'
		labels.push 'Suggestion'
	elsif issue['milestone'] == 'x.0.x [VT]'
		labels.push 'Future'
		labels.push 'Suggestion'
	end
	
	# Are we holding any for a bit?
	if issue['status'] == 'on hold'
		labels.push 'On Hold'
	elsif issue['status'] == 'invalid' || issue['status'] == 'wontfix'
		labels.push 'Invalid'
		labels.push 'IO-CLOSED'
	elsif issue['status'] == 'duplicate'
		labels.push 'Duplicate'
		labels.push 'IO-CLOSED'
	elsif issue['status'] == 'closed'
		labels.push 'IO-CLOSED'
	elsif issue['status'] == 'resolved'
		labels.push 'IO-CLOSED'
	end
	
    gitlab_id=post_issue("#{issue['title']} (Old #{issue_id})",issue['content'], assignee, milestone, labels)
    id_map[issue_id]=gitlab_id
	if 'new' != issue['status'] && 'open' != issue['status'] && 'on hold' != issue['status']
		#close_issue(gitlab_id)
    end
	
  end
  bitbucket_json['comments'].each do |comment|
    if comment['content']
	
		# Let's fix any REALLY Bad issue references
		# Find all references to old issue numbers.
		results = comment['content'].scan(/#([0-9]+)\D*/i)
		
		results.each do |bad_reference|
			replacement = id_map.fetch(bad_reference[0].to_i, nil)
			if replacement.nil? || replacement == 0
				next
			else
				comment['content'] = comment['content'].gsub! bad_reference[0],replacement.to_s
			end
		end
		
		# Push away!
        	post_comment(id_map[comment['issue']],"#{comment['content']}\n\n#{comment['user']} - #{comment['created_on']}")
    end
  end

end

def gitlab_key(email,password)
  uri = URI("#{@base_url}/api/v3/session")
  res = Net::HTTP.post_form(uri, 'email' => email, 'password' => password)
  JSON.parse(res.body)['private_token']
end

def post_issue(title,description,assignee,milestone,labels)
  uri = URI("#{@base_url}/api/v3/projects/#{@full_project_namespace}/issues")
  res = Net::HTTP.post_form(uri, 'title' => title, 'description' => description, 'private_token' => @token, 'assignee_id' => assignee, 'milestone_id' => milestone, 'labels' => labels.join(","))
  created=JSON.parse(res.body)
  puts created.to_json
  created['id']
end

def post_comment(id,content)
  uri = URI("#{@base_url}/api/v3/projects/#{@full_project_namespace}/issues/#{id}/notes")
  res = Net::HTTP.post_form(uri, 'body' => content,'private_token' => @token)
  created=JSON.parse(res.body)
  puts created.to_json
end

def close_issue(id)
	
  request = Net::HTTP::Put.new(URI("#{@base_url}/api/v3/projects/#{@full_project_namespace}/issues/#{id}"))

  request.set_form_data({'private_token' => @token,'state_event'=>'close'})
  response=@http.request(request)
  puts response.inspect
  puts response.body
end

def get_issues()
  request = Net::HTTP::Get.new("#{@base_url}/api/v3/projects/#{@full_project_namespace}/issues?private_token=#{@token}")
  response=@http.request(request)
  puts response.inspect
  puts response.body
end

def get_milestones()
	uri = URI("#{@base_url}/api/v3/projects/#{@full_project_namespace}/milestones?private_token=#{@token}")
	response = Net::HTTP.get_response(uri)
	return JSON.parse(response.body)
end

def get_milestone_id(milestone_name)
	if milestone_name.nil? || milestone_name.empty?
		return ''
	end

	@milestones.each do |milestone|
		if milestone_name.casecmp(milestone['title']) == 0
			return milestone['id']
			break
		end
	end
	return ''
end

def get_members()
	uri = URI("#{@base_url}/api/v3/groups/#{@group}/members?private_token=#{@token}")
	response = Net::HTTP.get_response(uri)
	group_members = JSON.parse(response.body)
	
	uri = URI("#{@base_url}/api/v3/projects/#{@full_project_namespace}/members?private_token=#{@token}")
	response = Net::HTTP.get_response(uri)
	project_members = JSON.parse(response.body)
	
	return group_members + project_members
end

def get_member_id(member_username)
	if member_username.nil? || member_username.empty?
		return ''
	end

	@members.each do |member|
		if member_username.casecmp(member['username']) == 0
			return member['id']
			break
		end
	end
	return ''
end
