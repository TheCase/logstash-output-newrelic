require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/codecs/plain"
require "logstash/event"

# TO DO: Well... most of it. This is just the start.

describe LogStash::Outputs::NewRelic do
  let(:sample_event) { LogStash::Event.new }
  let(:output) { LogStash::Outputs::NewRelic.new }
  let(:minimal_settings)  {  { "account_id" => "284929",
                               "insert_key" => "BYh7sByiVrkfqcDa2eqVMhjxafkdyuX0" } }

  before do
    output.register
  end

  describe "receive message" do
    subject { output.receive(sample_event) }
  end
end