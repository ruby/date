# frozen_string_literal: true

class Date
  include Comparable

  Error = Class.new(ArgumentError)

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  class << self
    # Same as Date.new.
    def civil(year = -4712, month = 1, day = 1, start = DEFAULT_SG)
      unless (Integer === (year + month + day) rescue false) && month >= 1 && month <= 12
        return new(year, month, day, start)
      end
      if day >= 1 && day <= 28
        gy = month > 2 ? year : year - 1
        gjd_base = (1461 * (gy + 4716)) / 4 + GJD_MONTH_OFFSET[month] + day
        a = gy / 100
        jd_julian = gjd_base - 1524
        gjd = jd_julian + 2 - a + a / 4
        obj = allocate
        obj.__send__(:_init_from_jd, gjd >= start ? gjd : jd_julian, start)
        return obj
      elsif day >= -31
        dim = if month == 2
          if start == Float::INFINITY
            year % 4 == 0 ? 29 : 28
          else
            (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
          end
        else
          DAYS_IN_MONTH_GREGORIAN[month]
        end
        d = day < 0 ? day + dim + 1 : day
        if d >= 1 && d <= dim
          gy = month > 2 ? year : year - 1
          gjd_base = (1461 * (gy + 4716)) / 4 + GJD_MONTH_OFFSET[month] + d
          a = gy / 100
          jd_julian = gjd_base - 1524
          gjd = jd_julian + 2 - a + a / 4
          obj = allocate
          obj.__send__(:_init_from_jd, gjd >= start ? gjd : jd_julian, start)
          return obj
        end
      end
      new(year, month, day, start)
    end
    # call-seq:
    #   Date.valid_civil?(year, month, mday, start = Date::ITALY) -> true or false
    #
    # Returns +true+ if the arguments define a valid ordinal date,
    # +false+ otherwise:
    #
    #   Date.valid_date?(2001, 2, 3)  # => true
    #   Date.valid_date?(2001, 2, 29) # => false
    #   Date.valid_date?(2001, 2, -1) # => true
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.jd, Date.new.
    def valid_civil?(year, month, day, start = DEFAULT_SG)
      return false unless year.is_a?(Numeric) && month.is_a?(Numeric) && day.is_a?(Numeric)
      !!internal_valid_civil?(year, month, day, start)
    end
    alias_method :valid_date?, :valid_civil?

    # call-seq:
    #   Date.jd(jd = 0, start = Date::ITALY) -> date
    #
    # Returns a new \Date object formed from the arguments:
    #
    #   Date.jd(2451944).to_s # => "2001-02-03"
    #   Date.jd(2451945).to_s # => "2001-02-04"
    #   Date.jd(0).to_s       # => "-4712-01-01"
    #
    # The returned date is:
    #
    # - Gregorian, if the argument is greater than or equal to +start+:
    #
    #     Date::ITALY                         # => 2299161
    #     Date.jd(Date::ITALY).gregorian?     # => true
    #     Date.jd(Date::ITALY + 1).gregorian? # => true
    #
    # - Julian, otherwise
    #
    #     Date.jd(Date::ITALY - 1).julian?    # => true
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.new.
    def jd(jd = 0, start = DEFAULT_SG)
      jd = Integer(jd)
      obj = allocate
      obj.__send__(:_init_from_jd, jd, start)
      obj
    end

    # call-seq:
    #   Date.valid_jd?(jd, start = Date::ITALY) -> true
    #
    # Implemented for compatibility;
    # returns +true+ unless +jd+ is invalid (i.e., not a Numeric).
    #
    #   Date.valid_jd?(2451944) # => true
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.jd.
    def valid_jd?(jd, _start = DEFAULT_SG)
      jd.is_a?(Numeric)
    end

    # call-seq:
    #   Date.gregorian_leap?(year) -> true or false
    #
    # Returns +true+ if the given year is a leap year
    # in the {proleptic Gregorian calendar}[https://en.wikipedia.org/wiki/Proleptic_Gregorian_calendar], +false+ otherwise:
    #
    #   Date.gregorian_leap?(2000) # => true
    #   Date.gregorian_leap?(2001) # => false
    #
    # Related: Date.julian_leap?.
    def gregorian_leap?(year)
      raise TypeError, "expected numeric" unless year.is_a?(Numeric)
      internal_gregorian_leap?(year)
    end
    alias_method :leap?, :gregorian_leap?

    # call-seq:
    #   Date.julian_leap?(year) -> true or false
    #
    # Returns +true+ if the given year is a leap year
    # in the {proleptic Julian calendar}[https://en.wikipedia.org/wiki/Proleptic_Julian_calendar], +false+ otherwise:
    #
    #   Date.julian_leap?(1900) # => true
    #   Date.julian_leap?(1901) # => false
    #
    # Related: Date.gregorian_leap?.
    def julian_leap?(year)
      raise TypeError, "expected numeric" unless year.is_a?(Numeric)
      internal_julian_leap?(year)
    end

    # call-seq:
    #   Date.ordinal(year = -4712, yday = 1, start = Date::ITALY) -> date
    #
    # Returns a new \Date object formed fom the arguments.
    #
    # With no arguments, returns the date for January 1, -4712:
    #
    #   Date.ordinal.to_s # => "-4712-01-01"
    #
    # With argument +year+, returns the date for January 1 of that year:
    #
    #   Date.ordinal(2001).to_s  # => "2001-01-01"
    #   Date.ordinal(-2001).to_s # => "-2001-01-01"
    #
    # With positive argument +yday+ == +n+,
    # returns the date for the +nth+ day of the given year:
    #
    #   Date.ordinal(2001, 14).to_s # => "2001-01-14"
    #
    # With negative argument +yday+, counts backward from the end of the year:
    #
    #   Date.ordinal(2001, -14).to_s # => "2001-12-18"
    #
    # Raises an exception if +yday+ is zero or out of range.
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.jd, Date.new.
    def ordinal(year = -4712, yday = 1, start = DEFAULT_SG)
      if Integer === year && Integer === yday && yday >= 1 && yday <= 365
        gy = year - 1
        gjd_base = (1461 * (gy + 4716)) / 4 + 429  # GJD_MONTH_OFFSET[1] + 1
        a = gy / 100
        gjd = gjd_base - 1524 + 2 - a + a / 4
        jd1 = gjd >= start ? gjd : gjd_base - 1524
        obj = allocate
        obj.__send__(:_init_from_jd, jd1 + yday - 1, start)
        return obj
      end
      year = Integer(year)
      yday = Integer(yday)
      jd = internal_valid_ordinal?(year, yday, start)
      raise Date::Error, "invalid date" unless jd
      _new_from_jd(jd, start)
    end

    # call-seq:
    #   Date.valid_ordinal?(year, yday, start = Date::ITALY) -> true or false
    #
    # Returns +true+ if the arguments define a valid ordinal date,
    # +false+ otherwise:
    #
    #   Date.valid_ordinal?(2001, 34)  # => true
    #   Date.valid_ordinal?(2001, 366) # => false
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.jd, Date.ordinal.
    def valid_ordinal?(year, day, start = DEFAULT_SG)
      return false unless year.is_a?(Numeric) && day.is_a?(Numeric)
      !!internal_valid_ordinal?(year, day, start)
    end

    # call-seq:
    #   Date.commercial(cwyear = -4712, cweek = 1, cwday = 1, start = Date::ITALY) -> date
    #
    # Returns a new \Date object constructed from the arguments.
    #
    # Argument +cwyear+ gives the year, and should be an integer.
    #
    # Argument +cweek+ gives the index of the week within the year,
    # and should be in range (1..53) or (-53..-1);
    # in some years, 53 or -53 will be out-of-range;
    # if negative, counts backward from the end of the year:
    #
    #   Date.commercial(2022, 1, 1).to_s  # => "2022-01-03"
    #   Date.commercial(2022, 52, 1).to_s # => "2022-12-26"
    #
    # Argument +cwday+ gives the indes of the weekday within the week,
    # and should be in range (1..7) or (-7..-1);
    # 1 or -7 is Monday;
    # if negative, counts backward from the end of the week:
    #
    #   Date.commercial(2022, 1, 1).to_s  # => "2022-01-03"
    #   Date.commercial(2022, 1, -7).to_s # => "2022-01-03"
    #
    # When +cweek+ is 1:
    #
    # - If January 1 is a Friday, Saturday, or Sunday,
    #   the first week begins in the week after:
    #
    #     Date::ABBR_DAYNAMES[Date.new(2023, 1, 1).wday] # => "Sun"
    #     Date.commercial(2023, 1, 1).to_s # => "2023-01-02"
    #     Date.commercial(2023, 1, 7).to_s # => "2023-01-08"
    #
    # - Otherwise, the first week is the week of January 1,
    #   which may mean some of the days fall on the year before:
    #
    #     Date::ABBR_DAYNAMES[Date.new(2020, 1, 1).wday] # => "Wed"
    #     Date.commercial(2020, 1, 1).to_s # => "2019-12-30"
    #     Date.commercial(2020, 1, 7).to_s # => "2020-01-05"
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.jd, Date.new, Date.ordinal.
    def commercial(cwyear = -4712, cweek = 1, cwday = 1, start = DEFAULT_SG)
      if Integer === cwyear && Integer === cweek && Integer === cwday &&
         cweek >= 1 && cweek <= 52 && cwday >= 1 && cwday <= 7
        # ISO 8601: every year has at least 52 weeks, so weeks 1-52 are always valid.
        # Inline civil_to_jd(cwyear, 1, 4, start): month=1, day=4
        gy = cwyear - 1
        gjd_base4 = (1461 * (gy + 4716)) / 4 + 432  # GJD_MONTH_OFFSET[1] + 4
        a = gy / 100
        gjd4 = gjd_base4 - 1524 + 2 - a + a / 4
        jd_jan4 = gjd4 >= start ? gjd4 : gjd_base4 - 1524
        wday_jan4 = (jd_jan4 + 1) % 7
        mon_wk1 = jd_jan4 - (wday_jan4 == 0 ? 6 : wday_jan4 - 1)
        jd = mon_wk1 + (cweek - 1) * 7 + (cwday - 1)
        obj = allocate
        obj.__send__(:_init_from_jd, jd, start)
        return obj
      end
      cwyear = Integer(cwyear)
      cweek = Integer(cweek)
      cwday = Integer(cwday)
      jd = internal_valid_commercial?(cwyear, cweek, cwday, start)
      raise Date::Error, "invalid date" unless jd
      _new_from_jd(jd, start)
    end

    # call-seq:
    #   Date.valid_commercial?(cwyear, cweek, cwday, start = Date::ITALY) -> true or false
    #
    # Returns +true+ if the arguments define a valid commercial date,
    # +false+ otherwise:
    #
    #   Date.valid_commercial?(2001, 5, 6) # => true
    #   Date.valid_commercial?(2001, 5, 8) # => false
    #
    # See Date.commercial.
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # Related: Date.jd, Date.commercial.
    def valid_commercial?(year, week, day, start = DEFAULT_SG)
      return false unless year.is_a?(Numeric) && week.is_a?(Numeric) && day.is_a?(Numeric)
      !!internal_valid_commercial?(year, week, day, start)
    end

    # call-seq:
    #   Date.weeknum(year, week, wday, wstart = 0, start = Date::ITALY) -> date
    def weeknum(year = -4712, week = 0, wday = 1, wstart = 0, start = DEFAULT_SG)
      year = Integer(year)
      week = Integer(week)
      wday = Integer(wday)
      wstart = Integer(wstart)
      # Validate wday range
      raise Date::Error, "invalid date" unless wday >= 0 && wday <= 6
      # Validate week: reconstruct and check round-trip
      jd = weeknum_to_jd(year, week, wday, wstart, start)
      # Verify the resulting date is in the same year (week must be valid)
      y2, = jd_to_civil(jd, start)
      raise Date::Error, "invalid date" if y2 != year
      _new_from_jd(jd, start)
    end

    # call-seq:
    #   Date.nth_kday(year, month, n, k, start = Date::ITALY) -> date
    def nth_kday(year = -4712, month = 1, n = 1, k = 1, start = DEFAULT_SG)
      year = Integer(year)
      month = Integer(month)
      n = Integer(n)
      k = Integer(k)
      raise Date::Error, "invalid date" unless month >= 1 && month <= 12
      raise Date::Error, "invalid date" unless k >= 0 && k <= 6
      raise Date::Error, "invalid date" if n == 0
      jd = nth_kday_to_jd(year, month, n, k, start)
      # Verify the result is in the same month
      y2, m2, = jd_to_civil(jd, start)
      raise Date::Error, "invalid date" if y2 != year || m2 != month
      _new_from_jd(jd, start)
    end

    # call-seq:
    #   Date.today(start = Date::ITALY) -> date
    #
    # Returns a new \Date object constructed from the present date:
    #
    #   Date.today.to_s # => "2022-07-06"
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    def today(start = DEFAULT_SG)
      t = Time.now
      jd = civil_to_jd(t.year, t.mon, t.mday, start)
      _new_from_jd(jd, start)
    end

    # :nodoc:
    def _load(s)
      a = Marshal.load(s)
      obj = allocate
      obj.marshal_load(a)
      obj
    end

    # :nodoc:
    def new!(ajd = 0, of = 0, sg = DEFAULT_SG)
      # ajd is Astronomical Julian Day (may be Rational)
      # Convert to integer JD and day fraction (same as C's old_to_new)
      raw_jd = ajd + Rational(1, 2)
      jd = raw_jd.floor
      df = raw_jd - jd
      obj = allocate
      obj.__send__(:_init_from_jd, jd, sg, df == 0 ? nil : df)
      obj
    end

    private

    # ---------------------------------------------------------------------------
    # Internal calendar arithmetic (pure Ruby, no C dependency)
    # ---------------------------------------------------------------------------

    # Floor division that works correctly for negative numbers.
    def idiv(a, b)
      a.div(b)
    end

    # Gregorian leap year?
    def internal_gregorian_leap?(y)
      (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    end

    # Julian leap year?
    def internal_julian_leap?(y)
      y % 4 == 0
    end

    def days_in_month_gregorian(y, m)
      if m == 2 && internal_gregorian_leap?(y)
        29
      else
        DAYS_IN_MONTH_GREGORIAN[m]
      end
    end

    # Days in month for Julian calendar.
    def days_in_month_julian(y, m)
      if m == 2 && internal_julian_leap?(y)
        29
      else
        DAYS_IN_MONTH_GREGORIAN[m]
      end
    end

    # Gregorian civil (year, month, day) -> Julian Day Number
    def gregorian_to_jd(y, m, d)
      if m <= 2
        y -= 1
        m += 12
      end
      a = y / 100
      b = 2 - a + a / 4
      (1461 * (y + 4716)) / 4 + (306001 * (m + 1)) / 10000 + d + b - 1524
    end

    # Julian civil (year, month, day) -> Julian Day Number
    def julian_to_jd(y, m, d)
      if m <= 2
        y -= 1
        m += 12
      end
      (1461 * (y + 4716)) / 4 + (306001 * (m + 1)) / 10000 + d - 1524
    end

    # Civil (year, month, day) -> JD, respecting start (cutover).
    # Uses a unified formula: gjd >= sg -> Gregorian JD, else Julian JD.
    # Works for all sg values: Float::INFINITY (always Julian),
    # -Float::INFINITY (always Gregorian), or integer cutover JD.
    def civil_to_jd(y, m, d, sg)
      offset = GJD_MONTH_OFFSET[m]
      y -= 1 if m <= 2
      gjd_base = (1461 * (y + 4716)) / 4 + offset + d
      a = y / 100
      gjd = gjd_base - 1524 + 2 - a + a / 4
      gjd >= sg ? gjd : gjd_base - 1524
    end

    # Gregorian JD -> (year, month, day)
    def jd_to_gregorian(jd)
      a = jd + 32044
      b = idiv(4 * a + 3, 146097)
      c = a - idiv(146097 * b, 4)
      d = idiv(4 * c + 3, 1461)
      e = c - idiv(1461 * d, 4)
      m = idiv(5 * e + 2, 153)
      day  = e - idiv(153 * m + 2, 5) + 1
      mon  = m + 3 - 12 * idiv(m, 10)
      year = 100 * b + d - 4800 + idiv(m, 10)
      [year, mon, day]
    end

    # Julian JD -> (year, month, day)
    def jd_to_julian(jd)
      c = jd + 32082
      d = idiv(4 * c + 3, 1461)
      e = c - idiv(1461 * d, 4)
      m = idiv(5 * e + 2, 153)
      day  = e - idiv(153 * m + 2, 5) + 1
      mon  = m + 3 - 12 * idiv(m, 10)
      year = d - 4800 + idiv(m, 10)
      [year, mon, day]
    end

    # JD -> (year, month, day), respecting start (cutover).
    def jd_to_civil(jd, sg)
      if sg == Float::INFINITY
        jd_to_julian(jd)
      elsif sg == -Float::INFINITY || jd >= sg
        jd_to_gregorian(jd)
      else
        jd_to_julian(jd)
      end
    end

    # Ordinal (year, day-of-year) -> JD
    def ordinal_to_jd(y, d, sg)
      civil_to_jd(y, 1, 1, sg) + d - 1
    end

    # JD -> (year, day-of-year)
    def jd_to_ordinal(jd, sg)
      y, = jd_to_civil(jd, sg)
      jd_jan1 = civil_to_jd(y, 1, 1, sg)
      [y, jd - jd_jan1 + 1]
    end

    # Commercial (ISO week: cwyear, cweek, cwday) -> JD
    def commercial_to_jd(y, w, d, sg = -Float::INFINITY)
      # Jan 4 is always in week 1 (ISO 8601)
      jd_jan4 = civil_to_jd(y, 1, 4, sg)
      # Monday of week 1
      wday_jan4 = (jd_jan4 + 1) % 7  # 0=Sun
      iso_wday_jan4 = wday_jan4 == 0 ? 7 : wday_jan4
      mon_wk1 = jd_jan4 - (iso_wday_jan4 - 1)
      mon_wk1 + (w - 1) * 7 + (d - 1)
    end

    # JD -> (cwyear, cweek, cwday)
    def jd_to_commercial(jd, sg = -Float::INFINITY)
      wday = (jd + 1) % 7          # 0=Sun
      cwday = wday == 0 ? 7 : wday # 1=Mon..7=Sun
      # Thursday of the same ISO week
      thursday = jd + (4 - cwday)
      y, = thursday >= sg ? jd_to_gregorian(thursday) : jd_to_julian(thursday)
      jd_jan4 = civil_to_jd(y, 1, 4, sg)
      wday_jan4 = (jd_jan4 + 1) % 7
      iso_wday_jan4 = wday_jan4 == 0 ? 7 : wday_jan4
      mon_wk1 = jd_jan4 - (iso_wday_jan4 - 1)
      cweek = (jd - mon_wk1) / 7 + 1
      [y, cweek, cwday]
    end

    # Weeknum (year, week, wday, week_start, sg) -> JD
    # week_start: 0=Sun-based (%U), 1=Mon-based (%W)
    def weeknum_to_jd(y, w, d, ws, sg = -Float::INFINITY)
      jd_jan1 = civil_to_jd(y, 1, 1, sg)
      wday_jan1 = (jd_jan1 + 1) % 7  # 0=Sun
      j = jd_jan1 - wday_jan1
      j += 1 if ws == 1
      j + 7 * w + d
    end

    # n-th k-day (nth occurrence of weekday k in year y, month m) -> JD
    # k: 0=Sun..6=Sat, n: positive from beginning, negative from end
    def nth_kday_to_jd(y, m, n, k, sg)
      if n > 0
        jd_m1 = civil_to_jd(y, m, 1, sg)
        wday = (jd_m1 + 1) % 7
        diff = (k - wday + 7) % 7
        jd_m1 + diff + (n - 1) * 7
      else
        # Last day of month
        if m == 12
          jd_last = civil_to_jd(y + 1, 1, 1, sg) - 1
        else
          jd_last = civil_to_jd(y, m + 1, 1, sg) - 1
        end
        wday = (jd_last + 1) % 7
        diff = (wday - k + 7) % 7
        jd_last - diff + (n + 1) * 7
      end
    end

    # ---------------------------------------------------------------------------
    # Validation helpers
    # ---------------------------------------------------------------------------

    def internal_valid_jd?(jd, _sg)
      jd.is_a?(Numeric) ? jd.to_i : nil
    end

    def internal_valid_civil?(y, m, d, sg)
      return nil unless y.is_a?(Numeric) && m.is_a?(Numeric) && d.is_a?(Numeric)
      y = y.to_i
      m = m.to_i
      d = d.to_i
      # Handle negative month/day
      m += 13 if m < 0
      return nil if m < 1 || m > 12
      # Days in that month
      if sg == Float::INFINITY
        dim = days_in_month_julian(y, m)
      else
        dim = days_in_month_gregorian(y, m)
      end
      d += dim + 1 if d < 0
      return nil if d < 1 || d > dim
      civil_to_jd(y, m, d, sg)
    end

    def internal_valid_ordinal?(y, yday, sg)
      return nil unless y.is_a?(Numeric) && yday.is_a?(Numeric)
      y = y.to_i
      yday = yday.to_i
      # Days in year
      if sg == Float::INFINITY
        diy = internal_julian_leap?(y) ? 366 : 365
      else
        diy = internal_gregorian_leap?(y) ? 366 : 365
      end
      yday += diy + 1 if yday < 0
      return nil if yday < 1 || yday > diy
      ordinal_to_jd(y, yday, sg)
    end

    def internal_valid_commercial?(y, w, d, sg)
      return nil unless y.is_a?(Numeric) && w.is_a?(Numeric) && d.is_a?(Numeric)
      y = y.to_i
      w = w.to_i
      d = d.to_i
      # ISO cwday: 1=Mon..7=Sun
      d += 8 if d < 0
      return nil if d < 1 || d > 7
      # Weeks in year: Dec 28 is always in the last ISO week
      jd_dec28 = civil_to_jd(y, 12, 28, sg)
      _, max_week, = jd_to_commercial(jd_dec28, sg)
      w += max_week + 1 if w < 0
      return nil if w < 1 || w > max_week
      commercial_to_jd(y, w, d, sg)
    end

    # ---------------------------------------------------------------------------
    # Internal object factory
    # ---------------------------------------------------------------------------

    # Build a Date from a Julian Day Number (integer part), start, and optional day fraction.
    def _new_from_jd(jd, sg, df = nil)
      obj = allocate
      obj.__send__(:_init_from_jd, jd, sg, df)
      obj
    end

    # Parse offset string like "+09:00", "-07:30", "Z" to seconds.
    def _offset_str_to_sec(str)
      case str
      when 'Z', 'z', 'UTC', 'GMT'
        0
      when /\A([+-])(\d{1,2}):?(\d{2})(?::(\d{2}))?\z/
        sign = $1 == '+' ? 1 : -1
        h, m, s = $2.to_i, $3.to_i, ($4 || '0').to_i
        sign * (h * 3600 + m * 60 + s)
      when /\A([+-])(\d{2})(\d{2})\z/
        sign = $1 == '+' ? 1 : -1
        h, m = $2.to_i, $3.to_i
        sign * (h * 3600 + m * 60)
      else
        0
      end
    end

  end

  # ---------------------------------------------------------------------------
  # Initializer
  # ---------------------------------------------------------------------------

  # call-seq:
  #   Date.new(year = -4712, month = 1, mday = 1, start = Date::ITALY) -> date
  #
  # Returns a new \Date object constructed from the given arguments:
  #
  #   Date.new(2022).to_s        # => "2022-01-01"
  #   Date.new(2022, 2).to_s     # => "2022-02-01"
  #   Date.new(2022, 2, 4).to_s  # => "2022-02-04"
  #
  # Argument +month+ should be in range (1..12) or range (-12..-1);
  # when the argument is negative, counts backward from the end of the year:
  #
  #   Date.new(2022, -11, 4).to_s # => "2022-02-04"
  #
  # Argument +mday+ should be in range (1..n) or range (-n..-1)
  # where +n+ is the number of days in the month;
  # when the argument is negative, counts backward from the end of the month.
  #
  # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
  #
  # Related: Date.jd.
  def initialize(year = -4712, month = 1, day = 1, start = DEFAULT_SG)
    if Integer === year && Integer === month && Integer === day
      m = month
      m += 13 if m < 0
      if m >= 1 && m <= 12
        dim = if m == 2
          if start == Float::INFINITY
            year % 4 == 0 ? 29 : 28
          else
            (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
          end
        else
          DAYS_IN_MONTH_GREGORIAN[m]
        end
        d = day
        d += dim + 1 if d < 0
        if d >= 1 && d <= dim
          gy = m <= 2 ? year - 1 : year
          gjd_base = (1461 * (gy + 4716)) / 4 + GJD_MONTH_OFFSET[m] + d
          if start == Float::INFINITY
            @jd = gjd_base - 1524
          elsif start == -Float::INFINITY
            a = gy / 100
            @jd = gjd_base - 1524 + 2 - a + a / 4
          else
            a = gy / 100
            gjd = gjd_base - 1524 + 2 - a + a / 4
            @jd = gjd >= start ? gjd : gjd_base - 1524
          end
          @sg    = start
          @year  = year
          @month = m
          @day   = d
          return
        end
      end
      raise Date::Error, "invalid date"
    end
    year  = Integer(year)
    month = Integer(month)
    day   = Integer(day)
    jd = self.class.__send__(:internal_valid_civil?, year, month, day, start)
    raise Date::Error, "invalid date" unless jd
    _init_from_jd(jd, start)
  end

  # ---------------------------------------------------------------------------
  # Instance methods - basic attributes
  # ---------------------------------------------------------------------------

  # call-seq:
  #   year -> integer
  #
  # Returns the year:
  #
  #   Date.new(2001, 2, 3).year    # => 2001
  #   (Date.new(1, 1, 1) - 1).year # => 0
  #
  def year
    _civil unless @year
    @year
  end

  # call-seq:
  #   mon -> integer
  #
  # Returns the month in range (1..12):
  #
  #   Date.new(2001, 2, 3).mon # => 2
  #
  def month
    _civil unless @year
    @month
  end
  alias mon month

  # call-seq:
  #   mday -> integer
  #
  # Returns the day of the month in range (1..31):
  #
  #   Date.new(2001, 2, 3).mday # => 3
  #
  def day
    _civil unless @year
    @day
  end
  alias mday day

  # call-seq:
  #    d.jd  ->  integer
  #
  # Returns the Julian day number.  This is a whole number, which is
  # adjusted by the offset as the local time.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').jd	#=> 2451944
  #    DateTime.new(2001,2,3,4,5,6,'-7').jd	#=> 2451944
  def jd
    @jd
  end

  # call-seq:
  #   start -> float
  #
  # Returns the Julian start date for calendar reform;
  # if not an infinity, the returned value is suitable
  # for passing to Date#jd:
  #
  #   d = Date.new(2001, 2, 3, Date::ITALY)
  #   s = d.start     # => 2299161.0
  #   Date.jd(s).to_s # => "1582-10-15"
  #
  #   d = Date.new(2001, 2, 3, Date::ENGLAND)
  #   s = d.start     # => 2361222.0
  #   Date.jd(s).to_s # => "1752-09-14"
  #
  #   Date.new(2001, 2, 3, Date::GREGORIAN).start # => -Infinity
  #   Date.new(2001, 2, 3, Date::JULIAN).start    # => Infinity
  #
  # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
  #
  def start
    @sg
  end

  # call-seq:
  #    d.ajd  ->  rational
  #
  # Returns the astronomical Julian day number.  This is a fractional
  # number, which is not adjusted by the offset.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').ajd	#=> (11769328217/4800)
  #    DateTime.new(2001,2,2,14,5,6,'-7').ajd	#=> (11769328217/4800)
  def ajd
    r = Rational(@jd * 2 - 1, 2)
    @df ? r + @df : r
  end

  # call-seq:
  #    d.amjd  ->  rational
  #
  # Returns the astronomical modified Julian day number.  This is
  # a fractional number, which is not adjusted by the offset.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').amjd	#=> (249325817/4800)
  #    DateTime.new(2001,2,2,14,5,6,'-7').amjd	#=> (249325817/4800)
  def amjd
    ajd - Rational(4800001, 2)
  end

  # call-seq:
  #    d.mjd  ->  integer
  #
  # Returns the modified Julian day number.  This is a whole number,
  # which is adjusted by the offset as the local time.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').mjd	#=> 51943
  #    DateTime.new(2001,2,3,4,5,6,'-7').mjd	#=> 51943
  def mjd
    @jd - 2400001
  end

  # call-seq:
  #   ld -> integer
  #
  # Returns the
  # {Lilian day number}[https://en.wikipedia.org/wiki/Lilian_date],
  # which is the number of days since the beginning of the Gregorian
  # calendar, October 15, 1582.
  #
  #   Date.new(2001, 2, 3).ld # => 152784
  #
  def ld
    @jd - 2299160
  end

  # call-seq:
  #   yday -> integer
  #
  # Returns the day of the year, in range (1..366):
  #
  #   Date.new(2001, 2, 3).yday # => 34
  #
  def yday
    return @yday if @yday
    _civil unless @year
    # inline civil_to_jd(@year, 1, 1, @sg): month=1 (<= 2 so y-=1), day=1
    yy = @year - 1
    gjd_base = (1461 * (yy + 4716)) / 4 + 429  # GJD_MONTH_OFFSET[1](=428) + 1
    a = yy / 100
    gjd = gjd_base - 1524 + 2 - a + a / 4
    jd_jan1 = gjd >= @sg ? gjd : gjd_base - 1524
    val = @jd - jd_jan1 + 1
    @yday = val unless frozen?
    val
  end

  # call-seq:
  #   wday -> integer
  #
  # Returns the day of week in range (0..6); Sunday is 0:
  #
  #   Date.new(2001, 2, 3).wday # => 6
  #
  def wday
    (@jd + 1) % 7
  end

  # call-seq:
  #   cwday -> integer
  #
  # Returns the commercial-date weekday index for +self+
  # (see Date.commercial);
  # 1 is Monday:
  #
  #   Date.new(2001, 2, 3).cwday # => 6
  #
  def cwday
    w = wday
    w == 0 ? 7 : w
  end

  # call-seq:
  #   cweek -> integer
  #
  # Returns commercial-date week index for +self+
  # (see Date.commercial):
  #
  #   Date.new(2001, 2, 3).cweek # => 5
  #
  def cweek
    @cweek || _compute_commercial[1]
  end

  # call-seq:
  #   cwyear -> integer
  #
  # Returns commercial-date year for +self+
  # (see Date.commercial):
  #
  #   Date.new(2001, 2, 3).cwyear # => 2001
  #   Date.new(2000, 1, 1).cwyear # => 1999
  #
  def cwyear
    @cwyear || _compute_commercial[0]
  end

  # call-seq:
  #   day_fraction -> rational
  #
  # Returns the fractional part of the day in range (Rational(0, 1)...Rational(1, 1)):
  #
  #   DateTime.new(2001,2,3,12).day_fraction # => (1/2)
  #
  def day_fraction
    @df || Rational(0)
  end

  # call-seq:
  #   leap? -> true or false
  #
  # Returns +true+ if the year is a leap year, +false+ otherwise:
  #
  #   Date.new(2000).leap? # => true
  #   Date.new(2001).leap? # => false
  #
  def leap?
    _civil unless @year
    if @jd < @sg  # julian?
      @year % 4 == 0
    else
      (@year % 4 == 0 && @year % 100 != 0) || @year % 400 == 0
    end
  end

  # call-seq:
  #   gregorian? -> true or false
  #
  # Returns +true+ if the date is on or after
  # the date of calendar reform, +false+ otherwise:
  #
  #   Date.new(1582, 10, 15).gregorian?       # => true
  #   (Date.new(1582, 10, 15) - 1).gregorian? # => false
  #
  def gregorian?
    jd >= @sg
  end

  # call-seq:
  #   d.julian? -> true or false
  #
  # Returns +true+ if the date is before the date of calendar reform,
  # +false+ otherwise:
  #
  #   (Date.new(1582, 10, 15) - 1).julian? # => true
  #   Date.new(1582, 10, 15).julian?       # => false
  #
  def julian?
    !gregorian?
  end

  # call-seq:
  #   new_start(start = Date::ITALY]) -> new_date
  #
  # Returns a copy of +self+ with the given +start+ value:
  #
  #   d0 = Date.new(2000, 2, 3)
  #   d0.julian? # => false
  #   d1 = d0.new_start(Date::JULIAN)
  #   d1.julian? # => true
  #
  # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
  #
  def new_start(start = DEFAULT_SG)
    obj = self.class.allocate
    obj.instance_variable_set(:@jd, @jd)
    obj.instance_variable_set(:@sg, start)
    obj
  end

  # call-seq:
  #   gregorian -> new_date
  #
  # Equivalent to Date#new_start with argument Date::GREGORIAN.
  def gregorian
    new_start(GREGORIAN)
  end

  # call-seq:
  #   italy -> new_date
  #
  # Equivalent to Date#new_start with argument Date::ITALY.
  #
  def italy
    new_start(ITALY)
  end

  # call-seq:
  #   england -> new_date
  #
  # Equivalent to Date#new_start with argument Date::ENGLAND.
  def england
    new_start(ENGLAND)
  end

  # call-seq:
  #   julian -> new_date
  #
  # Equivalent to Date#new_start with argument Date::JULIAN.
  def julian
    new_start(JULIAN)
  end

  # call-seq:
  #   sunday? -> true or false
  #
  # Returns +true+ if +self+ is a Sunday, +false+ otherwise.
  def sunday?
    wday == 0
  end
  # call-seq:
  #   monday? -> true or false
  #
  # Returns +true+ if +self+ is a Monday, +false+ otherwise.
  def monday?
    wday == 1
  end
  # call-seq:
  #   tuesday? -> true or false
  #
  # Returns +true+ if +self+ is a Tuesday, +false+ otherwise.
  def tuesday?
    wday == 2
  end
  # call-seq:
  #   wednesday? -> true or false
  #
  # Returns +true+ if +self+ is a Wednesday, +false+ otherwise.
  def wednesday?
    wday == 3
  end
  # call-seq:
  #   thursday? -> true or false
  #
  # Returns +true+ if +self+ is a Thursday, +false+ otherwise.
  def thursday?
    wday == 4
  end
  # call-seq:
  #   friday? -> true or false
  #
  # Returns +true+ if +self+ is a Friday, +false+ otherwise.
  def friday?
    wday == 5
  end
  # call-seq:
  #   saturday? -> true or false
  #
  # Returns +true+ if +self+ is a Saturday, +false+ otherwise.
  def saturday?
    wday == 6
  end

  # :nodoc:
  def nth_kday?(n, k)
    return false if k != wday
    jd_ref = self.class.__send__(:nth_kday_to_jd, year, month, n, k, @sg)
    jd_ref == @jd
  end

  # ---------------------------------------------------------------------------
  # Comparison
  # ---------------------------------------------------------------------------

  # call-seq:
  #   self <=> other  -> -1, 0, 1 or nil
  #
  # Compares +self+ and +other+, returning:
  #
  # - <tt>-1</tt> if +other+ is larger.
  # - <tt>0</tt> if the two are equal.
  # - <tt>1</tt> if +other+ is smaller.
  # - +nil+ if the two are incomparable.
  #
  # Argument +other+ may be:
  #
  # - Another \Date object:
  #
  #     d = Date.new(2022, 7, 27) # => #<Date: 2022-07-27 ((2459788j,0s,0n),+0s,2299161j)>
  #     prev_date = d.prev_day    # => #<Date: 2022-07-26 ((2459787j,0s,0n),+0s,2299161j)>
  #     next_date = d.next_day    # => #<Date: 2022-07-28 ((2459789j,0s,0n),+0s,2299161j)>
  #     d <=> next_date           # => -1
  #     d <=> d                   # => 0
  #     d <=> prev_date           # => 1
  #
  # - A DateTime object:
  #
  #     d <=> DateTime.new(2022, 7, 26) # => 1
  #     d <=> DateTime.new(2022, 7, 27) # => 0
  #     d <=> DateTime.new(2022, 7, 28) # => -1
  #
  # - A numeric (compares <tt>self.ajd</tt> to +other+):
  #
  #     d <=> 2459788 # => -1
  #     d <=> 2459787 # => 1
  #     d <=> 2459786 # => 1
  #     d <=> d.ajd   # => 0
  #
  # - Any other object:
  #
  #     d <=> Object.new # => nil
  #
  def <=>(other)
    case other
    when Date
      d = @jd <=> other.jd
      d != 0 ? d : day_fraction <=> other.day_fraction
    when Numeric
      ajd <=> other
    else
      nil
    end
  end

  def <(other)
    case other
    when Date
      d = @jd <=> other.jd
      d != 0 ? d < 0 : day_fraction < other.day_fraction
    when Numeric
      r = ajd <=> other
      raise ArgumentError, "comparison of #{self.class} with #{other.class} failed" if r.nil?
      r < 0
    else
      raise ArgumentError, "comparison of #{self.class} with #{other.class} failed"
    end
  end

  def >(other)
    case other
    when Date
      d = @jd <=> other.jd
      d != 0 ? d > 0 : day_fraction > other.day_fraction
    when Numeric
      r = ajd <=> other
      raise ArgumentError, "comparison of #{self.class} with #{other.class} failed" if r.nil?
      r > 0
    else
      raise ArgumentError, "comparison of #{self.class} with #{other.class} failed"
    end
  end

  def ==(other)
    case other
    when Date
      @jd == other.jd && day_fraction == other.day_fraction
    when Numeric
      ajd == other
    else
      false
    end
  end

  def eql?(other)
    other.is_a?(Date) && @jd == other.jd && day_fraction == other.day_fraction
  end

  def hash
    [@jd, @sg].hash
  end

  # call-seq:
  #   self === other -> true, false, or nil.
  #
  # Returns +true+ if +self+ and +other+ represent the same date,
  # +false+ if not, +nil+ if the two are not comparable.
  #
  # Argument +other+ may be:
  #
  # - Another \Date object:
  #
  #     d = Date.new(2022, 7, 27) # => #<Date: 2022-07-27 ((2459788j,0s,0n),+0s,2299161j)>
  #     prev_date = d.prev_day    # => #<Date: 2022-07-26 ((2459787j,0s,0n),+0s,2299161j)>
  #     next_date = d.next_day    # => #<Date: 2022-07-28 ((2459789j,0s,0n),+0s,2299161j)>
  #     d === prev_date           # => false
  #     d === d                   # => true
  #     d === next_date           # => false
  #
  # - A DateTime object:
  #
  #     d === DateTime.new(2022, 7, 26) # => false
  #     d === DateTime.new(2022, 7, 27) # => true
  #     d === DateTime.new(2022, 7, 28) # => false
  #
  # - A numeric (compares <tt>self.jd</tt> to +other+):
  #
  #     d === 2459788 # => true
  #     d === 2459787 # => false
  #     d === 2459786 # => false
  #     d === d.jd    # => true
  #
  # - An object not comparable:
  #
  #     d === Object.new # => nil
  #
  def ===(other)
    case other
    when Numeric
      jd == other.to_i
    when Date
      jd == other.jd
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Arithmetic
  # ---------------------------------------------------------------------------

  # call-seq:
  #    d + other  ->  date
  #
  # Returns a date object pointing +other+ days after self.  The other
  # should be a numeric value.  If the other is a fractional number,
  # assumes its precision is at most nanosecond.
  #
  #    Date.new(2001,2,3) + 1	#=> #<Date: 2001-02-04 ...>
  #    DateTime.new(2001,2,3) + Rational(1,2)
  #				#=> #<DateTime: 2001-02-03T12:00:00+00:00 ...>
  #    DateTime.new(2001,2,3) + Rational(-1,2)
  #				#=> #<DateTime: 2001-02-02T12:00:00+00:00 ...>
  #    DateTime.jd(0,12) + DateTime.new(2001,2,3).ajd
  #				#=> #<DateTime: 2001-02-03T00:00:00+00:00 ...>
  def +(other)
    case other
    when Integer
      if instance_of?(Date)
        obj = Date.allocate
        obj.instance_variable_set(:@jd, @jd + other)
        obj.instance_variable_set(:@sg, @sg)
        obj
      else
        self.class.__send__(:_new_from_jd, @jd + other, @sg, @df)
      end
    when Numeric
      r = other.to_r
      raise TypeError, "#{other.class} can't be coerced into Integer" unless r.is_a?(Rational)
      total = r + (@df || 0)
      days = total.floor
      frac = total - days
      self.class.__send__(:_new_from_jd, @jd + days, @sg, frac == 0 ? nil : frac)
    else
      raise TypeError, "expected numeric"
    end
  end

  # call-seq:
  #    d - other  ->  date or rational
  #
  # If the other is a date object, returns a Rational
  # whose value is the difference between the two dates in days.
  # If the other is a numeric value, returns a date object
  # pointing +other+ days before self.
  # If the other is a fractional number,
  # assumes its precision is at most nanosecond.
  #
  #     Date.new(2001,2,3) - 1	#=> #<Date: 2001-02-02 ...>
  #     DateTime.new(2001,2,3) - Rational(1,2)
  #				#=> #<DateTime: 2001-02-02T12:00:00+00:00 ...>
  #     Date.new(2001,2,3) - Date.new(2001)
  #				#=> (33/1)
  #     DateTime.new(2001,2,3) - DateTime.new(2001,2,2,12)
  #				#=> (1/2)
  def -(other)
    case other
    when Date
      Rational(@jd - other.jd) + (@df || 0) - other.day_fraction
    when Integer
      if instance_of?(Date)
        obj = Date.allocate
        obj.instance_variable_set(:@jd, @jd - other)
        obj.instance_variable_set(:@sg, @sg)
        obj
      else
        self.class.__send__(:_new_from_jd, @jd - other, @sg, @df)
      end
    when Numeric
      r = other.to_r
      raise TypeError, "#{other.class} can't be coerced into Integer" unless r.is_a?(Rational)
      total = (@df || 0) - r
      days = total.floor
      frac = total - days
      self.class.__send__(:_new_from_jd, @jd + days, @sg, frac == 0 ? nil : frac)
    else
      raise TypeError, "expected numeric"
    end
  end

  # call-seq:
  #   d >> n -> new_date
  #
  # Returns a new \Date object representing the date
  # +n+ months later; +n+ should be a numeric:
  #
  #   (Date.new(2001, 2, 3) >> 1).to_s  # => "2001-03-03"
  #   (Date.new(2001, 2, 3) >> -2).to_s # => "2000-12-03"
  #
  # When the same day does not exist for the new month,
  # the last day of that month is used instead:
  #
  #   (Date.new(2001, 1, 31) >> 1).to_s  # => "2001-02-28"
  #   (Date.new(2001, 1, 31) >> -4).to_s # => "2000-09-30"
  #
  # This results in the following, possibly unexpected, behaviors:
  #
  #   d0 = Date.new(2001, 1, 31)
  #   d1 = d0 >> 1 # => #<Date: 2001-02-28>
  #   d2 = d1 >> 1 # => #<Date: 2001-03-28>
  #
  #   d0 = Date.new(2001, 1, 31)
  #   d1 = d0 >> 1  # => #<Date: 2001-02-28>
  #   d2 = d1 >> -1 # => #<Date: 2001-01-28>
  #
  def >>(n)
    _civil unless @year
    m2 = @month + n.to_i
    y2 = @year + (m2 - 1).div(12)
    m2 = (m2 - 1) % 12 + 1
    # inline days_in_month
    if m2 == 2
      if @sg == Float::INFINITY
        dim = y2 % 4 == 0 ? 29 : 28
      else
        dim = ((y2 % 4 == 0 && y2 % 100 != 0) || y2 % 400 == 0) ? 29 : 28
      end
    else
      dim = DAYS_IN_MONTH_GREGORIAN[m2]
    end
    d2 = @day < dim ? @day : dim
    # inline civil_to_jd(y2, m2, d2, @sg)
    offset = GJD_MONTH_OFFSET[m2]
    yy = m2 <= 2 ? y2 - 1 : y2
    gjd_base = (1461 * (yy + 4716)) / 4 + offset + d2
    a = yy / 100
    gjd = gjd_base - 1524 + 2 - a + a / 4
    jd2 = gjd >= @sg ? gjd : gjd_base - 1524
    # inline _new_from_jd
    obj = self.class.allocate
    obj.instance_variable_set(:@jd, jd2)
    obj.instance_variable_set(:@sg, @sg)
    obj
  end

  # call-seq:
  #    d << n  ->  date
  #
  # Returns a new \Date object representing the date
  # +n+ months earlier; +n+ should be a numeric:
  #
  #   (Date.new(2001, 2, 3) << 1).to_s  # => "2001-01-03"
  #   (Date.new(2001, 2, 3) << -2).to_s # => "2001-04-03"
  #
  # When the same day does not exist for the new month,
  # the last day of that month is used instead:
  #
  #   (Date.new(2001, 3, 31) << 1).to_s  # => "2001-02-28"
  #   (Date.new(2001, 3, 31) << -6).to_s # => "2001-09-30"
  #
  # This results in the following, possibly unexpected, behaviors:
  #
  #   d0 = Date.new(2001, 3, 31)
  #   d0 << 2      # => #<Date: 2001-01-31>
  #   d0 << 1 << 1 # => #<Date: 2001-01-28>
  #
  #   d0 = Date.new(2001, 3, 31)
  #   d1 = d0 << 1  # => #<Date: 2001-02-28>
  #   d2 = d1 << -1 # => #<Date: 2001-03-28>
  #
  def <<(n)
    self >> -n
  end

  # call-seq:
  #   next_day(n = 1) -> new_date
  #
  # Equivalent to Date#+ with argument +n+.
  def next_day(n = 1)
    self + n
  end

  # call-seq:
  #   prev_day(n = 1) -> new_date
  #
  # Equivalent to Date#- with argument +n+.
  def prev_day(n = 1)
    self - n
  end

  # call-seq:
  #   d.next -> new_date
  #
  # Returns a new \Date object representing the following day:
  #
  #   d = Date.new(2001, 2, 3)
  #   d.to_s      # => "2001-02-03"
  #   d.next.to_s # => "2001-02-04"
  #
  def next
    self + 1
  end
  alias_method :succ, :next

  # call-seq:
  #   next_year(n = 1) -> new_date
  #
  # Equivalent to #>> with argument <tt>n * 12</tt>.
  def next_year(n = 1)
    self >> n * 12
  end

  # call-seq:
  #   prev_year(n = 1) -> new_date
  #
  # Equivalent to #<< with argument <tt>n * 12</tt>.
  def prev_year(n = 1)
    self << n * 12
  end

  # call-seq:
  #   next_month(n = 1) -> new_date
  #
  # Equivalent to #>> with argument +n+.
  def next_month(n = 1)
    self >> n
  end

  # call-seq:
  #   prev_month(n = 1) -> new_date
  #
  # Equivalent to #<< with argument +n+.
  def prev_month(n = 1)
    self << n
  end

  # call-seq:
  #   step(limit, step = 1){|date| ... } -> self
  #
  # Calls the block with specified dates;
  # returns +self+.
  #
  # - The first +date+ is +self+.
  # - Each successive +date+ is <tt>date + step</tt>,
  #   where +step+ is the numeric step size in days.
  # - The last date is the last one that is before or equal to +limit+,
  #   which should be a \Date object.
  #
  # Example:
  #
  #   limit = Date.new(2001, 12, 31)
  #   Date.new(2001).step(limit){|date| p date.to_s if date.mday == 31 }
  #
  # Output:
  #
  #   "2001-01-31"
  #   "2001-03-31"
  #   "2001-05-31"
  #   "2001-07-31"
  #   "2001-08-31"
  #   "2001-10-31"
  #   "2001-12-31"
  #
  # Returns an Enumerator if no block is given.
  def step(limit, step = 1)
    return to_enum(:step, limit, step) unless block_given?
    if Integer === step && instance_of?(Date) && limit.instance_of?(Date)
      raise ArgumentError, "step can't be 0" if step == 0
      limit_jd = limit.jd
      sg = @sg
      if step > 0
        jd = @jd
        while jd <= limit_jd
          obj = Date.allocate
          obj.instance_variable_set(:@jd, jd)
          obj.instance_variable_set(:@sg, sg)
          yield obj
          jd += step
        end
      else
        jd = @jd
        while jd >= limit_jd
          obj = Date.allocate
          obj.instance_variable_set(:@jd, jd)
          obj.instance_variable_set(:@sg, sg)
          yield obj
          jd += step
        end
      end
      return self
    end
    d = self
    cmp = step <=> 0
    raise ArgumentError, "comparison of #{step.class} with 0 failed" if cmp.nil?
    if cmp > 0
      while d <= limit
        yield d
        d = d + step
      end
    elsif cmp < 0
      while d >= limit
        yield d
        d = d + step
      end
    else
      raise ArgumentError, "step can't be 0"
    end
    self
  end

  # call-seq:
  #   upto(max){|date| ... } -> self
  #
  # Equivalent to #step with arguments +max+ and +1+.
  def upto(max, &block)
    return to_enum(:upto, max) unless block_given?
    if instance_of?(Date) && max.instance_of?(Date)
      jd = @jd
      max_jd = max.jd
      sg = @sg
      while jd <= max_jd
        obj = Date.allocate
        obj.instance_variable_set(:@jd, jd)
        obj.instance_variable_set(:@sg, sg)
        yield obj
        jd += 1
      end
      return self
    end
    step(max, 1, &block)
  end

  # call-seq:
  #   downto(min){|date| ... } -> self
  #
  # Equivalent to #step with arguments +min+ and <tt>-1</tt>.
  def downto(min, &block)
    return to_enum(:downto, min) unless block_given?
    if instance_of?(Date) && min.instance_of?(Date)
      jd = @jd
      min_jd = min.jd
      sg = @sg
      while jd >= min_jd
        obj = Date.allocate
        obj.instance_variable_set(:@jd, jd)
        obj.instance_variable_set(:@sg, sg)
        yield obj
        jd -= 1
      end
      return self
    end
    step(min, -1, &block)
  end

  # ---------------------------------------------------------------------------
  # Calendar conversion
  # ---------------------------------------------------------------------------

  # call-seq:
  #   to_date -> self
  #
  # Returns +self+.
  def to_date
    self
  end

  # call-seq:
  #    d.to_datetime  -> datetime
  #
  # Returns a DateTime whose value is the same as +self+:
  #
  #   Date.new(2001, 2, 3).to_datetime # => #<DateTime: 2001-02-03T00:00:00+00:00>
  #
  def to_datetime
    DateTime.new(year, month, day, 0, 0, 0, 0, @sg)
  end

  # call-seq:
  #   to_time -> time
  #
  # Returns a new Time object with the same value as +self+;
  # if +self+ is a Julian date, derives its Gregorian date
  # for conversion to the \Time object:
  #
  #   Date.new(2001, 2, 3).to_time               # => 2001-02-03 00:00:00 -0600
  #   Date.new(2001, 2, 3, Date::JULIAN).to_time # => 2001-02-16 00:00:00 -0600
  #
  def to_time
    # Use Gregorian date for Time (inline jd_to_gregorian)
    a = @jd + 32044
    b = (4 * a + 3) / 146097
    c = a - (146097 * b) / 4
    dd = (4 * c + 3) / 1461
    e = c - (1461 * dd) / 4
    m = (5 * e + 2) / 153
    day   = e - (153 * m + 2) / 5 + 1
    month = m + 3 - 12 * (m / 10)
    year  = 100 * b + dd - 4800 + m / 10
    Time.local(year, month, day)
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  # :nodoc:
  def initialize_copy(other)
    @jd    = other.instance_variable_get(:@jd)
    @sg    = other.instance_variable_get(:@sg)
    @df    = other.instance_variable_get(:@df)
    @year  = other.instance_variable_get(:@year)
    @month = other.instance_variable_get(:@month)
    @day   = other.instance_variable_get(:@day)
  end

  # :nodoc:
  def marshal_dump
    # 6-element format: [nth, jd, df, sf, of, sg]
    # df = seconds into day (Integer), sf = sub-second fraction (Rational)
    if @df
      total_sec = @df * 86400
      df_int = total_sec.floor
      sf = total_sec - df_int
      [0, @jd, df_int, sf, 0, @sg]
    else
      [0, @jd, 0, 0, 0, @sg]
    end
  end

  # :nodoc:
  def marshal_load(array)
    case array.length
    when 2
      # Format 1.4/1.6: [jd_like, sg_or_bool]
      jd_like, sg_or_bool = array
      sg = sg_or_bool == true ? GREGORIAN : (sg_or_bool == false ? JULIAN : sg_or_bool.to_f)
      _init_from_jd(jd_like.to_i, sg)
    when 3
      # Format 1.8: [ajd, of, sg]
      ajd, _of, sg = array
      raw_jd = ajd + Rational(1, 2)
      jd = raw_jd.floor
      df = raw_jd - jd
      _init_from_jd(jd, sg, df == 0 ? nil : df)
    when 6
      # Current format: [nth, jd, df, sf, of, sg]
      _nth, jd, df, sf, _of, sg = array
      if df != 0 || sf != 0
        day_frac = (Rational(df) + sf) / 86400
        _init_from_jd(jd, sg, day_frac)
      else
        _init_from_jd(jd, sg)
      end
    else
      raise TypeError, "invalid marshal data"
    end
  end

  #  call-seq:
  #    deconstruct_keys(array_of_names_or_nil) -> hash
  #
  #  Returns a hash of the name/value pairs, to use in pattern matching.
  #  Possible keys are: <tt>:year</tt>, <tt>:month</tt>, <tt>:day</tt>,
  #  <tt>:wday</tt>, <tt>:yday</tt>.
  #
  #  Possible usages:
  #
  #    d = Date.new(2022, 10, 5)
  #
  #    if d in wday: 3, day: ..7  # uses deconstruct_keys underneath
  #      puts "first Wednesday of the month"
  #    end
  #    #=> prints "first Wednesday of the month"
  #
  #    case d
  #    in year: ...2022
  #      puts "too old"
  #    in month: ..9
  #      puts "quarter 1-3"
  #    in wday: 1..5, month:
  #      puts "working day in month #{month}"
  #    end
  #    #=> prints "working day in month 10"
  #
  #  Note that deconstruction by pattern can also be combined with class check:
  #
  #    if d in Date(wday: 3, day: ..7)
  #      puts "first Wednesday of the month"
  #    end
  #
  def deconstruct_keys(keys)
    if keys
      if keys.size == 1
        case keys[0]
        when :year
          _civil unless @year
          { year: @year }
        when :month
          _civil unless @year
          { month: @month }
        when :day
          _civil unless @year
          { day: @day }
        when :wday  then { wday: (@jd + 1) % 7 }
        when :yday  then { yday: yday }
        else {}
        end
      else
        _civil unless @year
        h = {}
        keys.each do |k|
          case k
          when :year  then h[:year] = @year
          when :month then h[:month] = @month
          when :day   then h[:day] = @day
          when :wday  then h[:wday] = (@jd + 1) % 7
          when :yday  then h[:yday] = yday
          end
        end
        h
      end
    else
      _civil unless @year
      { year: @year, month: @month, day: @day, wday: (@jd + 1) % 7, yday: yday }
    end
  end

  # ---------------------------------------------------------------------------
  # String formatting (delegated to strftime.rb)
  # ---------------------------------------------------------------------------

  # call-seq:
  #   asctime -> string
  #
  # Equivalent to #strftime with argument <tt>'%a %b %e %T %Y'</tt>
  # (or its {shorthand form}[rdoc-ref:language/strftime_formatting.rdoc@Shorthand+Conversion+Specifiers]
  # <tt>'%c'</tt>):
  #
  #   Date.new(2001, 2, 3).asctime # => "Sat Feb  3 00:00:00 2001"
  #
  # See {asctime}[https://linux.die.net/man/3/asctime].
  #
  def asctime
    _civil unless @year
    d = @day
    d_s = d < 10 ? " #{d}" : d.to_s
    y = @year
    y_s = y >= 1000 ? y.to_s : (y >= 0 ? format('%04d', y) : format('-%04d', -y))
    w = (@jd + 1) % 7
    if instance_of?(Date)
      "#{ASCTIME_DAYS[w]} #{ASCTIME_MONS[@month]} #{d_s} 00:00:00 #{y_s}".force_encoding(Encoding::US_ASCII)
    else
      "#{ASCTIME_DAYS[w]} #{ASCTIME_MONS[@month]} #{d_s} #{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]} #{y_s}".force_encoding(Encoding::US_ASCII)
    end
  end
  alias_method :ctime, :asctime

  # call-seq:
  #   iso8601    ->  string
  #
  # Equivalent to #strftime with argument <tt>'%Y-%m-%d'</tt>
  # (or its {shorthand form}[rdoc-ref:language/strftime_formatting.rdoc@Shorthand+Conversion+Specifiers]
  # <tt>'%F'</tt>);
  #
  #   Date.new(2001, 2, 3).iso8601 # => "2001-02-03"
  #
  def iso8601
    to_s
  end
  alias_method :xmlschema, :iso8601

  # call-seq:
  #   rfc3339 -> string
  #
  # Equivalent to #strftime with argument <tt>'%FT%T%:z'</tt>;
  # see {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc]:
  #
  #   Date.new(2001, 2, 3).rfc3339 # => "2001-02-03T00:00:00+00:00"
  #
  def rfc3339
    (to_s << 'T00:00:00+00:00').force_encoding(Encoding::US_ASCII)
  end

  # call-seq:
  #   rfc2822 -> string
  #
  # Equivalent to #strftime with argument <tt>'%a, %-d %b %Y %T %z'</tt>;
  # see {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc]:
  #
  #   Date.new(2001, 2, 3).rfc2822 # => "Sat, 3 Feb 2001 00:00:00 +0000"
  #
  def rfc2822
    _civil unless @year
    w = (@jd + 1) % 7
    y = @year
    y_s = y >= 1000 ? y.to_s : (y >= 0 ? format('%04d', y) : format('-%04d', -y))
    if instance_of?(Date)
      "#{RFC2822_DAYS[w]}, #{@day}#{RFC_MON_SPACE[@month]}#{y_s} 00:00:00 +0000".force_encoding(Encoding::US_ASCII)
    else
      "#{RFC2822_DAYS[w]}, #{@day}#{RFC_MON_SPACE[@month]}#{y_s} #{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]} +0000".force_encoding(Encoding::US_ASCII)
    end
  end
  alias_method :rfc822, :rfc2822

  # call-seq:
  #   httpdate -> string
  #
  # Equivalent to #strftime with argument <tt>'%a, %d %b %Y %T GMT'</tt>;
  # see {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc]:
  #
  #   Date.new(2001, 2, 3).httpdate # => "Sat, 03 Feb 2001 00:00:00 GMT"
  #
  def httpdate
    _civil unless @year
    w = (@jd + 1) % 7
    y = @year
    y_s = y >= 1000 ? y.to_s : (y >= 0 ? format('%04d', y) : format('-%04d', -y))
    if instance_of?(Date)
      "#{ASCTIME_DAYS[w]}, #{PAD2[@day]}#{RFC_MON_SPACE[@month]}#{y_s} 00:00:00 GMT".force_encoding(Encoding::US_ASCII)
    else
      "#{ASCTIME_DAYS[w]}, #{PAD2[@day]}#{RFC_MON_SPACE[@month]}#{y_s} #{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]} GMT".force_encoding(Encoding::US_ASCII)
    end
  end

  # call-seq:
  #   jisx0301 -> string
  #
  # Returns a string representation of the date in +self+
  # in JIS X 0301 format.
  #
  #   Date.new(2001, 2, 3).jisx0301 # => "H13.02.03"
  #
  def jisx0301
    _civil unless @year
    jd = @jd
    m = @month
    d = @day
    md = "#{PAD2[m]}.#{PAD2[d]}"
    if jd >= 2458605       # Reiwa (2019-05-01)
      "R#{PAD2[@year - 2018]}.#{md}"
    elsif jd >= 2447535    # Heisei (1989-01-08)
      "H#{PAD2[@year - 1988]}.#{md}"
    elsif jd >= 2424875    # Showa (1926-12-25)
      "S#{PAD2[@year - 1925]}.#{md}"
    elsif jd >= 2419614    # Taisho (1912-07-30)
      "T#{PAD2[@year - 1911]}.#{md}"
    elsif jd >= 2405160    # Meiji (1873-01-01)
      "M#{PAD2[@year - 1867]}.#{md}"
    else
      to_s
    end
  end

  # call-seq:
  #   to_s -> string
  #
  # Returns a string representation of the date in +self+
  # in {ISO 8601 extended date format}[rdoc-ref:language/strftime_formatting.rdoc@ISO+8601+Format+Specifications]
  # (<tt>'%Y-%m-%d'</tt>):
  #
  #   Date.new(2001, 2, 3).to_s # => "2001-02-03"
  #
  def to_s
    _civil
    suffix = MONTH_DAY_SUFFIX[@month][@day]
    y = @year
    if y >= 1000
      # Fast path: 4-digit year needs no zero-padding (most common case).
      (y.to_s << suffix).force_encoding(Encoding::US_ASCII)
    elsif y >= 0
      (format('%04d', y) << suffix).force_encoding(Encoding::US_ASCII)
    else
      (format('-%04d', -y) << suffix).force_encoding(Encoding::US_ASCII)
    end
  end

  # call-seq:
  #   inspect -> string
  #
  # Returns a string representation of +self+:
  #
  #   Date.new(2001, 2, 3).inspect
  #   # => "#<Date: 2001-02-03 ((2451944j,0s,0n),+0s,2299161j)>"
  #
  def inspect
    sg = @sg.is_a?(Float) ? @sg.to_s : @sg
    "#<Date: #{to_s} ((#{@jd}j,0s,0n),+0s,#{sg}j)>".force_encoding(Encoding::US_ASCII)
  end

  # override
  def freeze
    _civil  # compute and cache civil date before freezing
    super
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  def _init_from_jd(jd, sg, df = nil)
    @jd = jd
    @sg = sg
    @df = df
  end

  def _civil
    return if @year
    jd = @jd
    if @sg == Float::INFINITY       # always Julian
      b = 0
      c = jd + 32082
    elsif jd >= @sg                 # Gregorian (handles -Infinity too)
      a = jd + 32044
      b = (4 * a + 3) / 146097
      c = a - (146097 * b) / 4
    else                            # Julian (before reform date)
      b = 0
      c = jd + 32082
    end
    d = (4 * c + 3) / 1461
    e = c - (1461 * d) / 4
    m = (5 * e + 2) / 153
    @day   = e - (153 * m + 2) / 5 + 1
    @month = m + 3 - 12 * (m / 10)
    @year  = 100 * b + d - 4800 + m / 10
  end

  # Inline jd_to_commercial: compute and cache cwyear/cweek
  def _compute_commercial
    jd = @jd
    wday_val = (jd + 1) % 7
    cwday_val = wday_val == 0 ? 7 : wday_val
    thursday = jd + (4 - cwday_val)
    sg = @sg
    # inline jd_to_gregorian/jd_to_julian to get year only
    if sg == Float::INFINITY
      # Julian
      c = thursday + 32082
      d = (4 * c + 3) / 1461
      e = c - (1461 * d) / 4
      m = (5 * e + 2) / 153
      y = d - 4800 + m / 10
    elsif thursday >= sg
      # Gregorian
      a = thursday + 32044
      b = (4 * a + 3) / 146097
      c = a - (146097 * b) / 4
      d = (4 * c + 3) / 1461
      e = c - (1461 * d) / 4
      m = (5 * e + 2) / 153
      y = 100 * b + d - 4800 + m / 10
    else
      # Julian
      c = thursday + 32082
      d = (4 * c + 3) / 1461
      e = c - (1461 * d) / 4
      m = (5 * e + 2) / 153
      y = d - 4800 + m / 10
    end
    # inline civil_to_jd(y, 1, 4, sg): month=1 (<= 2), day=4
    yy = y - 1
    gjd_base = (1461 * (yy + 4716)) / 4 + 432  # GJD_MONTH_OFFSET[1](=428) + 4
    a2 = yy / 100
    gjd = gjd_base - 1524 + 2 - a2 + a2 / 4
    jd_jan4 = gjd >= sg ? gjd : gjd_base - 1524
    wday_jan4 = (jd_jan4 + 1) % 7
    iso_wday_jan4 = wday_jan4 == 0 ? 7 : wday_jan4
    mon_wk1 = jd_jan4 - (iso_wday_jan4 - 1)
    cw = (jd - mon_wk1) / 7 + 1
    unless frozen?
      @cweek = cw
      @cwyear = y
    end
    [y, cw]
  end

end
