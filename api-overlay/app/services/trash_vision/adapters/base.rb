require "net/http"
require "json"

class TrashVision
  module Adapters
    class Base
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 60

      # transport: ->(url, headers, body_hash) { [status_integer, body_string] }, replaceable in tests.
      def initialize(env: ENV, transport: nil)
        @env = env
        @transport = transport || method(:http_post)
      end

      private

      attr_reader :env

      def required(name)
        value = env[name].to_s.strip
        raise NotConfigured, "#{name} is not set (needed by TRASH_VISION_PROVIDER)" if value.empty?

        value
      end

      def optional(name, default)
        value = env[name].to_s.strip
        value.empty? ? default : value
      end

      def prompt
        "#{TrashVision::PROMPT}\nAllowed types: #{Trash::TYPES.join(', ')}."
      end

      # Returns the parsed JSON body, or raises RequestFailed. Never puts the API key in a message.
      def post_json(url, headers, body)
        status, text = @transport.call(url, headers, body)
        parsed = begin
          JSON.parse(text.to_s)
        rescue JSON::ParserError
          nil
        end
        return parsed if status.between?(200, 299) && parsed.is_a?(Hash)

        detail = parsed.is_a?(Hash) ? (parsed.dig("error", "message") || parsed["message"]) : nil
        hint = [401, 403].include?(status) ? " (check the API key)" : ""
        raise RequestFailed, "#{self.class.name.split('::').last} answered HTTP #{status}#{hint}: #{detail.to_s[0, 200]}"
      end

      def http_post(url, headers, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        request = Net::HTTP::Post.new(uri.request_uri, headers.merge("content-type" => "application/json"))
        request.body = JSON.generate(body)
        response = http.request(request)
        [response.code.to_i, response.body]
      end
    end
  end
end
