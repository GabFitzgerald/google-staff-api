require "spec"
require "./google_helper"

DOMAIN = "https://example.place.technology"
ENV["PLACE_URI"] = DOMAIN

# Your application config
# If you have a testing environment, replace this with a test config file
require "../src/config"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"
require "webmock"

Spec.before_suite &->WebMock.reset
Spec.before_each &->WebMock.reset

# Grab the models generator
require "models"
require "../lib/models/spec/generator"

# Yield an authenticated user, and a header with Authorization bearer set
def authentication
  authority = PlaceOS::Model::Generator.authority("example.place.technology")
  authority.id = "sgrp-testing"

  authenticated_user = PlaceOS::Model::Generator.user(authority).not_nil!
  authenticated_user.email = authenticated_user.email.as(String) + Random.rand(9999).to_s
  authenticated_user.id = "user-testing"
  authenticated_user.authority = authority

  authorization_header = {
    "Authorization" => "Bearer #{PlaceOS::Model::Generator.jwt(authenticated_user).encode}",
  }
  {authenticated_user, authorization_header}
end

# Provide some basic headers for auth
HEADERS = HTTP::Headers{
  "Host"          => URI.parse(DOMAIN).host.as(String),
  "Authorization" => authentication[1]["Authorization"],
}

def generate_event
  meta = EventMetadata.new
  meta.system_id = "sys_id"
  meta.event_id = "event1234"
  meta.host_email = "user@org.com"
  meta.resource_calendar = "room2@example.com"

  meta.event_start = Time.utc
  meta.event_end = 5.minutes.from_now
  result = meta.save
  result.should eq true
  meta
end

def generate_guest
  guest = Guest.new
  guest.email = "bob@outside.com"
  result = guest.save
  result.should eq true
  guest
end

EventMetadata.migrator.drop_and_create
Attendee.migrator.drop_and_create
Guest.migrator.drop_and_create
