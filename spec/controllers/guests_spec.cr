require "../spec_helper"

describe Guests do
  guest1 = Guest.new
  guest2 = Guest.new

  Spec.before_each do
    guest1 = Guest.new
    guest1.name = "Steve"
    guest1.email = "steve@place.techn"
    guest1.save

    guest2 = Guest.new
    guest2.name = "Jon"
    guest2.email = "jon@place.techn"
    guest2.save
  end

  Spec.after_each do
    guest1.destroy
    guest2.destroy
  end

  it "should return a list of guests" do
    # instantiate the controller
    response = IO::Memory.new
    app = Guests.new(context("GET", "/api/staff/v1/guests", HEADERS, response_io: response))

    # Test the instance method of the controller
    app.index
    response.to_s.split("\r\n").reject(&.empty?)[-1].should eq(
      %([{"email":"jon@place.techn","name":"Jon","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false},{"email":"steve@place.techn","name":"Steve","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false}])
    )
  end

  it "should return a filtered list of guests" do
    # instantiate the controller
    response = IO::Memory.new
    app = Guests.new(context("GET", "/api/staff/v1/guests?q=stev", HEADERS, response_io: response))

    # Test the instance method of the controller
    app.index
    response.to_s.split("\r\n").reject(&.empty?)[-1].should eq(
      %([{"email":"steve@place.techn","name":"Steve","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false}])
    )
  end

  it "should return guests visiting today" do
    now = Time.utc.to_unix
    later = 4.hours.from_now.to_unix
    route = "/api/staff/v1/guests?period_start=#{now}&period_end=#{later}"
    response = IO::Memory.new
    app = Guests.new(context("GET", route, HEADERS, response_io: response))

    # Test the instance method of the controller
    app.index
    response.to_s.split("\r\n").reject(&.empty?)[-1].should eq("[]")

    meta = generate_event
    guest = generate_guest
    attend = guest.attendee_for(meta.id.not_nil!)

    # instantiate the controller
    response = IO::Memory.new
    app = Guests.new(context("GET", route, HEADERS, response_io: response))

    begin
      # Test the instance method of the controller
      app.index
      response.to_s.split("\r\n").reject(&.empty?)[-1].should eq(
        "[{\"email\":\"bob@outside.com\",\"name\":null,\"preferred_name\":null,\"phone\":null,\"organisation\":null,\"notes\":null,\"photo\":null,\"banned\":false,\"dangerous\":false,\"extension_data\":{},\"checked_in\":false,\"visit_expected\":true}]"
      )
    ensure
      meta.destroy
      guest.destroy
    end
  end

  systems_json = {{ read_file("#{__DIR__}/../mocks/systems.json") }}
  systems_resp = Array(JSON::Any).from_json(systems_json).map &.to_json

  it "should return guests visiting today in a subset of rooms" do
    meta = generate_event
    guest = generate_guest
    attend = guest.attendee_for(meta.id.not_nil!)

    begin
      {"sys-rJQQlR4Cn7", "sys_id"}.each_with_index do |system_id, index|
        WebMock
          .stub(:get, DOMAIN + "/api/engine/v2/systems/#{system_id}")
          .to_return(body: systems_resp[index])
      end

      now = Time.utc.to_unix
      later = 4.hours.from_now.to_unix
      route = "/api/staff/v1/guests?period_start=#{now}&period_end=#{later}&system_ids=sys-rJQQlR4Cn7"
      response = IO::Memory.new
      app = Guests.new(context("GET", route, HEADERS, response_io: response))

      # Test the instance method of the controller
      app.index
      response.to_s.split("\r\n").reject(&.empty?)[-1].should eq("[]")

      # instantiate the controller
      response = IO::Memory.new
      route = "/api/staff/v1/guests?period_start=#{now}&period_end=#{later}&system_ids=sys-rJQQlR4Cn7,sys_id"
      app = Guests.new(context("GET", route, HEADERS, response_io: response))

      # Test the instance method of the controller
      app.index
      response.to_s.split("\r\n").reject(&.empty?)[-1].should eq(
        "[{\"email\":\"bob@outside.com\",\"name\":null,\"preferred_name\":null,\"phone\":null,\"organisation\":null,\"notes\":null,\"photo\":null,\"banned\":false,\"dangerous\":false,\"extension_data\":{},\"checked_in\":false,\"visit_expected\":true}]"
      )
    ensure
      meta.destroy
      guest.destroy
    end
  end
end
