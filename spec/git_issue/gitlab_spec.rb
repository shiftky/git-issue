require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe GitIssue::Gitlab do
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

end
