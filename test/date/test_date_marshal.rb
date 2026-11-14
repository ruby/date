# frozen_string_literal: true
require 'test/unit'
require 'date'

class TestDateMarshal < Test::Unit::TestCase

  def test_marshal
    d = Date.new
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)

    d = Date.today
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)

    d = DateTime.now
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)

    d = Date.today
    a = d.marshal_dump
    d.freeze
    assert(d.frozen?)
    expected_error = defined?(FrozenError) ? FrozenError : RuntimeError
    assert_raise(expected_error){d.marshal_load(a)}

    d = DateTime.now
    a = d.marshal_dump
    d.freeze
    assert(d.frozen?)
    expected_error = defined?(FrozenError) ? FrozenError : RuntimeError
    assert_raise(expected_error){d.marshal_load(a)}

    d = assert_deprecated_warn(/fractional day/) { Date.new + 1/2r + 2304/65437r/86400 }
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)
  end

  def test_memsize
    require 'objspace'
    t = DateTime.new(2018, 11, 13)
    size = ObjectSpace.memsize_of(t)
    t2 = Marshal.load(Marshal.dump(t))
    assert_equal(t, t2)
    assert_equal(size, ObjectSpace.memsize_of(t2), "not reallocated but memsize changed")
  end

  def test_marshal_load_invalid_types
    d = Date.allocate
    assert_raise(TypeError) { d.marshal_load([1.5, 0, 0, 0, 0, 0.0]) }
    assert_raise(TypeError) { d.marshal_load([Rational(1, 2), 0, 0, 0, 0, 0.0]) }
    assert_raise(TypeError) { d.marshal_load(["1", 0, 0, 0, 0, 0.0]) }
    assert_raise(TypeError) { d.marshal_load([nil, 0, 0, 0, 0, 0.0]) }
    assert_raise(TypeError) { d.marshal_load([0, 0, 0, 1.5, 0, 0.0]) }
    assert_raise(TypeError) { d.marshal_load([0, 0, 0, "0", 0, 0.0]) }
    assert_raise(TypeError) { d.marshal_load([0, 0, 0, Date.new(2000), 0, 0.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 0, 86400, 0, 0, 0.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 0, 0, -1, 0, 0.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 0, 0, 1_000_000_000, 0, 0.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, -2, 0, 0, 0, 2299161.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 213447718, 0, 0, 0, 2299161.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 0, 0, 0, 86401, 2299161.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 0, 0, 0, 0, 0.0]) }
    assert_raise(Date::Error) { d.marshal_load([0, 0, 0, 0, 0, Float::NAN]) }
    assert_equal(Date.new(2000, 1, 1), d.marshal_load([0, 2451545, 0, 0, 0, 2299161.0]))
    dt = DateTime.allocate.marshal_load([0, 2451545, 0, Rational(1_000_000_000, 3), 0, 2299161.0])
    assert_equal(Rational(1, 3), dt.sec_fraction)
    assert_equal(Date.new(10**20), Date.allocate.marshal_load(Date.new(10**20).marshal_dump))
    [
      DateTime.new(-4712, 1, 1, 0, 0, 0, "+12:00"),
      DateTime.jd(213447716, 23, 59, 59, "-12:00"),
      DateTime.new(2001, 2, 3, 4, 5, 6, "+24:00"),
      Date.new(2001, 2, 3, Date::GREGORIAN),
      Date.new(2001, 2, 3, Date::JULIAN),
    ].each do |x|
      assert_equal(x, x.class.allocate.marshal_load(x.marshal_dump))
    end
  end

  def test_marshal_load_yaml_marshalable
    require "yaml"
    doc = "--- !ruby/marshalable:Date\n0: 0\n0: !ruby/marshalable:Date {1.5: 0, 0: 0, 0: 0.0}\n0: 0.0\n"
    assert_raise(TypeError) { YAML.safe_load(doc, permitted_classes: [Date]) }
  end
end
