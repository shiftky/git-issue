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

    def list(options = {})
      query_names = %i(state milestone labels)
      params = query_names.inject({}) { |hash, key| hash[key] = options[key] if options[key]; hash }
      params[:state] ||= 'opened'

      url = to_url("projects", @repo.gsub("/", "%2F"), "issues")
      issues = fetch_json(url, options, params)

      issues = issues.sort_by { |issue| issue['iid'] }

      title_max = issues.map { |issue| mlength(issue['title']) }.max
      label_max = issues.map { |issue| mlength(issue['labels'].join(",")) }.max
      username_max = issues.map { |issue| mlength(issue['author']['username']) }.max

      issues.each do |issue|
        comments_url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue['id'], "notes")
        comments = fetch_json(comments_url)

        puts sprintf('%s %s %s %s %s c:%s %s %s',
                      apply_fmt_colors(:id, sprintf('#%-4d', issue['iid'])),
                      apply_fmt_colors(:state, issue['state']),
                      mljust(issue['title'], title_max),
                      apply_fmt_colors(:labels, mljust(issue['labels'].join(","), label_max)),
                      apply_fmt_colors(:author, mljust(issue['author']['username'], username_max)),
                      comments.count,
                      to_date(issue['created_at']),
                      to_date(issue['updated_at'])
        )
      end
    end

    private

    def to_url(*path_list)
      @url + "/#{path_list.join("/")}"
    end

    def fetch_json(url, options = {}, params = {})
      response = send_request(url, {}, options, params, :get)
      json = JSON.parse(response.body)
      raise error_message(json) unless response_success?(response)
      json
    end

    def error_message(json)
      msg = [json['message']]
      msg += json['errors'].map(&:pretty_inspect) if json['errors']
      msg.join("\n  ")
    end

    def send_request(url, json = {}, options = {}, params = {}, method)
      uri = URI.parse(url)

      http = connection(uri.host, uri.port)
      http.start { |http|
        path = uri.path
        path += '?' + params.map { |name, value| "#{name}=#{value}" }.join("&") if params.present?

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

    def apply_fmt_colors(key, str)
      fmt_colors[key.to_sym] ? apply_colors(str, *Array(fmt_colors[key.to_sym])) : str
    end

    def fmt_colors
      @fmt_colors ||= { id: [:bold, :cyan],
        state: :blue,
        author: :magenta,
        labels: :yellow,
      }
    end
  end
end
