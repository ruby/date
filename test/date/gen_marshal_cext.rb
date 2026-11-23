# frozen_string_literal: true
#
# Generator for the Marshal compatibility fixture used by
# test_marshal_cext.rb. It serialises a spread of Date and DateTime objects
# and writes the bytes to test/date/marshal_cext.dump. Regenerate it with a
# Ruby whose +date+ library is the C extension (the reference whose on-disk
# format the pure-Ruby library must keep reading):
#
#   ruby test/date/gen_marshal_cext.rb
#
# The Date marshal format (the marshal_dump array) has been identical across
# date 3.3.x, 3.4.x and 3.5.x, so the fixture also stands in for data written
# by those older gems.

require 'date'

module MarshalCextFixture
  module_function

  # The exact objects serialised into the fixture. The test rebuilds this same
  # list with the pure-Ruby library and checks each loaded object against it.
  def objects
    [
      Date.new(2001, 2, 3),
      Date.new(2001, 2, 3, Date::JULIAN),
      Date.new(2001, 2, 3, Date::GREGORIAN),
      Date.new(-5, 1, 1),
      Date.jd(2451944),
      Date.new(1000, 1, 1),                       # before the reform (Julian)
      DateTime.new(2001, 2, 3, 4, 5, 6),
      DateTime.new(2001, 2, 3, 4, 5, 6, '+07:30'),
      DateTime.new(2001, 2, 3, 4, 5, Rational(6789, 1000), '-05:00'),
    ]
  end

  def fixture_path(dir = __dir__)
    File.join(dir, 'marshal_cext.dump')
  end

  def generate(dir = __dir__)
    File.binwrite(fixture_path(dir), Marshal.dump(objects))
  end
end

MarshalCextFixture.generate if $PROGRAM_NAME == __FILE__
