module GitIssue
  class GitIssue::Gitlab < GitIssue::Base
    def initialize(args, options = {})
      super(args, options)

      url = `git config remote.origin.url`.strip
      @repo = url.match(/([^\/]+\/[^\/]+)\.git/)[1]

      @url = options[:url] || configured_value('issue.url')
      configure_error('url', "git config issue.url http://gitlab.example.com/api/v3")  if @url.blank?

      @user = options[:user] || configured_value('issue.user')
      @user = global_configured_value('github.user') if @user.blank?
      configure_error('user', "git config issue.user yuroyoro")  if @user.blank?

      @token = options[:token] || configured_value('issue.token')
      configure_error('token', "git config issue.token XXXXXXXXXXXXXXXXXXXX")  if @token.blank?
    end

    def commands
      cl = super
    end

    def list(options = {})
      url = to_url("projects", @repo.gsub("/", "%2F"), "issues")
      issues = fetch_json(url)
      p issues
    end

    private

    def to_url(*path_list)
      @url + "/#{path_list.join("/")}"
    end

    def fetch_json(url, options = {}, params = {})
      response = send_request(url, {}, {}, {}, :get)
      json = JSON.parse(response.body)
      raise error_message(json) unless response_success?(response)
      json
    end

    def send_request(url, json = {}, options = {}, params = {}, method)
      uri = URI.parse(url)

      http = connection(uri.host, uri.port)
      http.start { |http|
        path = uri.path
        path += params.map { |name, value| "#{name}=#{value}" }.join("&") if params.present?

        request = case method
          when :post then Net::HTTP::Post.new(path)
          when :put then Net::HTTP::Put.new(path)
          when :get then Net::HTTP::Get.new(path)
          else "unknown method #{method}"
        end

        request['PRIVATE-TOKEN'] = @token
        request.set_content_type "application/json"
        request.body = json.to_json if json.present?

        response = http.request(request)

        response
      }
    end

    def error_message(json)
      msg = [json['message']]
      msg += json['errors'].map(&:pretty_inspect) if json['errors']
      msg.join("\n  ")
    end

  end
end
