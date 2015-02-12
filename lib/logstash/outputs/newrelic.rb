# encoding: utf-8
require "json"
require "logstash/outputs/base"
require "logstash/namespace"
require "net/http"
require "net/https"
require "stud/buffer"
require "time"
require "uri"

class LogStash::Outputs::NewRelic < LogStash::Outputs::Base
  include Stud::Buffer

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
  config :proxy_password, :validate => :password, :default => ""

  # Batch Processing - all optional
  config :batch, :validate => :boolean, :default => true
  config :batch_events, :validate => :number, :default => 10
  config :batch_timeout, :validate => :number, :default => 5

  # New Relic Insights Reserved Words
  # https://docs.newrelic.com/docs/insights/new-relic-insights/adding-querying-data/inserting-custom-events#keywords
  # moved = change "word" to "word_moved"
  # backticks = change "word" to "`word`"
  # If you enter anything else, the "word" will change to the "anything else"
  RESWORDS = {
    "accountId" => "moved",
    "appId" => "moved",
    "timestamp" => "moved",
    "type" => "moved",
    "ago" => "backticks",
    "and" => "backticks",
    "as" => "backticks",
    "auto" => "backticks",
    "begin" => "backticks",
    "begintime" => "backticks",
    "compare" => "backticks",
    "day" => "backticks",
    "days" => "backticks",
    "end" => "backticks",
    "endtime" => "backticks",
    "explain" => "backticks",
    "facet" => "backticks",
    "from" => "backticks",
    "hour" => "backticks",
    "hours" => "backticks",
    "in" => "backticks",
    "is" => "backticks",
    "like" => "backticks",
    "limit" => "backticks",
    "minute" => "backticks",
    "minutes" => "backticks",
    "month" => "backticks",
    "months" => "backticks",
    "not" => "backticks",
    "null" => "backticks",
    "offset" => "backticks",
    "or" => "backticks",
    "second" => "backticks",
    "seconds" => "backticks",
    "select" => "backticks",
    "since" => "backticks",
    "timeseries" => "backticks",
    "until" => "backticks",
    "week" => "backticks",
    "weeks" => "backticks",
    "where" => "backticks",
    "with" => "backticks"
  }

  public

  def register
    # URL to send event over http(s) to the New Relic Insights REST API
    @url = URI.parse("#{@proto}://insights-collector.newrelic.com/v1/accounts/#{@account_id}/events")
    @logger.info("New Relic Insights output initialized.")
    @logger.info("New Relic URL: #{@url}")
    if @batch
      @logger.info("Batch processing of events enabled.")
      if @batch_events > 1000
        raise RuntimeError.new("New Relic Insights only allows a batch_events parameter of 1000 or less")
      end
      buffer_initialize(
      :max_items => @batch_events,
      :max_interval => @batch_timeout,
      :logger => @logger
      )
    end
  end #def register

  public
  def receive(event)
    return unless output?(event)
    if event == LogStash::SHUTDOWN
      finished
      return
    end
    parsed_event = parse_event(event)
    if @batch
      buffer_receive(parsed_event)
    else
      send_to_insights(parsed_event)
    end
  end # def receive

  public
  def flush(events, teardown=false)
    @logger.debug("Sending batch of #{events.size} events to insights")
    send_to_insights(events)
  end # def flush

  public
  def teardown
    buffer_flush(:final => true)
    finished
  end # def teardown
  
  # Turn event into an Insights-compliant event
  def parse_event(event)
    this_event = event.to_hash
    output_event = Hash.new

    # Setting eventType to what's in the config
    output_event['eventType'] = @event_type

    # Convert timestamp to Insights-compliant form if it exists
    # Tomcat's timestamp is right except for a trailing ".###"
    begin
      if this_event.has_key?('timestamp')
        # If it's just a whole number, send it as-is to Insights.
        if this_event['timestamp'] =~ /\A\d+\z/
          output_event['timestamp'] = this_event['timestamp']
          # Tomcat's timestamp is right except for a trailing ".###"
        elsif this_event['timestamp'] =~ /\A\d+\.\d+\z/
          output_event['timestamp'] = this_event['timestamp'].split('.')[0]
          # If in any other form, attempt to parse the date/time and convert to seconds since epoch
        else
          timestamp_parsed = Time.parse(this_event['timestamp'])
          output_event['timestamp'] = timestamp_parsed.to_i
        end
      end
    rescue Exception => e
      # If it throws an exception, likely because date parsing didn't go so well, do nothing
      @logger.debug("Exception occurred when converting timestamp. Exception:", :exception => e.message)
    end

    # Search event's attribute names for reserved words, replace with 'compliant' versions
    # Storing 'compliant' key names in "EVENT_KEYS" to minimize time spent doing this
    this_event.each_key do |event_key|
      if RESWORDS.has_key?(event_key)
        @logger.debug("Reserved word found", :reserved_word => event_key)
        if RESWORDS[event_key] = "moved"
          proper_name = event_key + "_moved"
        elsif RESWORDS[event_key] = "backticks"
          proper_name = "`" + event_key + "`"
        else
          proper_name = RESWORDS[event_key]
        end
      else
        proper_name = event_key
      end
      output_event[proper_name] = this_event[event_key]
    end

    return output_event
  end # def parse_event

  # Can handle a single event or batched events
  def send_to_insights(event)
    http = Net::HTTP.new(@url.host, @url.port, @proxy_host, @proxy_port, @proxy_user, @proxy_password.value)
    if @url.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    # Insights uses a POST, requires Content-Type and X-Insert-Key.
    request = Net::HTTP::Post.new(@url.path)
    request['Content-Type'] = "application/json"
    request['X-Insert-Key'] = @insert_key
    request.body = event.to_json
    @logger.debug("Request Body:", :request_body => request.body)

    response = http.request(request)
    if response.is_a?(Net::HTTPSuccess)
      @logger.debug("Event sent to New Relic SUCCEEDED! Response Code:", :response_code => response.code)
    else
      @logger.warn("Event sent to New Relic FAILED. Error:", :error => response.error!)
    end
  end # def send_to_insights
  
end # class LogStash::Outputs::NewRelic