require "test_helper"
require "error_payload"
require "weather"

class ErrorPayloadTest < Minitest::Test
  def setup
    @local_time = Time.new(2026, 9, 28, 14, 30, 0, SVALBARD_OFFSET)
  end

  def raised(error_class = RuntimeError, message = "boom")
    raise error_class, message
  rescue => e
    e
  end

  def vars(exception)
    ErrorPayload.build(exception, local_time: @local_time).fetch("merge_variables")
  end

  def test_mode_is_error
    assert_equal "error", vars(raised)["mode"]
  end

  def test_names_the_error_class_and_message
    assert_equal "Weather::Error: Open-Meteo returned HTTP 503",
      vars(raised(Weather::Error, "Open-Meteo returned HTTP 503"))["error"]
  end

  def test_says_when_it_happened
    assert_equal "2026-09-28 14:30", vars(raised)["at"]
  end

  def test_says_where_without_leaking_absolute_paths
    where = vars(raised)["where"]

    assert_match(/\Aerror_payload_test\.rb:\d+\z/, where)
  end

  def test_where_is_unknown_for_an_exception_that_was_never_raised
    assert_equal "unknown", vars(RuntimeError.new("never raised"))["where"]
  end

  def test_long_messages_are_truncated
    message = vars(raised(RuntimeError, "x" * 1000))["error"]

    assert_equal "RuntimeError: #{"x" * (ErrorPayload::MAX_MESSAGE_LENGTH - 1)}…", message
  end

  def test_fits_the_webhook_limit_even_with_multibyte_messages
    body = ErrorPayload.build(raised(RuntimeError, "é" * 1000), local_time: @local_time)

    assert_operator body.to_json.bytesize, :<=, Payload::WEBHOOK_LIMIT_BYTES
  end
end
