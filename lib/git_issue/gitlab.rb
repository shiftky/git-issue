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

    def show(options = {})
      ticket_id = options[:ticket_id]
      raise 'ticket_id required.' unless ticket_id

      url = to_url("projects", @repo.gsub("/", "%2F"), "issues")
      issues = fetch_json(url)

      issue_id = nil
      issues.each { |issue| issue_id = issue['id'] if issue['iid'] == ticket_id }
      raise "issue ##{ticket_id} not found." unless issue_id

      url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue_id)
      issue = fetch_json(url)

      comments_url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue['id'], "notes")
      comments = fetch_json(comments_url)

      puts format_issue(issue, comments)
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

    def issue_title(issue)
      "[#{apply_fmt_colors(:state, issue['state'])}] #{apply_fmt_colors(:id, "##{issue['number']}")} #{issue['title']}"
    end

    def issue_author(issue)
      author     = issue['author']['username']
      created_at = issue['created_at']

      msg = "#{apply_fmt_colors(:login, author)} opened this issue #{Time.parse(created_at)}"
      msg
    end

    def format_comments(comments)
      cmts = []
      comments.sort_by{|c| c['created_at']}.each_with_index do |c,n|
        cmts += format_comment(c,n)
      end
      cmts
    end

    def format_comment(c, n)
      cmts = []

      cmts << "##{n + 1} - #{c['author']['username']} が#{time_ago_in_words(c['created_at'])}に更新"
      cmts << "-" * 78
      cmts +=  c['body'].split("\n").to_a if c['body']
      cmts << ""
    end

    def format_issue(issue, comments)
      msg = [""]

      msg << issue_title(issue)
      msg << "-" * 80
      msg << issue_author(issue)
      msg << ""

      props = []
      props << ['comments', comments.count]
      props << ['milestone', issue['milestone']['title']] unless issue['milestone'].blank?

      props.each_with_index do |p,n|
        row = sprintf("%s : %s", mljust(p.first, 18), mljust(p.last.to_s, 24))
        if n % 2 == 0
          msg << row
        else
          msg[-1] = "#{msg.last} #{row}"
        end
      end

      uri = URI.parse(@url)
      msg << sprintf("%s : %s", mljust('labels', 18), apply_fmt_colors(:labels, issue['labels'].join(", ")))
      msg << sprintf("%s : %s", mljust('html_url', 18), "#{uri.scheme}://#{uri.host}/#{@repo}/issues/#{issue['iid']}")
      msg << sprintf("%s : %s", mljust('updated_at', 18), Time.parse(issue['updated_at']))

      # display description
      msg << "-" * 80
      msg << "#{issue['description']}"
      msg << ""

      # display comments
      if comments && !comments.empty?
        msg << "-" * 80
        msg << ""
        cmts = format_comments(comments)
        msg += cmts.map{|s| "  #{s}"}
      end

      msg.join("\n")
    end
  end
end
