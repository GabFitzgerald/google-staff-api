class Staff < Application
  base "/api/staff/v1/people"

  @@dir_service = if App::DIR_SERVICE_ACCT
                    [PlaceOS::Client.new(
                      App::PLACE_URI,
                      App::DIR_SERVICE_USER,
                      App::DIR_SERVICE_PASS,
                      App::DIR_SERVICE_CLIENT_ID,
                      App::DIR_SERVICE_SECRET,
                    )]
                  else
                    Array(PlaceOS::Client).new
                  end

  protected def user_token
    client = @@dir_service[0]
    # TODO:: expires don't grab this every request, cache until almost expired
    client.users.resource_token.token
  end

  def index
    query = params["q"]?

    # If we can't use the 2-legged auth to access the staff directory
    dir = if App::DIR_SERVICE_ACCT
            google_directory(user_token)
          else
            google_directory
          end

    render json: dir.users(query).users.map { |u| build_user(u) }
  end

  def show
    id = params["id"]

    # If we can't use the 2-legged auth to access the staff directory
    dir = if App::DIR_SERVICE_ACCT
            google_directory(user_token)
          else
            google_directory
          end

    # TODO:: return user location information

    user_info = dir.lookup(id)
    render json: build_user(user_info)
  end

  def build_user(google_user) : Hash(Symbol, String)
    user_name = google_user.name.full_name || "#{google_user.name.given_name} #{google_user.name.family_name}"

    if phones = google_user.phones.try(&.select(&.primary))
      phone = phones.first?.try(&.value) || google_user.recovery_phone
    end

    if orgs = google_user.organizations.try(&.select(&.primary))
      department = orgs.first?.try &.department
    end

    if accounts = google_user.posix_accounts.try(&.select(&.primary))
      account = accounts.first?.try &.username
    end

    {
      name:       user_name,
      email:      google_user.primary_email,
      phone:      phone,
      department: department,
      photo:      google_user.thumbnail_photo_url,
      username:   account,
    }.to_h.compact
  end
end
