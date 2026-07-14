# frozen_string_literal: true

module LePain
  class Response
    attr_reader :status, :body, :headers, :error, :validation_errors, :compressed_body

    def initialize(status: 200, body: {}, headers: {}, error: nil)
      @status = status
      @body = body
      @headers = headers
      @error = error
      @validation_errors = nil
    end

    def success?
      (200...300).cover?(@status)
    end

    def to_h
      h = {
        status: @status,
        body: @body,
        headers: @headers,
        error: @error,
      }
      h[:validation_errors] = @validation_errors if @validation_errors
      h
    end

    def to_json
      JSON.generate(to_h)
    end

    def self.success(body = {}, status: 200)
      new(status: status, body: body)
    end

    def self.error(message, status: 500, code: nil)
      new(status: status, error: { message: message, code: code })
    end

    def self.not_found(message = 'Resource not found')
      error(message, status: 404, code: 'not_found')
    end

    def self.bad_request(message = 'Invalid request')
      error(message, status: 400, code: 'bad_request')
    end

    def self.unauthorized(message = 'Unauthorized')
      error(message, status: 401, code: 'unauthorized')
    end
  end
end
