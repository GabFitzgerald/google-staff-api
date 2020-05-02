class Events < Application
  base "/api/staff/v1/events"

  # TODO:: show deleted events
  def index
    args = CalendarPeriod.new(params)
    calendars = matching_calendar_ids
    render(json: [] of Nil) unless calendars.size > 0

    include_cancelled = query_params["include_cancelled"]? == "true"
    user = user_token.user.email
    calendar = calendar_for(user)

    # Grab events in parallel
    results = Promise.all(calendars.map { |calendar_id, system|
      Promise.defer {
        calendar.events(
          calendar_id,
          args.period_start.not_nil!,
          args.period_end.not_nil!,
          showDeleted: include_cancelled
        ).items.map { |event| {calendar_id, system, event} }
      }
    }).get.flatten

    # Grab any existing eventmeta data
    metadatas = {} of String => EventMetadata
    metadata_ids = results.map { |(calendar_id, system, event)|
      system.nil? ? nil : "#{system.id}-#{event.id}"
    }.compact
    EventMetadata.where(:id, :in, metadata_ids).each { |meta| metadatas[meta.event_id] = meta }

    # return array of standardised events
    render json: results.map { |(calendar_id, system, event)|
      standard_event(calendar_id, system, event, metadatas[event.id]?)
    }
  end

  def show
    event_id = route_params["id"]
    if user_cal = query_params["calendar"]?
      # Need to confirm the user can access this calendar
      found = get_user_calendars.reject { |cal| cal[:id] != user_cal }.first?
      head(:not_found) unless found

      # Grab the event details
      event = get_event(event_id, user_cal)
      head(:not_found) unless event

      render json: standard_event(user_cal, nil, event, nil)
    elsif system_id = query_params["system_id"]?
      # Need to grab the calendar associated with this system
      system = get_placeos_client.systems.fetch(system_id)
      # TODO:: return 404 if system not found
      cal_id = system.email
      head(:not_found) unless cal_id

      event = get_event(event_id, cal_id)
      head(:not_found) unless event

      metadata = EventMetadata.find("#{system_id}-#{event_id}")
      render json: standard_event(cal_id, system, event, metadata)
    end

    head :bad_request
  end

  def destroy
    event_id = route_params["id"]
    notify_guests = query_params["notify"] != "false"
    notify_option = notify_guests ? Google::UpdateGuests::All : Google::UpdateGuests::None

    if user_cal = query_params["calendar"]?
      # Need to confirm the user can access this calendar
      found = get_user_calendars.reject { |cal| cal[:id] != user_cal }.first?
      head(:not_found) unless found

      # Grab the event details
      calendar = calendar_for(user_token.user.email)
      calendar.delete(event_id, user_cal, notify_option)

      head :accepted
    elsif system_id = query_params["system_id"]?
      # Need to grab the calendar associated with this system
      system = get_placeos_client.systems.fetch(system_id)
      # TODO:: return 404 if system not found
      cal_id = system.email
      head(:not_found) unless cal_id

      EventMetadata.find("#{system_id}-#{event_id}").try &.destroy
      calendar = calendar_for # admin when no user passed
      calendar.delete(event_id, cal_id, notify_option)

      head :accepted
    end

    head :bad_request
  end

  get("/:id/guests", :guest_list) do
    event_id = route_params["id"]
    render(json: [] of Nil) if query_params["calendar"]?
    system_id = query_params["system_id"]?
    head :bad_request unless system_id

    # Grab meeting metadata if it exists
    metadata = EventMetadata.find("#{system_id}-#{event_id}")
    render(json: [] of Nil) unless metadata

    # Find anyone who is attending
    visitors = metadata.attendees.to_a
    render(json: [] of Nil) if visitors.empty?

    # Grab the guest profiles if they exist
    guests = {} of String => Guest
    Guest.where(:id, :in, visitors.map(&.email)).each { |guest| guests[guest.id.not_nil!] = guest }

    # Merge the visitor data with guest profiles
    visitors = visitors.map { |visitor| attending_guest(visitor, guests[visitor.email]?) }
    render json: visitors
  end

  post("/:id/guests/:guest_id/checkin", :guest_checkin) do
    event_id = route_params["id"]
    guest_email = route_params["guest_id"].downcase
    checkin = (query_params["state"]? || "true") == "true"

    attendee = Attendee.where(guest_id: guest_email, event_id: event_id).limit(1).map { |at| at }.first
    attendee.checked_in = checkin
    attendee.save!

    render json: attending_guest(attendee, attendee.guest)
  end
end
