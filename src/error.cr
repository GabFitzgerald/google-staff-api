class Error < Exception
  getter message

  def initialize(@message : String = "")
    super(message)
  end

  class Unauthorized < Error
  end

  class Forbidden < Error
  end

  class InvalidParams < Error
    def initialize(@params : Params, message = "")
      super(message)
    end

    getter params
  end

  class Session < Error
    getter error_code

    def initialize(@error_code : Api::Session::ErrorCode, message = "")
      super(message)
    end

    def error_response(request_id : String = "") : Api::Session::Response
      Api::Session::Response.new(
        id: request_id,
        type: Api::Session::Response::Type::Error,
        error_code: error_code.to_i,
        message: message,
      )
    end
  end
end
