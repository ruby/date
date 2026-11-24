# frozen_string_literal: true
require 'test/unit'
require 'date'

class TestDateNew < Test::Unit::TestCase

  def test_ordinal_and_calendar_start_paths
    assert_equal(Date.new(2001, 3, 1), Date.ordinal(2001, 60))
    assert_equal(2, Date.new(2001, 2, 3, Date::JULIAN).month)
    assert_equal(2, Date.new(2001, 2, 3, Date::GREGORIAN).month)
    assert_equal(2086308, Date.new(1000, 1, 1).jd)  # before the reform -> Julian
  end

  def test_datetime_new_offset_type_errors
    assert_raise(TypeError) { DateTime.new(2001, 1, 1, 0, 0, 0, Object.new) }
    assert_raise(TypeError) { DateTime.new(nil) }
  end

  def test_valid_and_leap_predicates_true
    # Happy paths for the predicate class methods.
    assert_equal(true, Date.valid_civil?(2001, 2, 3))
    assert_equal(true, Date.valid_ordinal?(2001, 60))
    assert_equal(true, Date.gregorian_leap?(2000))
    assert_equal(true, Date.julian_leap?(1900))
    assert_equal(true, Date.leap?(2000))
  end

  def test_jd
    d = Date.jd
    dt = DateTime.jd
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    assert_equal([-4712, 1, 1], [dt.year, dt.mon, dt.mday])
    assert_equal([0, 0, 0], [dt.hour, dt.min, dt.sec])

    d2 = Date.jd
    dt2 = DateTime.jd
    assert_equal(d, d2)
    assert_equal(dt, dt2)

    d = Date.jd(0)
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    d = DateTime.jd(0, 0,0,0, 0)
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.jd(0, 0,0,0, '+0900')
    assert_equal([-4712, 1, 1, 0, 0, 0, 9.to_r/24],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_jd__ex
    assert_raise(Date::Error) do
      DateTime.jd(0, 23,59,60,0)
    end
  end

  def test_valid_with_invalid_types
    o = Object.new
    assert_equal(false, Date.valid_jd?(o))
    assert_equal(false, Date.valid_civil?(o, 1, 1))
    assert_equal(false, Date.valid_civil?(1, o, 1))
    assert_equal(false, Date.valid_civil?(1, 1, o))
    assert_equal(false, Date.valid_ordinal?(o, 1))
    assert_equal(false, Date.valid_ordinal?(1, o))
    assert_equal(false, Date.valid_commercial?(o, 1, 1))
    assert_equal(false, Date.valid_commercial?(1, o, 1))
    assert_equal(false, Date.valid_commercial?(1, 1, o))
  end

  def test_invalid_types
    o = Object.new
    assert_raise(TypeError) { Date.julian_leap?(o) }
    assert_raise(TypeError) { Date.gregorian_leap?(o) }
    assert_raise(TypeError) { Date.jd(o) }
    assert_raise(TypeError) { Date.new(o) }
    assert_raise(TypeError) { Date.new(1, o) }
    assert_raise(TypeError) { Date.new(1, 1, o) }
    assert_raise(TypeError) { Date.ordinal(o) }
    assert_raise(TypeError) { Date.ordinal(1, o) }
    assert_raise(TypeError) { Date.commercial(o) }
    assert_raise(TypeError) { Date.commercial(1, o) }
    assert_raise(TypeError) { Date.commercial(1, 1, o) }

    assert_raise(TypeError) { DateTime.jd(o) }
    assert_raise(TypeError) { DateTime.jd(1, o) }
    assert_raise(TypeError) { DateTime.jd(1, 1, o) }
    assert_raise(TypeError) { DateTime.jd(1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.new(o) }
    assert_raise(TypeError) { DateTime.new(1, o) }
    assert_raise(TypeError) { DateTime.new(1, 1, o) }
    assert_raise(TypeError) { DateTime.new(1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.new(1, 1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.new(1, 1, 1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.ordinal(o) }
    assert_raise(TypeError) { DateTime.ordinal(1, o) }
    assert_raise(TypeError) { DateTime.ordinal(1, 1, o) }
    assert_raise(TypeError) { DateTime.ordinal(1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.ordinal(1, 1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.commercial(o) }
    assert_raise(TypeError) { DateTime.commercial(1, o) }
    assert_raise(TypeError) { DateTime.commercial(1, 1, o) }
    assert_raise(TypeError) { DateTime.commercial(1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.commercial(1, 1, 1, 1, o) }
    assert_raise(TypeError) { DateTime.commercial(1, 1, 1, 1, 1, o) }
  end

  def test_ordinal
    d = Date.ordinal
    dt = DateTime.ordinal
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    assert_equal([-4712, 1, 1], [dt.year, dt.mon, dt.mday])
    assert_equal([0, 0, 0], [dt.hour, dt.min, dt.sec])

    d2 = Date.ordinal
    dt2 = DateTime.ordinal
    assert_equal(d, d2)
    assert_equal(dt, dt2)

    d = Date.ordinal(-4712,1)
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])

    d = Date.ordinal(-4712,1.0)
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])

    d = DateTime.ordinal(-4712,1, 0,0,0, 0)
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.ordinal(-4712,1, 0,0,0, '+0900')
    assert_equal([-4712, 1, 1, 0, 0, 0, 9.to_r/24],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_ordinal__neg
    d = Date.ordinal(-1,-1)
    assert_equal([-1, 365], [d.year, d.yday])

    d = DateTime.ordinal(-1,-1, -1,-1,-1, 0)
    assert_equal([-1, 365, 23, 59, 59, 0],
		 [d.year, d.yday, d.hour, d.min, d.sec, d.offset])
  end

  def test_ordinal__ex
    assert_raise(Date::Error) do
      Date.ordinal(2001,366)
    end
    assert_raise(Date::Error) do
      DateTime.ordinal(2001,365, 23,59,60, 0)
    end
  end

  def test_civil
    d = Date.civil
    dt = DateTime.civil
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    assert_equal([-4712, 1, 1], [dt.year, dt.mon, dt.mday])
    assert_equal([0, 0, 0], [dt.hour, dt.min, dt.sec])

    d2 = Date.civil
    dt2 = DateTime.civil
    assert_equal(d, d2)
    assert_equal(dt, dt2)

    d = Date.civil(-4712,1,1)
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])

    d = Date.civil(-4712,1,1.0)
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])

    d = DateTime.civil(-4712,1,1, 0,0,0, 0)
    assert_equal([-4712, 1, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.civil(-4712,1,1, 0,0,0, '+0900')
    assert_equal([-4712, 1, 1, 0, 0, 0, 9.to_r/24],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])


    d = DateTime.civil(2001,2,3 + 1.to_r/2)
    assert_equal([2001, 2, 3, 12, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.civil(2001,2,3, 4 + 1.to_r/2)
    assert_equal([2001, 2, 3, 4, 30, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.civil(2001,2,3, 4,5 + 1.to_r/2)
    assert_equal([2001, 2, 3, 4, 5, 30, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.civil(2001,2,3, 4,5,6 + 1.to_r/2)
    assert_equal([2001, 2, 3, 4, 5, 6, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    assert_equal(1.to_r/2, d.sec_fraction)

    d = DateTime.civil(2001, 2)
    assert_equal([2001, 2, 1, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_civil__neg
    d = Date.civil(-1,-1,-1)
    assert_equal([-1, 12, 31], [d.year, d.mon, d.mday])

    d = DateTime.civil(-1,-1,-1, -1,-1,-1, 0)
    assert_equal([-1, 12, 31, 23, 59, 59, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_civil__ex
    assert_raise(Date::Error) do
      Date.civil(2001,2,29)
    end
    assert_raise(Date::Error) do
      DateTime.civil(2001,2,28, 23,59,60, 0)
    end
    assert_raise(Date::Error) do
      DateTime.civil(2001,2,28, 24,59,59, 0)
    end
  end

  def test_civil__offset
    d = DateTime.civil(2001,2,3, 0,0,0, Rational(1, 1))
    assert_equal(1.to_r, d.offset)
    d = DateTime.civil(2001,2,3, 0,0,0, Rational(-1, 1))
    assert_equal(-1.to_r, d.offset)

    # An out-of-range offset is ignored, as it is for the equivalent Integer.
    assert_warning(/invalid offset/) do
      d = DateTime.civil(2001,2,3, 0,0,0, 2)
    end
    assert_equal(0, d.offset)
    assert_warning(/invalid offset/) do
      d = DateTime.civil(2001,2,3, 0,0,0, Rational(2, 1))
    end
    assert_equal(0, d.offset)
    assert_warning(/invalid offset/) do
      d = DateTime.civil(2001,2,3, 0,0,0, Rational(49710, 1))
    end
    assert_equal(0, d.offset)
  end

  def test_civil__reform
    d = Date.jd(Date::ENGLAND, Date::ENGLAND)
    dt = DateTime.jd(Date::ENGLAND, 0,0,0,0, Date::ENGLAND)
    assert_equal([1752, 9, 14], [d.year, d.mon, d.mday])
    assert_equal([1752, 9, 14], [dt.year, dt.mon, dt.mday])
    d -= 1
    dt -= 1
    assert_equal([1752, 9, 2], [d.year, d.mon, d.mday])
    assert_equal([1752, 9, 2], [dt.year, dt.mon, dt.mday])

    d = Date.jd(Date::ITALY, Date::ITALY)
    dt = DateTime.jd(Date::ITALY, 0,0,0,0, Date::ITALY)
    assert_equal([1582, 10, 15], [d.year, d.mon, d.mday])
    assert_equal([1582, 10, 15], [dt.year, dt.mon, dt.mday])
    d -= 1
    dt -= 1
    assert_equal([1582, 10, 4], [d.year, d.mon, d.mday])
    assert_equal([1582, 10, 4], [dt.year, dt.mon, dt.mday])

    d = Date.civil(1582,10,-17)
    assert_equal([1582, 10, 15], [d.year, d.mon, d.mday])
    d = Date.civil(1582,10,-18)
    assert_equal([1582, 10, 4], [d.year, d.mon, d.mday])
    d = DateTime.civil(1582,10,-21)
    assert_equal([1582, 10, 1], [d.year, d.mon, d.mday])
    assert_equal(false, Date.valid_civil?(1582,10,-22))
  end

  def test_civil__reform_negative_mday_custom_cutover
    # A custom Gregorian cutover whose reform gap falls near the end of the
    # month: the last existing day of the month must be found by scanning down
    # (as the C extension's c_find_ldom does), not by taking the next month's
    # first day minus one. sg = 1900-02-05 (Gregorian) leaves 1900-01-23 as the
    # last day of January 1900.
    sg = Date.new(1900, 2, 5, Date::GREGORIAN).jd
    assert_equal([1900, 1, 23], Date.new(1900, 1, -1, sg).then { |d| [d.year, d.mon, d.mday] })
    assert_equal([1900, 1, 10], Date.new(1900, 1, -14, sg).then { |d| [d.year, d.mon, d.mday] })
    assert_equal(true, Date.valid_civil?(1900, 1, -1, sg))
  end

  def test_invalid_start
    d = nil
    assert_warning(/invalid start/) do
      d = Date.jd(0, 0)
    end
    assert_equal([-4712, 1, 1, Date::ITALY],
		 [d.year, d.mon, d.mday, d.start])
    assert_warning(/invalid start/) do
      d = Date.civil(2001,2,3, 3000000)
    end
    assert_equal([2451944, Date::ITALY], [d.jd, d.start])
    assert_warning(/invalid start/) do
      d = Date.civil(2001,2,3).new_start(1)
    end
    assert_equal(Date::ITALY, d.start)
  end

  def test_invalid_start_boundaries
    # The valid range for a finite start matches the C extension:
    # 2298874 (ns 1582-01-01) .. 2426355 (os 1930-12-31), inclusive.
    # Infinities are valid; NaN and any finite value outside the range are
    # ignored (warning + fallback to ITALY).
    assert_warning('') do
      assert_equal(2298874, Date.jd(0, 2298874).start)
      assert_equal(2426355, Date.jd(0, 2426355).start)
      assert_equal(Date::ENGLAND, Date.jd(0, Date::ENGLAND).start)
      assert_equal(Float::INFINITY, Date.jd(0, Date::JULIAN).start)
      assert_equal(-Float::INFINITY, Date.jd(0, Date::GREGORIAN).start)
    end
    assert_warning(/invalid start/) do
      assert_equal(Date::ITALY, Date.jd(0, 2298873).start)
    end
    assert_warning(/invalid start/) do
      assert_equal(Date::ITALY, Date.jd(0, 2426356).start)
    end
    assert_warning(/invalid start/) do
      assert_equal(Date::ITALY, Date.jd(0, Float::NAN).start)
    end
    # new_start shares the same validation.
    assert_warning('') do
      assert_equal(Date::ENGLAND, Date.new(2001,2,3).new_start(Date::ENGLAND).start)
    end
    assert_warning(/invalid start/) do
      assert_equal(Date::ITALY, Date.new(2001,2,3).new_start(0).start)
    end
  end

  def test_non_numeric_start_raises
    # A non-numeric start is a TypeError, not a silent fallback (the C
    # extension's NUM2DBL). This holds across the constructors, new_start, the
    # parse/strptime entry points, and the validity predicates.
    assert_raise(TypeError) { Date.new(2001, 1, 1, nil) }
    assert_raise(TypeError) { Date.jd(1, "x") }
    assert_raise(TypeError) { Date.ordinal(2001, 34, nil) }
    assert_raise(TypeError) { Date.commercial(2001, 5, 3, nil) }
    assert_raise(TypeError) { Date.new(2001, 1, 1).new_start(nil) }
    assert_raise(TypeError) { Date.parse("2001-02-03", true, nil) }
    assert_raise(TypeError) { Date.strptime("2001-02-03", "%F", nil) }
    assert_raise(TypeError) { Date.valid_civil?(2001, 2, 3, nil) }
    assert_raise(TypeError) { Date.valid_ordinal?(2001, 34, nil) }
    assert_raise(TypeError) { Date.valid_commercial?(2001, 5, 3, nil) }
    assert_raise(TypeError) { Date.valid_jd?(1, nil) }
    assert_raise(TypeError) { DateTime.new(2001, 1, 1, 0, 0, 0, 0, nil) }

    # An out-of-range numeric start is still only a warning + fallback, so the
    # predicate holds (clamped to ITALY).
    assert_warning(/invalid start/) do
      assert_equal(true, Date.valid_civil?(2001, 2, 3, 3000000))
    end

    # The NUM2DBL error wording follows the C extension: nil/true/false and the
    # builtin non-numerics report "no implicit conversion of <name> into
    # Float", other objects "can't convert <Class> into Float".
    assert_raise_with_message(TypeError, "no implicit conversion of nil into Float") { Date.new(2001, 1, 1, nil) }
    assert_raise_with_message(TypeError, "no implicit conversion of true into Float") { Date.new(2001, 1, 1, true) }
    assert_raise_with_message(TypeError, "no implicit conversion of false into Float") { Date.new(2001, 1, 1, false) }
    assert_raise_with_message(TypeError, "no implicit conversion of String into Float") { Date.new(2001, 1, 1, "x") }
    assert_raise_with_message(TypeError, "no implicit conversion of Symbol into Float") { Date.new(2001, 1, 1, :x) }
    assert_raise_with_message(TypeError, "can't convert Object into Float") { Date.new(2001, 1, 1, Object.new) }

    # A non-numeric object that defines #to_f is accepted via #to_f, as the C
    # extension does.
    to_f_obj = Object.new
    def to_f_obj.to_f; Date::ITALY.to_f; end
    assert_equal(Date::ITALY, Date.new(2001, 1, 1, to_f_obj).start)
  end

  def test_invalid_start_datetime
    # DateTime shares Date's start validation across all of its constructors:
    # an invalid start is ignored (warning + fallback to ITALY), and the
    # calendar math uses the corrected start.
    assert_warning(/invalid start/) do
      d = DateTime.jd(0, 0, 0, 0, 0, 0)
      assert_equal(Date::ITALY, d.start)
    end
    assert_warning(/invalid start/) do
      # With the raw start the civil fast path would pick the Julian jd; the
      # corrected ITALY start must yield the Gregorian jd 2451944.
      d = DateTime.civil(2001, 2, 3, 0, 0, 0, 0, 3000000)
      assert_equal([2451944, Date::ITALY], [d.jd, d.start])
    end
    assert_warning(/invalid start/) do
      d = DateTime.new(2001, 2, 3).new_start(1)
      assert_equal(Date::ITALY, d.start)
    end
    assert_warning('') do
      assert_equal(Date::ENGLAND, DateTime.jd(0, 0, 0, 0, 0, Date::ENGLAND).start)
      assert_equal(Float::INFINITY, DateTime.jd(0, 0, 0, 0, 0, Date::JULIAN).start)
    end
  end

  def test_commercial
    d = Date.commercial
    dt = DateTime.commercial
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    assert_equal([-4712, 1, 1], [dt.year, dt.mon, dt.mday])
    assert_equal([0, 0, 0], [dt.hour, dt.min, dt.sec])

    d2 = Date.commercial
    dt2 = DateTime.commercial
    assert_equal(d, d2)
    assert_equal(dt, dt2)

    d = Date.commercial(1582,40,5)
    assert_equal([1582, 10, 15], [d.year, d.mon, d.mday])

    d = Date.commercial(1582,40,5.0)
    assert_equal([1582, 10, 15], [d.year, d.mon, d.mday])

    d = DateTime.commercial(1582,40,5, 0,0,0, 0)
    assert_equal([1582, 10, 15, 0, 0, 0, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
    d = DateTime.commercial(1582,40,5, 0,0,0, '+0900')
    assert_equal([1582, 10, 15, 0, 0, 0, 9.to_r/24],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_commercial__neg
    d = Date.commercial(1998,-1,-1)
    assert_equal([1999, 1, 3], [d.year, d.mon, d.mday])

    d = DateTime.commercial(1998,-1,-1, -1,-1,-1, 0)
    assert_equal([1999, 1, 3, 23, 59, 59, 0],
		 [d.year, d.mon, d.mday, d.hour, d.min, d.sec, d.offset])
  end

  def test_commercial__ex
    assert_raise(Date::Error) do
      Date.commercial(1997,53,1)
    end
    assert_raise(Date::Error) do
      DateTime.commercial(1997,52,1, 23,59,60, 0)
    end
  end

  def test_commercial_p
    assert_equal(false, Date.valid_commercial?(2024, -53, 1))
    assert_equal(false, Date.valid_commercial?(2024, -1227133565, 1))
  end

  def test_weeknum
    d = Date.weeknum
    dt = DateTime.weeknum
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    assert_equal([-4712, 1, 1], [dt.year, dt.mon, dt.mday])
    assert_equal([0, 0, 0], [dt.hour, dt.min, dt.sec])

    d = Date.weeknum(2002,11,4, 0)
    assert_equal(2452355, d.jd)

    d = DateTime.weeknum(2002,11,4, 0, 11,22,33)
    assert_equal(2452355, d.jd)
    assert_equal([11,22,33], [d.hour, d.min, d.sec])

    assert_raise(Date::Error) do
      Date.weeknum(1999,53,0, 0)
    end
    assert_raise(Date::Error) do
      Date.weeknum(1999,-53,-1, 0)
    end
  end if Date.respond_to?(:weeknum, true)

  def test_nth_kday
    d = Date.nth_kday
    dt = DateTime.nth_kday
    assert_equal([-4712, 1, 1], [d.year, d.mon, d.mday])
    assert_equal([-4712, 1, 1], [dt.year, dt.mon, dt.mday])
    assert_equal([0, 0, 0], [dt.hour, dt.min, dt.sec])

    d = Date.nth_kday(1992,2, 5,6)
    assert_equal(2448682, d.jd)

    d = DateTime.nth_kday(1992,2, 5,6, 11,22,33)
    assert_equal(2448682, d.jd)
    assert_equal([11,22,33], [d.hour, d.min, d.sec])

    assert_raise(Date::Error) do
      Date.nth_kday(2006,5, 5,0)
    end
    assert_raise(Date::Error) do
      Date.nth_kday(2006,5, -5,0)
    end
  end if Date.respond_to?(:nth_kday, true)

  def test_today
    z = Time.now
    d = Date.today
    t = Time.now
    t2 = Time.utc(t.year, t.mon, t.mday)
    t3 = Time.utc(d.year, d.mon, d.mday)
    assert_in_delta(t2, t3, t - z + 2)

    assert_equal(false, DateTime.respond_to?(:today))
  end

  def test_now
    assert_equal(false, Date.respond_to?(:now))

    z = Time.now
    d = DateTime.now
    t = Time.now
    t2 = Time.local(d.year, d.mon, d.mday, d.hour, d.min, d.sec)
    assert_in_delta(t, t2, t - z + 2)
  end

  def test_memsize
    require 'objspace'
    t = DateTime.now
    size = ObjectSpace.memsize_of(t)
    t.__send__(:initialize_copy, Date.today)
    assert_instance_of(DateTime, t)
    assert_equal(size, ObjectSpace.memsize_of(t), "not reallocated but memsize changed")
  end
end
