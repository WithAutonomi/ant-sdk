# frozen_string_literal: true

module Antd
  # Base error type for all antd errors.
  class AntdError < StandardError
    attr_reader :status_code

    def initialize(message, status_code:)
      @status_code = status_code
      super("antd error #{status_code}: #{message}")
    end
  end

  # Invalid request parameters (HTTP 400).
  class BadRequestError < AntdError
    def initialize(message) = super(message, status_code: 400)
  end

  # Insufficient funds or payment failure (HTTP 402).
  class PaymentError < AntdError
    def initialize(message) = super(message, status_code: 402)
  end

  # Resource not found on the network (HTTP 404).
  class NotFoundError < AntdError
    def initialize(message) = super(message, status_code: 404)
  end

  # Resource already exists (HTTP 409).
  class AlreadyExistsError < AntdError
    def initialize(message) = super(message, status_code: 409)
  end

  # Version conflict or fork detected (HTTP 409).
  class ForkError < AntdError
    def initialize(message) = super(message, status_code: 409)
  end

  # Payload too large (HTTP 413).
  class TooLargeError < AntdError
    def initialize(message) = super(message, status_code: 413)
  end

  # Internal server error (HTTP 500).
  class InternalError < AntdError
    def initialize(message) = super(message, status_code: 500)
  end

  # Operation not implemented by the daemon (HTTP 501).
  class NotImplementedError < AntdError
    def initialize(message) = super(message, status_code: 501)
  end

  # Daemon cannot reach the network (HTTP 502).
  class NetworkError < AntdError
    def initialize(message) = super(message, status_code: 502)
  end

  # Returns the appropriate error type for an HTTP status code.
  def self.error_for_status(code, message)
    case code
    when 400 then BadRequestError.new(message)
    when 402 then PaymentError.new(message)
    when 404 then NotFoundError.new(message)
    when 409 then AlreadyExistsError.new(message)
    when 413 then TooLargeError.new(message)
    when 500 then InternalError.new(message)
    when 501 then NotImplementedError.new(message)
    when 502 then NetworkError.new(message)
    else          AntdError.new(message, status_code: code)
    end
  end
end
