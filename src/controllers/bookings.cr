class Bookings < Application
  base "/api/staff/v1/bookings"

  before_action :find_booking, only: [:show, :update, :update_alt, :destroy, :check_in, :approve, :reject]
  before_action :check_access, only: [:update, :update_alt, :destroy, :check_in]
  getter booking : Booking?

  def index
    starting = query_params["period_start"].to_i64
    ending = query_params["period_end"].to_i64
    booking_type = query_params["type"]
    zones = Set.new((query_params["zones"]? || "").split(',').map(&.strip).reject(&.empty?)).to_a
    user_id = query_params["user"]?
    user_id = user_token.id if user_id == "current"

    results = [] of Booking

    # Bookings have the requested zones
    # https://www.postgresql.org/docs/9.1/arrays.html#ARRAYS-SEARCHING
    query = String.build do |str|
      zones.each { |_zone| str << " AND ? = ANY (zones)" }
      if user_id
        str << " AND user_id = ?"
        zones << user_id
      end
    end

    Booking.all(
      "WHERE booking_start <= ? AND booking_end >= ? AND booking_type = ?#{query}",
      [ending, starting, booking_type] + zones
    ).each { |booking| results << booking }

    render json: results
  end

  def create
    booking = Booking.from_json(request.body.as(IO))

    # check there isn't a clashing booking
    starting = booking.booking_start
    ending = booking.booking_end
    booking_type = booking.booking_type
    asset_id = booking.asset_id

    existing = [] of Booking
    Booking.all(
      "WHERE booking_start <= ? AND booking_end >= ? AND booking_type = ? AND asset_id = ?",
      [ending, starting, booking_type, asset_id]
    ).each { |b| existing << b }

    head(:conflict) unless existing.empty?

    # Add the user details
    user = user_token.user
    booking.user_id = user_token.id
    booking.user_email = user.email
    booking.user_name = user.name

    if booking.save
      spawn do
        get_placeos_client.root.signal("staff/booking/changed", {
          action:        :create,
          id:            booking.id,
          booking_type:  booking.booking_type,
          booking_start: booking.booking_start,
          booking_end:   booking.booking_end,
          timezone:      booking.timezone,
          resource_id:   booking.asset_id,
          user_id:       booking.user_id,
          user_email:    booking.user_email,
          user_name:     booking.user_name,
          zones:         booking.zones,
        })
      end

      render json: booking, status: HTTP::Status::CREATED
    else
      render json: booking.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  def update
    booking = current_booking
    changes = Booking.from_json(request.body.as(IO))

    {% for key in [:asset_id, :zones, :booking_start, :booking_end, :title, :description, :checked_in] %}
      begin
        booking.{{key.id}} = changes.{{key.id}}
      rescue NilAssertionError
      end
    {% end %}

    # merge changes into extension data
    data = booking.extension_data.as_h
    changes.extension_data.as_h.each { |key, value| data[key] = value }
    booking.extension_data = nil
    booking.ext_data = data.to_json

    # reset the checked-in state
    booking.checked_in = false
    booking.rejected = false
    booking.approved = false

    # check there isn't a clashing booking
    starting = booking.booking_start
    ending = booking.booking_end
    booking_type = booking.booking_type
    asset_id = booking.booking_type

    existing = [] of Booking
    Booking.all(
      "WHERE booking_start <= ? AND booking_end >= ? AND booking_type = ? AND asset_id = ?",
      [ending, starting, booking_type, asset_id]
    ).each { |b| existing << b }

    # Don't clash with self
    existing = existing.reject { |b| b.id == booking.id }

    head(:conflict) unless existing.empty?

    update_booking(booking)
  end

  put "/:id", :update_alt { update }

  post "/:id/approve", :approve do
    booking = current_booking
    set_approver(booking, true)
    update_booking(booking, "approved")
  end

  post "/:id/reject", :reject do
    booking = current_booking
    set_approver(booking, false)
    update_booking(booking, "rejected")
  end

  post "/:id/check_in", :check_in do
    booking = current_booking
    booking.checked_in = params["state"]? != "false"
    update_booking(booking, "checked_in")
  end

  def show
    render json: current_booking
  end

  def destroy
    booking = current_booking
    booking.destroy

    spawn do
      get_placeos_client.root.signal("staff/booking/changed", {
        action:        :cancelled,
        id:            booking.id,
        booking_type:  booking.booking_type,
        booking_start: booking.booking_start,
        booking_end:   booking.booking_end,
        timezone:      booking.timezone,
        resource_id:   booking.asset_id,
        user_id:       booking.user_id,
        user_email:    booking.user_email,
        user_name:     booking.user_name,
        zones:         booking.zones,
      })
    end

    head :accepted
  end

  # ============================================
  #              Helper Methods
  # ============================================

  def current_booking : Booking
    @booking || find_booking
  end

  def find_booking
    id = route_params["id"]
    # Find will raise a 404 (not found) if there is an error
    @booking = Booking.find!(id)
  end

  def check_access
    user = user_token
    if current_booking.user_id != user.id
      head :forbidden unless user.is_admin? || user.is_support?
    end
  end

  def update_booking(booking, signal = "changed")
    if booking.save
      spawn do
        get_placeos_client.root.signal("staff/booking/changed", {
          action:        signal,
          id:            booking.id,
          booking_type:  booking.booking_type,
          booking_start: booking.booking_start,
          booking_end:   booking.booking_end,
          timezone:      booking.timezone,
          resource_id:   booking.asset_id,
          user_id:       booking.user_id,
          user_email:    booking.user_email,
          user_name:     booking.user_name,
          zones:         booking.zones,
        })
      end

      render json: booking
    else
      render json: booking.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  def set_approver(booking, approved : Bool)
    user = user_token.user
    booking.approver_id = user_token.id
    booking.approver_email = user.email
    booking.approver_name = user.name
    booking.approved = approved
    booking.rejected = !approved
  end
end
