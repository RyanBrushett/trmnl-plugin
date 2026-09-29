require "googleauth"
require "googleauth/token_store"
require "securerandom"
require "calendar_source"

# The one-off Google consent: build the URL to send the browser to, then swap
# the code Google redirects back with for a refresh token. Uses PKCE and a
# random state, and keeps nothing on disk.
class ConsentFlow
  # The library only ships file and Redis stores, and a refresh token should
  # not be written to disk by accident.
  class MemoryTokenStore < Google::Auth::TokenStore
    def initialize
      @tokens = {}
    end

    def load(id) = @tokens[id]

    def store(id, token)
      @tokens[id] = token
    end

    def delete(id) = @tokens.delete(id)
  end

  CALLBACK_PATH = "/oauth2callback"
  USER_ID = "me"

  attr_reader :state

  def initialize(client_id:, client_secret:, base_url:)
    @base_url = base_url
    @state = SecureRandom.hex(16)
    @authorizer = Google::Auth::UserAuthorizer.new(
      Google::Auth::ClientId.new(client_id, client_secret),
      CalendarSource::SCOPE,
      MemoryTokenStore.new,
      callback_uri: CALLBACK_PATH,
      code_verifier: Google::Auth::UserAuthorizer.generate_code_verifier
    )
  end

  def authorization_url
    @authorizer.get_authorization_url(base_url: @base_url, state: @state)
  end

  def refresh_token_for(code)
    @authorizer.get_credentials_from_code(user_id: USER_ID, code: code, base_url: @base_url).refresh_token
  end
end
