# encoding: utf-8
require "json"
require "logstash/outputs/base"
require "logstash/namespace"
require "net/http"
require "net/https"
require "uri"

class LogStash::Outputs::NewRelic < LogStash::Outputs::Base
  config_name "newrelic"
  milestone 1
  
  config :account_id, :validate => :string, :required => true
  config :insert_key, :validate => :string, :required => true
  config :event_type, :validate => :string, :default => "logstashEvent"
  
  # Should the log action be sent over https instead of plain http
  config :proto, :validate => :string, :default => "https"

  # Proxy Info - all optional
  config :proxy_host, :validate => :string
  config :proxy_port, :validate => :number
  config :proxy_user, :validate => :string
  config :proxy_password, :validate => :password

  # New Relic Insights Reserved Words
  # https://docs.newrelic.com/docs/insights/new-relic-insights/adding-querying-data/inserting-custom-events#keywords
  RESWORDS = {"accountId" => "accountId_moved", "appId" => "appId_moved", "timestamp" => "timestamp_moved", "type" => "type_moved", "ago" => "`ago`", "and" => "`and`", "as" => "`as`", "auto" => "`auto`", "begin" => "`begin`", "begintime" => "`begintime`", "compare" => "`compare`", "day" => "`day`", "days" => "`days`", "end" => "`end`", "endtime" => "`endtime`", "explain" => "`explain`", "facet" => "`facet`", "from" => "`from`", "hour" => "`hour`", "hours" => "`hours`", "in" => "`in`", "is" => "`is`", "like" => "`like`", "limit" => "`limit`", "minute" => "`minute`", "minutes" => "`minutes`", "month" => "`month`", "months" => "`months`", "not" => "`not`", "null" => "`null`", "offset" => "`offset`", "or" => "`or`", "second" => "`second`", "seconds" => "`seconds`", "select" => "`select`", "since" => "`since`", "timeseries" => "`timeseries`", "until" => "`until`", "week" => "`week`", "weeks" => "`weeks`", "where" => "`where`", "with" => "`with`"}

  public
  def register
    # nothing to do
  end

  public
  def receive(event)
    return unless output?(event)
    if event == LogStash::SHUTDOWN
      finished
      return
    end
    this_event = event.to_hash
    output_event = Hash.new
    
    # Send the event over http(s) to the New Relic Insights REST API
    url = URI.parse("#{@proto}://insights-collector.newrelic.com/v1/accounts/#{@account_id}/events")
    # @logger.debug("New Relic URL", :url => url)
    if proxy_host.nil? || proxy_host.empty?
      http = Net::HTTP.new(url.host, url.port)
    else
      http = Net::HTTP.new(url.host, url.port, @proxy_host, @proxy_port, @proxy_user, @proxy_password.value)
    end
    if url.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    
    # Insights uses a POST, requires Content-Type and X-Insert-Key.
    request = Net::HTTP::Post.new(url.path)
    request['Content-Type'] = "application/json"
    request['X-Insert-Key'] = @insert_key
    
    # Tomcat's timestamp is right except for a trailing ".###"
    if this_event.has_key?('timestamp') && this_event['timestamp'] =~ /\d+\.\d+/
      output_event['timestamp'] = this_event['timestamp'].split('.')[0]
    end
    
	# Search event's attribute names for reserved words, replace with 'compliant' versions
	this_event.each_key do |event_key|
    	if RESWORDS.has_key?(event_key)
          @logger.debug("Reserved word found", :reserved_word => event_key)
          proper_name = RESWORDS[event_key]
          output_event[proper_name] = this_event[event_key]
    	else
    	  output_event[event_key] = this_event[event_key]
    	end
    end
    
    # Setting eventType to what's in the config
    output_event['eventType'] = @event_type
        
    request.body = output_event.to_json
    @logger.debug("Request", :request_body => request.body)
    response = http.request(request)
    if response.is_a?(Net::HTTPSuccess)
      @logger.debug("Event sent to New Relic SUCCEEDED!", :response_code => response.code)
    else
      @logger.warn("Event sent to New Relic FAILED.", :error => response.error!)
    end
  end # def receive
end # class LogStash::Outputs::NewRelic
