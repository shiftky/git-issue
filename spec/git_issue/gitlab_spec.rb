require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe GitIssue::Gitlab do
  let (:sysout) { StringIO.new }
  let (:syserr) { StringIO.new }

  let (:repo) { "yuroyoro/gitterb" }
  let (:url) { "http://gitlab.example.com/api/v3" }
  let (:user) { "yuroyoro" }
  let (:token) { "MAwbtYEG6Pz5WJNB7jZb" }

  describe '#initialize' do
    let (:args) { ['show', '1234'] }

    context 'given no repo' do
      subject { lambda { GitIssue::Gitlab.new(args) } }
      it { is_expected.to raise_error }
    end

    context 'given no URL of Gitlab API' do
      subject { lambda { GitIssue::Gitlab.new(args, repo: repo) } }
      it { is_expected.to raise_error }
    end

    context 'given no user' do
      subject { lambda { GitIssue::Gitlab.new(args, repo: repo, url: url) } }
      it { is_expected.to raise_error }
    end

    context 'given no API token' do
      subject { lambda { GitIssue::Gitlab.new(args, repo: repo, url: url, user: user) } }
      it { is_expected.to raise_error }
    end

    context 'given all required options' do
      subject { lambda { GitIssue::Gitlab.new(args, repo: repo, url: url, user: user, token: token) } }
      it { is_expected.not_to raise_error }
    end
  end

  describe '#show' do
    let (:args) { ['show', '1234'] }
    let (:gitlab) { GitIssue::Gitlab.new(args, repo: repo, url: url, user: user, token: token, sysout: sysout, syserr:syserr) }

    context 'given no ticket_id' do
      subject { lambda{ gitlab.show } }
      it { is_expected.to raise_error('ticket_id required.') }
    end

    context 'given ticket_id' do
      let (:issue) {
        { 'id' => 1234, 'iid' => 1234, 'project_id' => 100,
          'title' => "Test-issue", 'description' => "This is test data.", 'state' => "opened",
          'created_at' => "2014-11-05T15:56:36.860+09:00", 'updated_at' => "2014-11-07T15:55:12.604+09:00",
          'labels' => [], 'milestone' => nil, 'assignee' => nil,
          'author' => { 'name' => "John Smith", 'username' => "john_smith", 'id' => 2, 'state' => "active" }
        }
      }
      let (:comments) {
        [ { 'id' => 646, 'body' => "Text of the comment.", 'attachment' => nil,
            'author' => { 'name' => "John Smith", 'username' => "john_smith", 'id' => 2, 'state' => "active" },
            'created_at' => "2014-11-07T16:04:20.660+09:00"
          },
          { 'id' => 645, 'body' => "Text of the comment.", 'attachment' => nil,
            'author' => { 'name' => "Pip", 'username' => "pipin", 'id' => 3, 'state' => "active" },
            'created_at' => "2014-11-07T16:03:05.006+09:00"
          }
        ]
      }

      before do
        gitlab.stub(:fetch_issue).and_return(issue)
        gitlab.stub(:fetch_json).and_return(comments)
        gitlab.show(ticket_id: 1234)
      end

      subject { gitlab.sysout.rewind; gitlab.sysout.read }

      it { sysout.length.should_not be_zero }
      it { syserr.length.should be_zero }
      it { is_expected.to include "\n[\e[34mopened\e[0m] \e[1m\e[36m#1234\e[0m Test-issue\n" }
      it { is_expected.to include "john_smith opened this issue 2014-11-05 15:56:36 +0900" }
    end
  end

  describe '#view' do
    let (:args) { ['view', '1234'] }
    let (:gitlab) { GitIssue::Gitlab.new(args, repo: repo, url: url, user: user, token: token, sysout: sysout, syserr:syserr) }

    context 'given no ticket_id' do
      subject { lambda{ gitlab.view } }
      it { is_expected.to raise_error('ticket_id required.') }
    end

    context 'given ticket_id' do
      before do
        gitlab.stub (:system)
        gitlab.view(ticket_id: 1234)
      end

      subject { gitlab }
      it { is_expected.to have_received(:system).with("git web--browse http://gitlab.example.com/yuroyoro/gitterb/issues/1234") }
    end
  end

  describe '#list' do
    let (:args) { ['list'] }
    let (:gitlab) { GitIssue::Gitlab.new(args, repo: repo, url: url, user: user, token: token, sysout: sysout, syserr:syserr) }
    let (:issues) {
      [
        { 'id' => 1234, 'iid' => 1234, 'project_id' => 100,
          'title' => "Opened-issue1", 'description' => "This is test data.", 'state' => "opened",
          'created_at' => "2014-11-05T15:56:36.860+09:00", 'updated_at' => "2014-11-07T15:55:12.604+09:00",
          'labels' => [], 'milestone' => nil,
          'assignee' => { 'name' => "John Smith", 'username' => "john_smith", 'id' => 2, 'state' => "active" },
          'author' => { 'name' => "John Smith", 'username' => "john_smith", 'id' => 2, 'state' => "active" }
        },
        { 'id' => 1235, 'iid' => 1235, 'project_id' => 100,
          'title' => "Closed-issue1", 'description' => "This is test data.", 'state' => "closed",
          'created_at' => "2014-10-06T15:56:36.860+09:00", 'updated_at' => "2014-10-08T15:55:12.604+09:00",
          'labels' => [], 'milestone' => nil,
          'assignee' => { 'name' => "John Smith", 'username' => "john_smith", 'id' => 2, 'state' => "active" },
          'author' => { 'name' => "John Smith", 'username' => "john_smith", 'id' => 2, 'state' => "active" }
        },
        { 'id' => 1236, 'iid' => 1236, 'project_id' => 100,
          'title' => "Opened-issue2", 'description' => "This is test data.", 'state' => "opened",
          'created_at' => "2014-11-06T15:56:36.860+09:00", 'updated_at' => "2014-11-08T15:55:12.604+09:00",
          'labels' => [], 'milestone' => nil, 'assignee' => nil,
          'author' => { 'name' => "Pip", 'username' => "pipin", 'id' => 3, 'state' => "active" }
        }
      ]
    }

    subject { gitlab.sysout.rewind; gitlab.sysout.read }

    context 'given no options' do
      let (:list_options) { {} }
      before do
        return_issues = issues.delete_if { |issue| issue['state'] == 'closed' }
        gitlab.stub(:fetch_json).and_return(return_issues)
        gitlab.list
      end

      it { sysout.length.should_not be_zero }
      it { syserr.length.should be_zero }
      it { is_expected.to include "\e[1m\e[36m#1234\e[0m \e[34mopened\e[0m Opened-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/11/05 2014/11/07" }
      it { is_expected.to include "\e[1m\e[36m#1236\e[0m \e[34mopened\e[0m Opened-issue2 \e[33m\e[0m \e[35mpipin     \e[0m 2014/11/06 2014/11/08" }
    end

    context 'given state option' do
      context 'assignee is john_smith' do
        before do
          return_issues = issues.delete_if { |issue| issue['state'] == 'closed' }
          gitlab.stub(:fetch_json).and_return(return_issues)
          gitlab.list(assignee: 'john_smith')
        end

        it { sysout.length.should_not be_zero }
        it { syserr.length.should be_zero }
        it { is_expected.to include "\e[1m\e[36m#1234\e[0m \e[34mopened\e[0m Opened-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/11/05 2014/11/07" }
        it { is_expected.not_to include "\e[1m\e[36m#1235\e[0m \e[34mclosed\e[0m Closed-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/10/06 2014/10/08" }
        it { is_expected.not_to include "\e[1m\e[36m#1236\e[0m \e[34mopened\e[0m Opened-issue2 \e[33m\e[0m \e[35mpipin     \e[0m 2014/11/06 2014/11/08" }
      end
    end

    context 'given state option' do
      context 'opened' do
        before do
          return_issues = issues.delete_if { |issue| issue['state'] == 'closed' }
          gitlab.stub(:fetch_json).and_return(return_issues)
          gitlab.list(state: 'opened')
        end

        it { sysout.length.should_not be_zero }
        it { syserr.length.should be_zero }
        it { is_expected.to include "\e[1m\e[36m#1234\e[0m \e[34mopened\e[0m Opened-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/11/05 2014/11/07" }
        it { is_expected.to include "\e[1m\e[36m#1236\e[0m \e[34mopened\e[0m Opened-issue2 \e[33m\e[0m \e[35mpipin     \e[0m 2014/11/06 2014/11/08" }
        it { is_expected.not_to include "\e[1m\e[36m#1235\e[0m \e[34mclosed\e[0m Closed-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/10/06 2014/10/08" }
      end

      context 'closed' do
        before do
          return_issues = issues.delete_if { |issue| issue['state'] == 'opened' }
          gitlab.stub(:fetch_json).and_return(return_issues)
          gitlab.list(state: 'closed')
        end

        it { sysout.length.should_not be_zero }
        it { syserr.length.should be_zero }
        it { is_expected.to include "\e[1m\e[36m#1235\e[0m \e[34mclosed\e[0m Closed-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/10/06 2014/10/08" }
        it { is_expected.not_to include "\e[1m\e[36m#1234\e[0m \e[34mopened\e[0m Opened-issue1 \e[33m\e[0m \e[35mjohn_smith\e[0m 2014/11/05 2014/11/07" }
        it { is_expected.not_to include "\e[1m\e[36m#1236\e[0m \e[34mopened\e[0m Opened-issue2 \e[33m\e[0m \e[35mpipin     \e[0m 2014/11/06 2014/11/08" }
      end
    end
  end
end
