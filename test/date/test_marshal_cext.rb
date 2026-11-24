# frozen_string_literal: true
require 'test/unit'
require 'date'
require_relative 'gen_marshal_cext'

# Verify the pure-Ruby Date/DateTime can load Marshal data produced by the C
# extension (date 3.5.1; the format is shared with 3.3.x/3.4.x), and that a
# pure-Ruby dump round-trips. See gen_marshal_cext.rb for the fixture.
class TestMarshalCext < Test::Unit::TestCase
  def attrs(d)
    a = [d.class, d.jd, d.start, d.to_s]
    a.concat([d.hour, d.min, d.sec, d.sec_fraction, d.offset]) if d.is_a?(DateTime)
    a
  end

  def test_loads_c_extension_marshal
    expected = MarshalCextFixture.objects
    loaded = Marshal.load(File.binread(MarshalCextFixture.fixture_path(__dir__)))
    assert_equal(expected.size, loaded.size)
    expected.zip(loaded).each_with_index do |(exp, got), i|
      assert_equal(attrs(exp), attrs(got), "object #{i} (#{exp.inspect})")
    end
  end

  def test_pure_ruby_round_trip
    MarshalCextFixture.objects.each do |d|
      got = Marshal.load(Marshal.dump(d))
      assert_equal(attrs(d), attrs(got), d.inspect)
    end
  end
end
