require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/event"

# TO DO (in order of easiest to hardest):
# + Test batch_timeout
# + Test 3 different kinds of "Insights Reserved Words": Moved, Backticks and Other
# + Test various timestamp formats
# + Test proxy (oy gevalt)

describe LogStash::Outputs::NewRelic do

  let (:simple_event) { LogStash::Event.new( {  'message' => 'hello', 'topic_name' => 'my_topic', 'host' => '172.0.0.1',
                        'timestamp' => LogStash::Timestamp.now } ) }  
  let(:options) { { "account_id" => "284929",
                      "insert_key" => "BYh7sByiVrkfqcDa2eqVMhjxafkdyuX0" } }
                      
  describe "#register" do
    it "should register" do
      output = LogStash::Plugin.lookup("output", "newrelic").new(options)
      expect { output.register }.to_not raise_error
    end
    
    it "should NOT register when batch_events > 1000" do
      options["batch_events"] = 1001
      output = LogStash::Plugin.lookup("output", "newrelic").new(options)
      expect { output.register }.to raise_error
    end
  end
 
  describe "#receive" do
    it "should send a single event" do
      options["batch"] = false
      output = LogStash::Plugin.lookup("output", "newrelic").new(options)
      output.register
      expect { output.receive(simple_event) }.to_not raise_error
    end
    
    it "should send multiple events" do
      batch_event_count = 5
      options["batch_events"] = batch_event_count
      output = LogStash::Plugin.lookup("output", "newrelic").new(options)
      output.register
      for i in 0..batch_event_count
        simple_event["iteration"] = i
        expect { output.receive(simple_event) }.to_not raise_error
      end
    end
  end
end