module GitIssue
  class GitIssue::Gitlab < GitIssue::Base
    def initialize(args, options = {})
      super(args, options)

      @repo = options[:repo] || configured_value('issue.repo')
      if @repo.blank?
        url = `git config remote.origin.url`.strip
        if url.empty?
          raise "please set remote.origin.url.\n\n\tgit remote add origin git@gitlab.example.com:username/repo_name.git\n\n"
        end
        @repo = url.match(/([^\/:]+\/[^\/]+)\.git/)[1]
      end

      @url = options[:url] || configured_value('issue.url')
      configure_error('url', "git config issue.url http://gitlab.example.com/api/v3") if @url.blank?

      @user = options[:user] || configured_value('issue.user')
      @user = global_configured_value('github.user') if @user.blank?
      configure_error('user', "git config issue.user yuroyoro") if @user.blank?

      @token = options[:token] || configured_value('issue.token')
      configure_error('token', "git config issue.token MAwbtYEG6Pz5WJNB7jZb") if @token.blank?

      @ssl_options = {}
      if @options.key?(:sslNoVerify) && RUBY_VERSION < "1.9.0" || configured_value('http.sslVerify') == "false"
        @ssl_options[:ssl_verify_mode] = OpenSSL::SSL::VERIFY_NONE
      end
      if (ssl_cert = configured_value('http.sslCert'))
        @ssl_options[:ssl_ca_cert] = ssl_cert
      end
    end

    def commands
      cmds = super
      unused_cmds = %i(cherry publish rebase)
      cmds.delete_if { |cmd| unused_cmds.include?(cmd.name) }
      cmds << GitIssue::Command.new(:mention, :men, 'create a comment to given issue.')
      cmds << GitIssue::Command.new(:close , :cl, 'close an issue with comment. comment is optional.')
    end

    def show(options = {})
      ticket_id = options[:ticket_id]
      raise 'ticket_id required.' unless ticket_id

      issue = fetch_issue(ticket_id)
      comments_url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue['id'], "notes")
      comments = fetch_json(comments_url)
      puts format_issue(issue, comments)
    end

    def view(options = {})
      ticket_id = options[:ticket_id]
      raise 'ticket_id required.' unless ticket_id

      base_uri = URI.parse(@url)
      url = "#{base_uri.scheme}://#{base_uri.host}/#{@repo}/issues/#{ticket_id}"
      system "git web--browse #{url}"
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
        if options[:assignee].present?
          next if issue['assignee'].nil?
          next unless issue['assignee']['username'] == options[:assignee]
        end

        puts sprintf('%s %s %s %s %s %s %s',
                      apply_fmt_colors(:id, sprintf('#%-4d', issue['iid'])),
                      apply_fmt_colors(:state, issue['state']),
                      mljust(issue['title'], title_max),
                      apply_fmt_colors(:labels, mljust(issue['labels'].join(","), label_max)),
                      apply_fmt_colors(:author, mljust(issue['author']['username'], username_max)),
                      to_date(issue['created_at']),
                      to_date(issue['updated_at'])
        )
      end
    end

    def mine(options = {})
      list(options.merge(assignee: @user))
    end

    def add(options = {})
      message = <<-MSG
### Write title here ###

