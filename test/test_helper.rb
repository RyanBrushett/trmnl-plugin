require "minitest/autorun"
require "webmock/minitest"

ENV["TZ"] = "Arctic/Longyearbyen"

# That zone in September. It is +01:00 in winter, and Time.new only takes
# fixed offsets, not zone names.
SVALBARD_OFFSET = "+02:00".freeze

def fixture(name)
  File.read(File.join(__dir__, "fixtures", name))
end
