require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/codecs/plain"
require "logstash/event"

# TO DO: Well... most of it. This is just the start.

describe LogStash::Outputs::NewRelic do

  let (:simple_event) { LogStash::Event.new( {  'message' => 'hello', 'topic_name' => 'my_topic', 'host' => '172.0.0.1',
												'@timestamp' => LogStash::Timestamp.now } ) }
  let(:output) { LogStash::Outputs::NewRelic.new }
  let(:options)  {  { "account_id" => "284929",
                      "insert_key" => "BYh7sByiVrkfqcDa2eqVMhjxafkdyuX0" } }
                      
  it "should register" do
    output = LogStash::Plugin.lookup("output", "newrelic").new(options)
    expect {output.register}.to_not raise_error
  end
  
  before do
    output.register
  end

  describe "::receive" do
    subject { output.receive(simple_event) }
  end
end