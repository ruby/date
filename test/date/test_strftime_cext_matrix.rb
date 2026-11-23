# frozen_string_literal: true
require 'test/unit'
require 'date'
require 'zlib'
require_relative 'gen_strftime_cext_matrix'

# Exhaustive comparison of the pure-Ruby Date#strftime / DateTime#strftime
# against the C extension, over every conversion specifier combined with every
# flag combination, width, colon count and locale modifier (see
# gen_strftime_cext_matrix.rb). The expected results were produced from the C
# extension (date 3.5.1) and stored in the committed fixtures; regenerate them
# with that generator under a C-extension Ruby if the reference ever changes.
class TestStrftimeCextMatrix < Test::Unit::TestCase
  StrftimeCextMatrix::REFERENCE.each_key do |key|
    define_method(:"test_strftime_matches_c_extension_#{key}") do
      obj  = StrftimeCextMatrix::REFERENCE[key]
      path = StrftimeCextMatrix.fixture_path(__dir__, key)
      Zlib::GzipReader.open(path) do |gz|
        gz.each_line do |line|
          fmt, expected = line.chomp.split("\t", 2)
          assert_equal(expected, StrftimeCextMatrix.encode(obj, fmt),
                       "#{key}.strftime(#{fmt.inspect})")
        end
      end
    end
  end
end