### descriptions here ###
      MSG

      params = {}
      if options[:title]
        params[:title] = options[:title]
      else
        params[:title], params[:description] = get_title_and_body_from_editor(message)
      end

      url = to_url("projects", @repo.gsub("/", "%2F"), 'issues')
      issue = fetch_json(url, options, params, :post)
      puts "created issue #{issue_title(issue)}"
    end

    def update(options = {})
      ticket_id = options[:ticket_id]
      raise 'ticket_id required.' unless ticket_id

      issue = fetch_issue(ticket_id)

      params = {}
      names = %i(title description)
      if options.slice(*names).empty?
        message = "#{issue['title']}\n\n#{issue['description']}"
        params[:title], params[:description] = get_title_and_body_from_editor(message)
      else
        params[:title] = options[:title] if options[:title].present?
        params[:description] = options[:description] if options[:description].present?
      end
      params[:state_event] = options[:state_event] if options[:state_event].present?

      url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue['id'])
      issue = fetch_json(url, options, params, :put)
      puts "updated issue #{issue_title(issue)}"
    end

    def branch(options = {})
      ticket = options[:ticket_id]
      raise 'ticket_id is required.' unless ticket

      branch_name = ticket_branch(ticket)

      if options[:force]
        system "git branch -D #{branch_name}" if options[:force]
        system "git checkout -b #{branch_name}"
      else
        if %x(git branch -l | grep "#{branch_name}").strip.empty?
          system "git checkout -b #{branch_name}"
        else
          system "git checkout #{branch_name}"
        end
      end

      show(options)
    end

    def mention(options = {})
      ticket_id = options[:ticket_id]
      raise 'ticket_id required.' unless ticket_id

      message = '### comment here ###'
      body = options[:body] || get_body_from_editor(message)
      raise 'comment body is required.' if body.empty?
      raise "Aborting cause messages didn't modified." if body == message

      post_data = { body: body }
      issue = fetch_issue(ticket_id)
      url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue['id'], 'notes')
      comment = fetch_json(url, options, post_data, :post)
      puts "commented issue #{issue_title(issue)}"
    end

    def close(options = {})
      ticket_id = options[:ticket_id]
      raise 'ticket_id required.' unless ticket_id

      mention(options)

      params = { state_event: 'close' }
      issue = fetch_issue(ticket_id)
      url = to_url("projects", @repo.gsub("/", "%2F"), "issues", issue['id'])
      issue = fetch_json(url, options, params, :put)
      puts "closed issue #{issue_title(issue)}"
    end

    private

    def to_url(*path_list)
      @url + "/#{path_list.join("/")}"
    end

    def fetch_json(url, options = {}, params = {}, method = :get)
      response = send_request(url, {}, options, params, method)
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
      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = @ssl_options[:ssl_verify_mode] || OpenSSL::SSL::VERIFY_NONE

        store = OpenSSL::X509::Store.new
        if @ssl_options[:ssl_ca_cert].present?
          if File.directory? @ssl_options[:ssl_ca_cert]
            store.add_path @ssl_options[:ssl_ca_cert]
          else
            store.add_file @ssl_options[:ssl_ca_cert]
          end
          http.cert_store = store
        else
          store.set_default_paths
        end
        http.cert_store = store
      end

      path = uri.path
      path += '?' + params.map { |name, value| "#{URI.encode(name.to_s)}=#{URI.encode(value.to_s)}" }.join("&") if params.present?

      request = case method
        when :post then Net::HTTP::Post.new(path)
        when :put then Net::HTTP::Put.new(path)
        when :get then Net::HTTP::Get.new(path)
        else raise "unknown method #{method}"
      end

      request['PRIVATE-TOKEN'] = @token
      request.set_content_type "application/json"
      request.body = json.to_json if json.present?

      http.start { |h|
        return h.request(request)
      }
    end

    def fetch_issue(issue_iid)
      url = to_url("projects", @repo.gsub("/", "%2F"), "issues")
      issues = fetch_json(url)
      issues.each do |issue|
        return issue if issue['iid'] == issue_iid.to_i
      end
      raise "issue ##{issue_iid} not found."
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
      "[#{apply_fmt_colors(:state, issue['state'])}] #{apply_fmt_colors(:id, "##{issue['iid']}")} #{issue['title']}"
    end

    def issue_author(issue)
      author     = issue['author']['username']
      created_at = issue['created_at']
      "#{apply_fmt_colors(:login, author)} opened this issue #{Time.parse(created_at)}"
    end

    def format_comments(comments)
      cmts = []
      comments.sort_by { |comment| comment['created_at'] }.each_with_index do |c, n|
        cmts += format_comment(c, n)
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

    def opt_parser
      opts = super
      opts.on("--assignee=VALUE", "Use the given value to create/update issue. or query of listing issues. (String User login)") { |v| @options[:assignee] = v }
      opts.on("--state=VALUE", "Use the given value to create/update issue. or query of listing issues. Where 'state' is either 'opened' or 'closed'.") { |v| @options[:state] = v }
      opts.on("--title=VALUE", "Title of issue. Use the given value to create/update issue.") { |v| @options[:title] = v }
      opts.on("--description=VALUE", "Description of issue. Use the given value to create/update issue.") { |v| @options[:description] = v }
      opts.on("--body=VALUE", "Content of issue comment. Use the given value to mention to issue.") { |v| @options[:body] = v }
    end
  end
end
