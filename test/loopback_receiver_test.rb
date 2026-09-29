require "test_helper"
require "loopback_receiver"
require "net/http"

class LoopbackReceiverTest < Minitest::Test
  def setup
    WebMock.disable_net_connect!(allow_localhost: true)
    @receiver = LoopbackReceiver.new
  end

  def teardown
    @receiver.close
    WebMock.disable_net_connect!
  end

  def wait_in_background(**options)
    thread = Thread.new do
      Thread.current.report_on_exception = false
      @receiver.wait_for_code(expected_state: "expected", **options)
    end
    sleep 0.05
    thread
  end

  def visit(path)
    Net::HTTP.get_response(URI("#{@receiver.base_url}#{path}"))
  end

  def test_returns_the_code_from_the_redirect
    thread = wait_in_background
    visit("/oauth2callback?state=expected&code=the-code&scope=ignored")

    assert_equal "the-code", thread.value
  end

  def test_tells_the_browser_it_can_close_the_tab
    thread = wait_in_background
    response = visit("/oauth2callback?state=expected&code=the-code")
    thread.join

    assert_match(/close this tab/, response.body)
  end

  def test_ignores_requests_without_a_code_such_as_the_favicon
    thread = wait_in_background
    favicon = visit("/favicon.ico")
    visit("/oauth2callback?state=expected&code=the-code")

    assert_equal ["404", "the-code"], [favicon.code, thread.value]
  end

  def test_refuses_a_reply_with_the_wrong_state
    thread = wait_in_background
    visit("/oauth2callback?state=somebody-else&code=the-code")

    error = assert_raises(LoopbackReceiver::Error) { thread.value }

    assert_match(/state/, error.message)
  end

  def test_reports_an_error_from_google
    thread = wait_in_background
    visit("/oauth2callback?error=access_denied&state=expected")

    error = assert_raises(LoopbackReceiver::Error) { thread.value }

    assert_equal "Google returned an error: access_denied", error.message
  end

  def test_gives_up_after_the_timeout
    error = assert_raises(LoopbackReceiver::Error) { @receiver.wait_for_code(expected_state: "expected", timeout: 0.1) }

    assert_match(/timed out/, error.message)
  end

  def test_the_base_url_is_on_loopback_with_a_real_port
    assert_match(%r{\Ahttp://127\.0\.0\.1:\d+\z}, @receiver.base_url)
  end
end
