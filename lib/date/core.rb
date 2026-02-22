# frozen_string_literal: true

# Implementation of ruby/date/ext/date/date_core.c
class Date
  include Comparable

  Error = Class.new(ArgumentError)

  # Initialize method
  # call-seq:
  #   Date.new(year = -4712, month = 1, mday = 1, start = Date::ITALY) -> date
  #
  # Returns a new Date object constructed from the given arguments:
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
    # Fast path: Integer arguments, Gregorian calendar
    # Avoids self.class.send, Hash allocation, redundant decode_year
    if year.is_a?(Integer) && year.abs < 579000 && month.is_a?(Integer) && day.is_a?(Integer)
      gregorian_fast = if start.is_a?(Float) && start.infinite?
                         start < 0  # GREGORIAN (-Infinity) only
                       elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                         year > REFORM_END_YEAR
                       end

      if gregorian_fast
        m = month
        m += 13 if m < 0
        raise Error unless m >= 1 && m <= 12

        leap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
        last = MONTH_DAYS[leap ? 1 : 0][m]
        d = day
        d = last + d + 1 if d < 0
        raise Error unless d >= 1 && d <= last

        j = (m < 3) ? 1 : 0
        y0 = year - j
        m0 = j.nonzero? ? m + 12 : m
        d0 = d - 1
        q1 = y0 / 100
        yc = (NS_DAYS_IN_4_YEARS * y0) / 4 - q1 + q1 / 4
        mc = (NS_DAYS_BEFORE_NEW_YEAR * m0 - 914) / 10

        @nth = 0
        @jd = yc + mc + d0 + NS_EPOCH
        @sg = start
        @year = year
        @month = m
        @day = d
        @has_jd = true
        @has_civil = true
        @df = nil
        @sf = nil
        @of = nil
        return self
      end
    end

    # Original path: handles non-Integer args, Julian/reform dates, fractional days
    y = year
    m = month
    d = day
    sg = start
    fr2 = 0

    # argument type checking
    if y
      raise TypeError, "invalid year (not numeric)" unless year.is_a?(Numeric)
    end
    if m
      raise TypeError, "invalid month (not numeric)" unless month.is_a?(Numeric)
    end
    if d
      raise TypeError, "invalid day (not numeric)" unless day.is_a?(Numeric)
      # Check if there is a decimal part.
      d_trunc, fr = d_trunc_with_frac(d)
      d = d_trunc
      fr2 = fr if fr.nonzero?
    end

    sg = self.class.send(:valid_sg, sg)
    style = self.class.send(:guess_style, y, sg)

    if style < 0
      # gregorian calendar only
      result = self.class.send(:valid_gregorian_p, y, m, d)
      raise Error unless result

      nth, ry = self.class.send(:decode_year, y, -1)
      rm = result[:rm]
      rd = result[:rd]

      @nth = canon(nth)
      @jd = 0
      @sg = sg
      @year = ry
      @month = rm
      @day = rd
      @has_jd = false
      @has_civil = true
      @df = nil
      @sf = nil
      @of = nil
    else
      # full validation
      result = self.class.send(:valid_civil_p, y, m, d, sg)
      raise Error unless result

      nth = result[:nth]
      ry = result[:ry]
      rm = result[:rm]
      rd = result[:rd]
      rjd = result[:rjd]

      @nth = canon(nth)
      @jd = rjd
      @sg = sg
      @year = ry
      @month = rm
      @day = rd
      @has_jd = true
      @has_civil = true
      @df = nil
      @sf = nil
      @of = nil
    end

    # Add any decimal parts.
    if fr2.nonzero?
      new_date = self + fr2
      @nth = new_date.instance_variable_get(:@nth)
      @jd = new_date.instance_variable_get(:@jd)
      @sg = new_date.instance_variable_get(:@sg)
      @year = new_date.instance_variable_get(:@year)
      @month = new_date.instance_variable_get(:@month)
      @day = new_date.instance_variable_get(:@day)
      @has_jd = new_date.instance_variable_get(:@has_jd)
      @has_civil = new_date.instance_variable_get(:@has_civil)
      @df = new_date.instance_variable_get(:@df)
      @sf = new_date.instance_variable_get(:@sf)
      @of = new_date.instance_variable_get(:@of)
    end

    self
  end

  # Class methods
  class << self
    # Same as `Date.new`.
    alias_method :civil, :new

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
      # Fast path: Integer args, non-Julian start
      if year.is_a?(Integer) && month.is_a?(Integer) && day.is_a?(Integer)
        gregorian_fast = if start.is_a?(Float) && start.infinite?
                           start < 0
                         elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                           true
                         end

        if gregorian_fast
          return false if month < 1 || month > 12
          leap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
          return day >= 1 && day <= MONTH_DAYS[leap ? 1 : 0][month]
        end
      end

      return false unless numeric?(year)
      return false unless numeric?(month)
      return false unless numeric?(day)

      result = valid_civil_sub(year, month, day, start, 0)

      !result.nil?
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
      # Fast path: Integer jd in common range, valid start
      if jd.is_a?(Integer) && jd >= 0 && jd < CM_PERIOD
        valid_start = if start.is_a?(Float) && start.infinite?
                        true
                      elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                        true
                      end

        if valid_start
          obj = allocate
          obj.instance_variable_set(:@nth, 0)
          obj.instance_variable_set(:@jd, jd)
          obj.instance_variable_set(:@sg, start)
          obj.instance_variable_set(:@year, 0)
          obj.instance_variable_set(:@month, 0)
          obj.instance_variable_set(:@day, 0)
          obj.instance_variable_set(:@has_jd, true)
          obj.instance_variable_set(:@has_civil, false)
          obj.instance_variable_set(:@df, nil)
          obj.instance_variable_set(:@sf, nil)
          obj.instance_variable_set(:@of, nil)
          return obj
        end
      end

      # Original path
      j = 0
      fr = 0
      sg = start

      sg = valid_sg(start) if start

      if jd
        raise TypeError, "invalid jd (not numeric)" unless jd.is_a?(Numeric)

        j, fr = value_trunc(jd)
      end

      nth, rjd = decode_jd(j)

      ret = d_simple_new_internal(nth, rjd, sg, 0, 0, 0, HAVE_JD)

      ret = ret + fr if fr.nonzero?

      ret
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
    def valid_jd?(jd, start = DEFAULT_SG)
      # All Numeric jd values are valid; skip valid_jd_sub/valid_sg chain
      return true if jd.is_a?(Numeric)
      return true if jd.respond_to?(:to_int)

      false
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
      if year.is_a?(Integer)
        return (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
      end
      raise TypeError, "invalid year (not numeric)" unless numeric?(year)

      _, ry = decode_year(year, -1)

      c_gregorian_leap_p?(ry)
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
      if year.is_a?(Integer)
        return (year % 4).zero?
      end
      raise TypeError, "invalid year (not numeric)" unless numeric?(year)

      _, ry = decode_year(year, +1)

      c_julian_leap_p?(ry)
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
      # Fast path: Integer args, Gregorian calendar
      if year.is_a?(Integer) && year.abs < 579000 && yday.is_a?(Integer)
        gregorian_fast = if start.is_a?(Float) && start.infinite?
                           start < 0
                         elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                           year > REFORM_END_YEAR
                         end

        if gregorian_fast
          leap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
          days_in_year = leap ? 366 : 365
          d = yday
          d = days_in_year + d + 1 if d < 0
          raise Error unless d >= 1 && d <= days_in_year

          rjd = c_gregorian_civil_to_jd(year, 1, 1) + d - 1

          obj = allocate
          obj.instance_variable_set(:@nth, 0)
          obj.instance_variable_set(:@jd, rjd)
          obj.instance_variable_set(:@sg, start)
          obj.instance_variable_set(:@year, 0)
          obj.instance_variable_set(:@month, 0)
          obj.instance_variable_set(:@day, 0)
          obj.instance_variable_set(:@has_jd, true)
          obj.instance_variable_set(:@has_civil, false)
          obj.instance_variable_set(:@df, nil)
          obj.instance_variable_set(:@sf, nil)
          obj.instance_variable_set(:@of, nil)
          return obj
        end
      end

      # Original path
      y = year
      d = yday
      fr2 = 0
      sg = start

      if y
        raise TypeError, "invalid year (not numeric)" unless year.is_a?(Numeric)
      end
      if d
        raise TypeError, "invalid yday (not numeric)" unless yday.is_a?(Numeric)
        d_trunc, fr = value_trunc(d)
        d = d_trunc
        fr2 = fr if fr.nonzero?
      end

      result = valid_ordinal_p(year, yday, start)
      raise Error unless result

      nth = result[:nth]
      rjd = result[:rjd]

      obj = d_simple_new_internal(nth, rjd, sg, 0, 0, 0, HAVE_JD)

      obj = obj + fr2 if fr2.nonzero?

      obj
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
      # Fast path: Integer args, non-Julian start
      if year.is_a?(Integer) && day.is_a?(Integer)
        gregorian_fast = if start.is_a?(Float) && start.infinite?
                           start < 0
                         elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                           true
                         end

        if gregorian_fast
          leap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
          days_in_year = leap ? 366 : 365
          d = day
          d = days_in_year + d + 1 if d < 0
          return d >= 1 && d <= days_in_year
        end
      end

      return false unless numeric?(year)
      return false unless numeric?(day)

      result = valid_ordinal_sub(year, day, start, false)

      !result.nil?
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
      # Fast path: Integer args, Gregorian calendar
      if cwyear.is_a?(Integer) && cwyear.abs < 579000 && cweek.is_a?(Integer) && cwday.is_a?(Integer)
        gregorian_fast = if start.is_a?(Float) && start.infinite?
                           start < 0
                         elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                           cwyear > REFORM_END_YEAR
                         end

        if gregorian_fast
          # Validate cwday (handle negative)
          d = cwday
          d += 8 if d < 0
          raise Error unless d >= 1 && d <= 7

          # JD of Jan 1 and ISO week metadata
          jd_jan1 = c_gregorian_civil_to_jd(cwyear, 1, 1)

          # Max ISO weeks: 53 if Jan 1 is Thursday, or leap year and Jan 1 is Wednesday
          p_val = (jd_jan1 + 1) % 7  # 0=Sun..6=Sat
          p_val = 7 if p_val == 0     # Convert to ISO (1=Mon..7=Sun)
          leap = (cwyear % 4 == 0) && (cwyear % 100 != 0 || cwyear % 400 == 0)
          max_weeks = (p_val == 4 || (leap && p_val == 3)) ? 53 : 52

          # Handle negative week
          w = cweek
          w = max_weeks + w + 1 if w < 0
          raise Error unless w >= 1 && w <= max_weeks

          # Compute JD: Monday of week 1 + offset
          rjd2 = jd_jan1 + 3
          rjd = (rjd2 - (rjd2 % 7)) + 7 * (w - 1) + (d - 1)

          obj = allocate
          obj.instance_variable_set(:@nth, 0)
          obj.instance_variable_set(:@jd, rjd)
          obj.instance_variable_set(:@sg, start)
          obj.instance_variable_set(:@year, 0)
          obj.instance_variable_set(:@month, 0)
          obj.instance_variable_set(:@day, 0)
          obj.instance_variable_set(:@has_jd, true)
          obj.instance_variable_set(:@has_civil, false)
          obj.instance_variable_set(:@df, nil)
          obj.instance_variable_set(:@sf, nil)
          obj.instance_variable_set(:@of, nil)
          return obj
        end
      end

      # Original path
      y = cwyear
      w = cweek
      d = cwday
      fr2 = 0
      sg = start

      if y
        raise TypeError, "invalid year (not numeric)" unless cwyear.is_a?(Numeric)
      end
      if w
        raise TypeError, "invalid cweek (not numeric)" unless cweek.is_a?(Numeric)
        w = w.to_i
      end
      if d
        raise TypeError, "invalid cwday (not numeric)" unless cwday.is_a?(Numeric)
        d_trunc, fr = value_trunc(d)
        d = d_trunc
        fr2 = fr if fr.nonzero?
      end

      sg = valid_sg(start) if start

      result = valid_commercial_p(y, w, d, sg)
      raise Error unless result

      nth = result[:nth]
      rjd = result[:rjd]

      obj = d_simple_new_internal(nth, rjd, sg, 0, 0, 0, HAVE_JD)

      obj = obj + fr2 if fr2.nonzero?

      obj
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
      # Fast path: Integer args, non-Julian start
      if year.is_a?(Integer) && week.is_a?(Integer) && day.is_a?(Integer)
        gregorian_fast = if start.is_a?(Float) && start.infinite?
                           start < 0
                         elsif start.is_a?(Integer) && start >= REFORM_BEGIN_JD && start <= REFORM_END_JD
                           true
                         end

        if gregorian_fast
          # Validate cwday (handle negative)
          d = day
          d += 8 if d < 0
          return false unless d >= 1 && d <= 7

          # Max ISO weeks: 53 if Jan 1 is Thursday, or leap year and Jan 1 is Wednesday
          jd_jan1 = c_gregorian_civil_to_jd(year, 1, 1)
          p_val = (jd_jan1 + 1) % 7  # 0=Sun..6=Sat
          p_val = 7 if p_val == 0     # Convert to ISO (1=Mon..7=Sun)
          leap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0)
          max_weeks = (p_val == 4 || (leap && p_val == 3)) ? 53 : 52

          # Handle negative week
          w = week
          w = max_weeks + w + 1 if w < 0
          return w >= 1 && w <= max_weeks
        end
      end

      return false unless numeric?(year)
      return false unless numeric?(week)
      return false unless numeric?(day)

      result = valid_commercial_sub(year, week, day, start, false)

      !result.nil?
    end

    # call-seq:
    #   Date.today(start = Date::ITALY) -> date
    #
    # Returns a new \Date object constructed from the present date:
    #
    #   Date.today.to_s # => "2022-07-06"
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    def today(start = DEFAULT_SG)
      time = Time.now

      obj = allocate
      obj.instance_variable_set(:@nth, 0)
      obj.instance_variable_set(:@year, time.year)
      obj.instance_variable_set(:@month, time.mon)
      obj.instance_variable_set(:@day, time.mday)
      obj.instance_variable_set(:@jd, nil)
      obj.instance_variable_set(:@sg, start)
      obj.instance_variable_set(:@has_jd, false)
      obj.instance_variable_set(:@has_civil, true)

      obj
    end

    # :nodoc:
    # C: date_s__load — for Marshal format 1.4, 1.6, 1.8 (u: prefix)
    def _load(s)
      a = Marshal.load(s)
      obj = allocate
      obj.marshal_load(a)
      obj
    end

    private

    # Optimized: Gregorian date -> Julian Day Number
    def gregorian_civil_to_jd(year, month, day)
      # Shift epoch to March 1 of year 0 (Jan/Feb belong to previous year)
      j = (month < 3) ? 1 : 0
      y0 = year - j
      m0 = j == 1 ? month + 12 : month
      d0 = day - 1

      # Calculate year contribution with leap year correction
      q1 = y0 / NS_YEARS_PER_CENTURY
      yc = (NS_DAYS_IN_4_YEARS * y0) / 4 - q1 + (q1 / 4)

      # Calculate month contribution using integer arithmetic
      mc = (NS_CIVIL_MONTH_COEFF * m0 - NS_CIVIL_MONTH_OFFSET) / NS_CIVIL_MONTH_DIVISOR

      # Combine and add epoch offset to get JDN
      yc + mc + d0 + NS_EPOCH
    end

    def julian_civil_to_jd(y, m, d)
      # Traditional Julian calendar algorithm
      y2 = y
      m2 = m

      if m2 <= 2
        y2 -= 1
        m2 += 12
      end

      (365.25 * (y2 + 4716)).floor + (30.6001 * (m2 + 1)).floor + d - 1524
    end

    def validate_ordinal(year, yday, sg)
      # Handling negative day of year
      if yday < 0
        # Counting backwards from the end of the year
        last_jd, _ = c_find_ldoy(year, sg)
        return nil unless last_jd

        # Recalculate the total number of days in the year from the calculated JD
        adjusted_jd = last_jd + yday + 1
        y, d = jd_to_ordinal(adjusted_jd, sg)

        # Invalid if the year does not match
        return nil if y != year

        yday = d
      end

      # Calculate jd from the day of the year
      nth, ry, _, _ = decode_year(year, sg)
      first_jd, ns = c_find_fdoy(ry, sg)

      return nil unless first_jd

      jd = first_jd + yday - 1

      # Verify that the calculated jd actually belongs to the specified year
      verify_y, verify_d = jd_to_ordinal(jd, sg)
      return nil if verify_y != ry || verify_d != yday

      [nth, ry, yday, jd, ns]
    end

    def extract_fraction(value)
      if value.is_a?(Rational) || value.is_a?(Float)
        int_part = value.floor
        frac_part = value - int_part
        [int_part, frac_part]
      else
        [value.to_i, 0]
      end
    end

    def jd_to_ordinal(jd, sg)
      year, _, _ = jd_to_civil_internal(jd, sg)
      first_jd, _ = c_find_fdoy(year, sg)
      yday = jd - first_jd + 1

      [year, yday]
    end

    def validate_commercial(year, week, day, sg)
      if day < 0
        day += 8  # -1 -> 7 (Sun), -7 -> 1 (Mon)
      end

      return nil if day < 1 || day > 7

      if week < 0
        next_year_jd, ns = commercial_to_jd_internal(year + 1, 1, 1, sg)
        return nil unless next_year_jd

        adjusted_jd = next_year_jd + week * 7
        y2, w2, _ = jd_to_commercial_internal(adjusted_jd, sg)

        return nil if y2 != year

        week = w2
      end

      # Calculate jd from ISO week date
      nth, ry, _, _ = decode_year(year, sg)
      jd, ns = commercial_to_jd_internal(ry, week, day, sg)

      return nil unless jd

      verify_y, verify_w, verify_d = jd_to_commercial_internal(jd, sg)
      return nil if verify_y != ry || verify_w != week || verify_d != day

      [nth, ry, week, day, jd, ns]
    end

    def commercial_to_jd_internal(cwyear, cweek, cwday, sg)
      # Calculating ISO week date(The week containing January 4 is week 1)
      jan4_jd = gregorian_civil_to_jd(cwyear, 1, 4)

      # Day of the week on which January 4th falls
      # (0 = Sun, 1 = Mon, ..., 6 = Sat)
      jan4_wday = (jan4_jd + 1) % 7

      # Monday of week 1
      week1_mon = jan4_jd - jan4_wday + 1

      # jd for a specified weekday
      jd = week1_mon + (cweek - 1) * 7 + (cwday - 1)

      # If before sg, it is the Julian calendar
      ns = jd >= sg ? 1 : 0

      [jd, ns]
    end

    def jd_to_commercial_internal(jd, sg)
      # get date from jd
      year, _, _ = jd_to_civil_internal(jd, sg)

      # calculate jd for January 4 of that year
      jan4_jd = gregorian_civil_to_jd(year, 1, 4)
      jan4_wday = (jan4_jd + 1) % 7
      week1_mon = jan4_jd - jan4_wday + 1

      # If jd is before the first week, it belongs to the previous year
      if jd < week1_mon
        year -= 1
        jan4_jd = gregorian_civil_to_jd(year, 1, 4)
        jan4_wday = (jan4_jd + 1) % 7
        week1_mon = jan4_jd - jan4_wday + 1
      end

      # check the first week of the next year
      next_jan4 = gregorian_civil_to_jd(year + 1, 1, 4)
      next_jan4_wday = (next_jan4 + 1) % 7
      next_week1_mon = next_jan4 - next_jan4_wday + 1

      if jd >= next_week1_mon
        year += 1
        week1_mon = next_week1_mon
      end

      # Calculate the week number
      week = (jd - week1_mon) / 7 + 1

      # week(1 = mon, ..., 7 = sun）
      cwday = (jd + 1) % 7
      cwday = 7 if cwday.zero?

      [year, week, cwday]
    end

    def jd_to_civil_internal(jd, sg)
      # Does it overlap with jd_to_civil?
      # Calculate the date from jd (using existing methods)
      # simple version
      r0 = jd - NS_EPOCH

      n1 = 4 * r0 + 3
      q1 = n1 / NS_DAYS_IN_400_YEARS
      r1 = (n1 % NS_DAYS_IN_400_YEARS) / 4

      n2 = 4 * r1 + 3
      u2 = NS_YEAR_MULTIPLIER * n2
      q2 = u2 >> 32
      r2 = (u2 & 0xFFFFFFFF) / NS_YEAR_MULTIPLIER / 4

      n3 = NS_MONTH_COEFF * r2 + NS_MONTH_OFFSET
      q3 = n3 >> 16
      r3 = (n3 & 0xFFFF) / NS_MONTH_COEFF

      y0 = NS_YEARS_PER_CENTURY * q1 + q2
      j = (r2 >= NS_DAYS_BEFORE_NEW_YEAR) ? 1 : 0

      year = y0 + j
      month = j == 1 ? q3 - 12 : q3
      day = r3 + 1

      [year, month, day]
    end

    def valid_civil_date?(year, month, day, sg)
      return false if month < 1 || month > 12

      if sg == GREGORIAN || sg < 0
        last_day = last_day_of_month_gregorian(year, month)
      elsif sg == JULIAN || sg > 0
        last_day = last_day_of_month_julian(year, month)
      else
        # Calculate (calendar reform period - jd) and determine
        jd = gregorian_civil_to_jd(year, month, day)

        if jd < sg
          last_day = last_day_of_month_julian(year, month)
        else
          last_day = last_day_of_month_gregorian(year, month)
        end
      end

      return false if day < 1 || day > last_day

      true
    end

    def last_day_of_month_gregorian(y, m)
      return nil if m < 1 || m > 12

      leap_index = gregorian_leap?(y) ? 1 : 0
      MONTH_DAYS[leap_index][m]
    end

    def last_day_of_month_julian(y, m)
      return nil if m < 1 || m > 12

      leap_index = julian_leap?(y) ? 1 : 0
      MONTH_DAYS[leap_index][m]
    end

    def civil_to_jd_with_check(year, month, day, sg)
      return nil unless valid_civil_date?(year, month, day, sg)

      jd, ns = civil_to_jd(year, month, day, sg)

      [jd, ns]
    end

    def civil_to_jd(year, month, day, sg)
      if sg == GREGORIAN
        jd = gregorian_civil_to_jd(year, month, day)

        return [jd, 1]
      end

      jd = gregorian_civil_to_jd(year, month, day)

      if jd < sg
        jd = julian_civil_to_jd(year, month, day)
        ns = 0
      else
        ns = 1
      end

      [jd, ns]
    end

    def last_day_of_month_for_sg(year, month, sg)
      last_day_of_month_gregorian(year, month)
    end

    def validate_civil(year, month, day, sg)
      month += 13 if month < 0
      return nil if month < 1 || month > 12

      if day < 0
        last_day = last_day_of_month_gregorian(year, month)
        return nil unless last_day
        day = last_day + day + 1
      end

      last_day = last_day_of_month_gregorian(year, month)
      return nil if day < 1 || day > last_day

      nth, ry = decode_year(year, -1)

      jd, ns = civil_to_jd_with_style(ry, month, day, sg)

      [nth, ry, month, day, jd, ns]
    end

    def civil_to_jd_with_style(year, month, day, sg)
      jd = gregorian_civil_to_jd(year, month, day)

      if jd < sg
        jd = julian_civil_to_jd(year, month, day)
        ns = 0
      else
        ns = 1
      end

      [jd, ns]
    end

    def convert_to_integer(value)
      if value.respond_to?(:to_int)
        value.to_int
      elsif value.is_a?(Numeric)
        value.to_i
      else
        value
      end
    end

    def numeric?(value)
      value.is_a?(Numeric) || value.respond_to?(:to_int)
    end

    def valid_civil_sub(year, month, day, start, need_jd)
      year = convert_to_integer(year)
      month = convert_to_integer(month)
      day = convert_to_integer(day)

      start = valid_sg(start)

      return nil if month < 1 || month > 12

      leap_year = start == JULIAN ? julian_leap?(year) : gregorian_leap?(year)
      max_day = MONTH_DAYS[leap_year ? 1 : 0][month]

      return nil if day < 1 || day > max_day

      need_jd ? civil_to_jd(year, month, day, start) : 0
    end

    def valid_sg(start)
      unless c_valid_start_p(start)
        warn "invalid start is ignored"
        return 0
      end

      start
    end

    def c_valid_start_p(start)
      return false unless start.is_a?(Numeric)

      return false if start.respond_to?(:nan?) && start.nan?

      return true if start.respond_to?(:infinite?) && start.infinite?

      return false if start < REFORM_BEGIN_JD || start > REFORM_END_JD

      true
    end

    def valid_jd_sub(jd, start, need_jd)
      valid_sg(start)

      jd
    end

    def valid_commercial_sub(year, week, day, start, need_jd)
      week = convert_to_integer(week)
      day = convert_to_integer(day)

      valid_sg(start)

      result = valid_commercial_p(year, week, day, start)

      return nil unless result

      return 0 unless need_jd

      encode_jd(result[:nth], result[:rjd])
    end

    def valid_commercial_p(year, week, day, start)
      style = guess_style(year, start)

      if style.zero?
        int_year = year.to_i
        result = c_valid_commercial_p(int_year, week, day, start)
        return nil unless result

        nth, rjd = decode_jd(result[:jd])

        if f_zero_p?(nth)
          ry = int_year
        else
          ns = result[:ns]
          _, ry = decode_year(year, ns.nonzero? ? -1 : 1)
        end

       { nth: nth, ry: ry, rw: result[:rw], rd: result[:rd], rjd: rjd, ns: result[:ns] }
      else
        nth, ry = decode_year(year, style)
        result = c_valid_commercial_p(ry, week, day, style)
        return nil unless result

        { nth: nth, ry: ry, rw: result[:rw], rd: result[:rd], rjd: result[:jd], ns: result[:ns] }
      end
    end

    def guess_style(year, sg)
      return sg if sg.infinite?
      return year >= 0 ? GREGORIAN : JULIAN unless year.is_a?(Integer) && year.abs < (1 << 62)

      int_year = year.to_i
      if int_year < REFORM_BEGIN_YEAR
        JULIAN
      elsif int_year > REFORM_END_YEAR
        GREGORIAN
      else
        0
      end
    end

    def c_valid_commercial_p(year, week, day, sg)
      day += 8 if day < 0

      if week < 0
        rjd2, _ = c_commercial_to_jd(year + 1, 1, 1, sg)
        ry2, rw2, _ = c_jd_to_commercial(rjd2 + week * 7, sg)
        return nil if ry2 != year

        week = rw2
      end

      rjd, ns = c_commercial_to_jd(year, week, day, sg)
      ry2, rw, rd = c_jd_to_commercial(rjd, sg)

      return nil if year != ry2 || week != rw || day != rd

      { jd: rjd, ns: ns, rw: rw, rd: rd }
    end

    def c_commercial_to_jd(year, week, day, sg)
      rjd2, _ = c_find_fdoy(year, sg)
      rjd2 += 3

      # Calcurate ISO week number.
      rjd = (rjd2 - ((rjd2 - 1 + 1) % 7)) + 7 * (week - 1) + (day - 1)
      ns = (rjd < sg) ? 0 : 1

      [rjd, ns]
    end

    def c_jd_to_commercial(jd, sg)
      ry2, _, _ = c_jd_to_civil(jd - 3, sg)
      a = ry2

      rjd2, _ = c_commercial_to_jd(a + 1, 1, 1, sg)
      if jd >= rjd2
        ry = a + 1
      else
        rjd2, _ = c_commercial_to_jd(a, 1, 1, sg)
        ry = a
      end

      rw = 1 + (jd - rjd2) / 7
      rd = (jd + 1) % 7
      rd = 7 if rd.zero?

      [ry, rw, rd]
    end

    def c_find_fdoy(year, sg)
      if c_gregorian_only_p?(sg)
        jd = c_gregorian_fdoy(year)

        return [jd, 1]
      end

      # Keep existing loop for Julian/reform period
      (1..30).each do |d|
        result = c_valid_civil_p(year, 1, d, sg)

        return [result[:jd], result[:ns]] if result
      end

      [nil, nil]
    end

    def c_find_ldom(year, month, sg)
      if c_gregorian_only_p?(sg)
        jd = c_gregorian_ldom_jd(year, month)

        return [jd, 1]
      end

      # Keep existing loop for Julian/reform period
      (0..29).each do |i|
        result = c_valid_civil_p(year, month, 31 - i, sg)
        return [result[:jd], result[:ns]] if result
      end

      nil
    end

    def c_gregorian_fdoy(year)
      c_gregorian_civil_to_jd(year, 1, 1)
    end

    def c_jd_to_civil(jd, sg)
      # Fast path: pure Gregorian or date after switchover, within safe range
      if (c_gregorian_only_p?(sg) || jd >= sg) && ns_jd_in_range(jd)
        return c_gregorian_jd_to_civil(jd)
      end

      # Original algorithm for Julian calendar or extreme dates
      if jd < sg
        a = jd
      else
        x = ((jd - 1867216.25) / 36524.25).floor
        a = jd + 1 + x - (x / 4.0).floor
      end

      b = a + 1524
      c = ((b - 122.1) / 365.25).floor
      d = (365.25 * c).floor
      e = ((b - d) / 30.6001).floor
      dom = b - d - (30.6001 * e).floor

      if e <= 13
        m = e - 1
        y = c - 4716
      else
        m = e - 13
        y = c - 4715
      end

      [y.to_i, m.to_i, dom.to_i]
    end

    # Optimized: Julian Day Number -> Gregorian date
    def c_gregorian_jd_to_civil(jd)
      # The argument jd of c_gregorian_jd_to_civil implemented in C is of type int,
      # so it is converted to Integer.
      jd = jd.to_i unless jd.is_a?(Integer)

      # Convert JDN to rata die (March 1, Year 0 epoch)
      r0 = jd - NS_EPOCH

      # Extract century and day within 400-year cycle
      # Use Euclidean (floor) division for negative values
      n1 = 4 * r0 + 3
      q1 = n1 / NS_DAYS_IN_400_YEARS
      r1 = (n1 % NS_DAYS_IN_400_YEARS) / 4

      # Calculate year within century and day of year
      n2 = 4 * r1 + 3
      # Use 64-bit arithmetic to avoid overflow
      u2 = NS_YEAR_MULTIPLIER * n2
      q2 = u2 >> 32
      r2 = (u2 & 0xFFFFFFFF) / NS_YEAR_MULTIPLIER / 4

      # Calculate month and day using integer arithmetic
      n3 = NS_MONTH_COEFF * r2 + NS_MONTH_OFFSET
      q3 = n3 >> 16
      r3 = (n3 & 0xFFFF) / NS_MONTH_COEFF

      # Combine century and year
      y0 = NS_YEARS_PER_CENTURY * q1 + q2

      # Adjust for January/February (shift from fiscal year)
      j = (r2 >= NS_DAYS_BEFORE_NEW_YEAR) ? 1 : 0

      ry = y0 + j
      rm = j.nonzero? ? q3 - 12 : q3
      rd = r3 + 1

      [ry, rm, rd]
    end

    def c_gregorian_civil_to_jd(year, month, day)
      j = (month < 3) ? 1 : 0
      y0 = year - j
      m0 = j.nonzero? ? month + 12 : month
      d0 = day - 1

      q1 = y0 / 100
      yc = (NS_DAYS_IN_4_YEARS * y0) / 4 - q1 + q1 / 4

      mc = (NS_DAYS_BEFORE_NEW_YEAR * m0 - 914) / 10

      yc + mc + d0 + NS_EPOCH
    end

    def valid_civil_p(y, m, d, sg)
      style = guess_style(y, sg)

      if style.zero?
        # If year is a Fixnum
        int_year = y.to_i

        # Validate with c_valid_civil_p
        result = c_valid_civil_p(int_year, m, d, sg)
        return nil unless result

        # decode_jd
        nth, rjd = decode_jd(result[:jd])

        if f_zero_p?(nth)
          ry = int_year
        else
          ns = result[:ns]
          _, ry = decode_year(y, ns.nonzero? ? -1 : 1)
        end

        return { nth: nth, ry: ry, rm: result[:rm], rd: result[:rd], rjd: rjd, ns: result[:ns] }
      else
        # If year is a large number
        nth, ry = decode_year(y, style)

        result = style < 0 ? c_valid_gregorian_p(ry, m, d) : result = c_valid_julian_p(ry, m, d)
        return nil unless result

        # Calculate JD from civil
        rjd, ns = c_civil_to_jd(ry, result[:rm], result[:rd], style)

        return { nth: nth, ry: ry, rm: result[:rm], rd: result[:rd], rjd: rjd, ns: ns }
      end
    end

    def c_valid_civil_p(year, month, day, sg)
      month += 13 if month < 0
      return nil if month < 1 || month > 12

      rd = day
      if rd < 0
        result = c_find_ldom(year, month, sg)
        return nil unless result

        rjd2, _ = result
        ry2, rm2, rd2 = c_jd_to_civil(rjd2 + rd + 1, sg)
        return nil if ry2 != year || rm2 != month

        rd = rd2
      end

      rjd, ns = c_civil_to_jd(year, month, rd, sg)
      ry2, rm2, rd2 = c_jd_to_civil(rjd, sg)

      return nil if ry2 != year || rm2 != month || rd2 != rd

      { jd: rjd, ns: ns, rm: rm2, rd: rd }
    end

    def c_gregorian_ldom_jd(year, month)
      last_day = c_gregorian_last_day_of_month(year, month)
      c_gregorian_civil_to_jd(year, month, last_day)
    end

    def c_gregorian_last_day_of_month(year, month)
      MONTH_DAYS[gregorian_leap?(year) ? 1 : 0][month]
    end

    def c_civil_to_jd(year, month, day, sg)
      if c_gregorian_only_p?(sg)
        jd = c_gregorian_civil_to_jd(year, month, day)

        return [jd, 1]
      end

      # Calculate Gregorian JD using optimized algorithm
      jd = c_gregorian_civil_to_jd(year, month, day)

      if jd < sg
        y2 = year
        m2 = month
        if m2 <= 2
          y2 -= 1
          m2 += 12
        end
        jd = (365.25 * (y2 + 4716)).floor + (30.6001 * (m2 + 1)).floor + day - 1524
        ns = 0
      else
        ns = 1
      end

      [jd, ns]
    end

    def decode_jd(jd)
      nth = jd / CM_PERIOD
      rjd = f_zero_p?(nth) ? jd : jd % CM_PERIOD

      [nth, rjd]
    end

    def encode_jd(nth, rjd)
      f_zero_p?(nth) ? rjd : nth * CM_PERIOD + rjd
    end

    def decode_year(year, style)
      period = (style < 0) ? CM_PERIOD_GCY : CM_PERIOD_JCY

      if year.is_a?(Integer) && year.abs < (1 << 30)
        shifted = year + 4712
        nth = shifted / period

        shifted = shifted % period if f_nonzero_p?(nth)

        ry = shifted - 4712
      else
        shifted = year + 4712
        nth = shifted / period

        shifted = shifted % period if f_nonzero_p?(nth)

        ry = shifted.to_i - 4712
      end

      [nth, ry]
    end

    # Check if using pure Gregorian calendar (sg == -Infinity)
    def c_gregorian_only_p?(sg)
      sg.infinite? && sg < 0
    end

    def valid_ordinal_sub(year, day, start, need_jd)
      day = convert_to_integer(day)

      valid_sg(start)

      result = valid_ordinal_p(year, day, start)

      return nil unless result

      return 0 unless need_jd

      encode_jd(result[:nth], result[:rjd])
    end

    def valid_ordinal_p(year, day, start)
      style = guess_style(year, start)

      if style.zero?
        int_year = year.to_i
        result = c_valid_ordinal_p(int_year, day, start)

        return nil unless result

        nth, rjd = decode_jd(result[:jd])

        if f_zero_p?(nth)
          ry = int_year
        else
          ns = result[:ns]
          _, ry = decode_year(year, ns.nonzero? ? -1 : 1)
        end

        return { nth: nth, ry: ry, rd: result[:rd], rjd: rjd, ns: result[:ns] }
      else
        nth, ry = decode_year(year, style)
        result = c_valid_ordinal_p(ry, day, style)
        return nil unless result

        return { nth: nth, ry: ry, rd: result[:rd], rjd: result[:jd], ns: result[:ns] }
      end
    end

    def c_valid_ordinal_p(year, day, sg)
      rd = day
      if rd < 0
        result = c_find_ldoy(year, sg)
        return nil unless result

        rjd2, _ = result
        ry2, rd2 = c_jd_to_ordinal(rjd2 + rd + 1, sg)
        return nil if ry2 != year

         rd = rd2
      end

      rjd, ns = c_ordinal_to_jd(year, rd, sg)
      ry2, rd2 = c_jd_to_ordinal(rjd, sg)

      return nil if ry2 != year || rd2 != rd

      { jd: rjd, ns: ns, rd: rd }
    end

    def c_find_ldoy(year, sg)
      if c_gregorian_only_p?(sg)
        jd = c_gregorian_ldoy(year)

        return [jd, 1]
      end

      # Keep existing loop for Julian/reform period
      (0..29).each do |i|
        result = c_valid_civil_p(year, 12, 31 - i, sg)

        return [result[:jd], result[:ns]] if result
      end

      nil
    end

    # O(1) last day of year for Gregorian calendar
    def c_gregorian_ldoy(year)
      c_gregorian_civil_to_jd(year, 12, 31)
    end

    def c_jd_to_ordinal(jd, sg)
      ry, _, _ = c_jd_to_civil(jd, sg)
      rjd, _ = c_find_fdoy(ry, sg)

      rd = (jd - rjd) + 1

      [ry, rd]
    end

    def c_ordinal_to_jd(year, day, sg)
      rjd, _ = c_find_fdoy(year, sg)
      rjd += day - 1
      ns = (rjd < sg) ? 0 : 1

      [rjd, ns]
    end

    def f_zero_p?(x)
      case x
      when Integer
        x.zero?
      when Rational
        x.numerator == 0
      else
        x == 0
      end
    end

    def f_nonzero_p?(x)
      !f_zero_p?(x)
    end

    def c_gregorian_leap_p?(year)
      !!(((year % 4).zero? && (year % 100).nonzero?) || (year % 400).zero?)
    end

    def c_julian_leap_p?(year)
      (year % 4).zero?
    end

    def new_with_jd(nth, jd, start)
      new_with_jd_and_time(nth, jd, nil, nil, nil, start)
    end

    def new_with_jd_and_time(nth, jd, df, sf, of, start)
      obj = allocate
      obj.send(:_init_with_jd, nth, jd, df, sf, of, start)
      obj
    end

    def valid_gregorian_p(y, m, d)
      decode_year(y, -1)

      c_valid_gregorian_p(y, m, d)
    end

    def c_valid_gregorian_p(y, m, d)
      m += 13 if m < 0
      return nil if m < 1 || m > 12

      last = c_gregorian_last_day_of_month(y, m)
      d = last + d + 1 if d < 0
      return nil if d < 1 || d > last

      { rm: m, rd: d }
    end

    def c_valid_julian_p(y, m, d)
      m += 13 if m < 0
      return nil if m < 1 || m > 12

      last = c_julian_last_day_of_month(y, m)
      d = last + d + 1 if d < 0
      return nil if d < 1 || d > last

      { rm: m, rd: d }
    end

    def c_julian_last_day_of_month(y, m)
      raise Error unless m >= 1 && m <= 12

      MONTH_DAYS[julian_leap?(y) ? 1 : 0][m]
    end

    # Create a simple Date object.
    def d_lite_s_alloc_simple
      obj = allocate
      obj.instance_variable_set(:@nth, 0)
      obj.instance_variable_set(:@jd, 0)
      obj.instance_variable_set(:@sg, DEFAULT_SG)
      obj.instance_variable_set(:@df, nil)
      obj.instance_variable_set(:@sf, nil)
      obj.instance_variable_set(:@of, nil)
      obj.instance_variable_set(:@year, nil)
      obj.instance_variable_set(:@month, nil)
      obj.instance_variable_set(:@day, nil)
      obj.instance_variable_set(:@has_jd, true)
      obj.instance_variable_set(:@has_civil, false)

      obj
    end

    # Create a complex Date object.
    def d_lite_s_alloc_complex
      obj = allocate
      obj.instance_variable_set(:@nth, 0)
      obj.instance_variable_set(:@jd, 0)
      obj.instance_variable_set(:@sg, DEFAULT_SG)
      obj.instance_variable_set(:@df, nil)
      obj.instance_variable_set(:@sf, nil)
      obj.instance_variable_set(:@of, nil)
      obj.instance_variable_set(:@year, nil)
      obj.instance_variable_set(:@month, nil)
      obj.instance_variable_set(:@day, nil)
      obj.instance_variable_set(:@hour, nil)
      obj.instance_variable_set(:@min, nil)
      obj.instance_variable_set(:@sec, nil)
      obj.instance_variable_set(:@has_jd, true)
      obj.instance_variable_set(:@has_civil, false)

      obj
    end

    def value_trunc(value)
      if value.is_a?(Integer)
        [value, 0]
      elsif value.is_a?(Float) || value.is_a?(Rational)
        trunc = value.truncate
        frac = value - trunc

        [trunc, frac]
      else
        [value.to_i, 0]
      end
    end

    def d_simple_new_internal(nth, jd, sg, year, mon, mday, flags)
      obj = allocate
      obj.instance_variable_set(:@nth, canon(nth))
      obj.instance_variable_set(:@jd, jd)
      obj.instance_variable_set(:@sg, sg)
      obj.instance_variable_set(:@year, year)
      obj.instance_variable_set(:@month, mon)
      obj.instance_variable_set(:@day, mday)
      obj.instance_variable_set(:@has_jd, (flags & HAVE_JD).nonzero?)
      obj.instance_variable_set(:@has_civil, (flags & HAVE_CIVIL).nonzero?)
      obj.instance_variable_set(:@df, nil)
      obj.instance_variable_set(:@sf, nil)
      obj.instance_variable_set(:@of, nil)

      obj
    end

    def canon(x)
      x.is_a?(Rational) && x.denominator == 1 ? x.numerator : x
    end

    def ns_jd_in_range(jd)
      jd >= NS_JD_MIN && jd <= NS_JD_MAX
    end

    def check_limit(str, limit)
      unless str.is_a?(String)
        begin
          str = str.to_str
        rescue NoMethodError
          raise TypeError, "no implicit conversion of #{str.class} into String"
        end
      end

      if limit && str.length > limit
        raise ArgumentError, "string length (#{str.length}) exceeds the limit #{limit}"
      end

      str
    end
  end

  # Instance methods

  # call-seq:
  #   year -> integer
  #
  # Returns the year:
  #
  #   Date.new(2001, 2, 3).year    # => 2001
  #   (Date.new(1, 1, 1) - 1).year # => 0
  def year
    m_real_year
  end

  # call-seq:
  #   mon -> integer
  #
  # Returns the month in range (1..12):
  #
  #   Date.new(2001, 2, 3).mon # => 2
  def month
    m_mon
  end
  alias mon month

  def day
    m_mday
  end
  alias mday day

  # call-seq:
  #    d.jd  ->  integer
  #
  # Returns the Julian day number.  This is a whole number, which is
  # adjusted by the offset as the local time.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').jd    #=> 2451944
  #    DateTime.new(2001,2,3,4,5,6,'-7').jd    #=> 2451944
  def jd
    m_real_jd
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
  def start
    @sg
  end

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
  def <=>(other)
    if other.is_a?(Date) &&
       @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       other.instance_variable_get(:@nth) == 0 &&
       other.instance_variable_get(:@has_jd) &&
       other.instance_variable_get(:@df).nil? &&
       other.instance_variable_get(:@sf).nil? &&
       other.instance_variable_get(:@of).nil?
      return @jd <=> other.instance_variable_get(:@jd)
    end

    case other
    when Date
      m_canonicalize_jd
      other.send(:m_canonicalize_jd)

      a_nth = m_nth
      b_nth = other.send(:m_nth)

      cmp = a_nth <=> b_nth
      return cmp if cmp.nonzero?

      a_jd = m_jd
      b_jd = other.send(:m_jd)

      cmp = a_jd <=> b_jd
      return cmp if cmp.nonzero?

      a_df = m_df
      b_df = other.send(:m_df)

      cmp = a_df <=> b_df
      return cmp if cmp.nonzero?

      a_sf = m_sf
      b_sf = other.send(:m_sf)

      a_sf <=> b_sf
    when Numeric
      ajd <=> other
    else
      begin
        l, r = other.coerce(self)
        l <=> r
      rescue NoMethodError
        nil
      end
    end
  end

  def <(other) # :nodoc:
    if other.is_a?(Date) &&
       @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       other.instance_variable_get(:@nth) == 0 &&
       other.instance_variable_get(:@has_jd) &&
       other.instance_variable_get(:@df).nil? &&
       other.instance_variable_get(:@sf).nil? &&
       other.instance_variable_get(:@of).nil?
      return @jd < other.instance_variable_get(:@jd)
    end
    super
  end

  def >(other) # :nodoc:
    if other.is_a?(Date) &&
       @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       other.instance_variable_get(:@nth) == 0 &&
       other.instance_variable_get(:@has_jd) &&
       other.instance_variable_get(:@df).nil? &&
       other.instance_variable_get(:@sf).nil? &&
       other.instance_variable_get(:@of).nil?
      return @jd > other.instance_variable_get(:@jd)
    end
    super
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
  def ===(other)
    if other.is_a?(Date) &&
       @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       @jd >= 0 && @jd < CM_PERIOD &&
       other.instance_variable_get(:@nth) == 0 &&
       other.instance_variable_get(:@has_jd) &&
       other.instance_variable_get(:@df).nil? &&
       other.instance_variable_get(:@sf).nil? &&
       other.instance_variable_get(:@of).nil?
      return @jd == other.instance_variable_get(:@jd)
    end

    return equal_gen(other) unless other.is_a?(Date)

    # Call equal_gen even if the Gregorian calendars do not match.
    return equal_gen(other) unless m_gregorian_p? == other.send(:m_gregorian_p?)

    m_canonicalize_jd
    other.send(:m_canonicalize_jd)

    a_nth = m_nth
    b_nth = other.send(:m_nth)
    a_jd = m_local_jd
    b_jd = other.send(:m_local_jd)

    a_nth == b_nth && a_jd == b_jd
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
  def >>(n)
    if n.is_a?(Integer) && @of.nil? && @nth == 0 && @has_civil
      sg = @sg
      gregorian_fast = if sg.is_a?(Float) && sg.infinite?
                         sg < 0
                       elsif sg.is_a?(Integer) && sg >= REFORM_BEGIN_JD && sg <= REFORM_END_JD
                         @year > REFORM_END_YEAR
                       end
      if gregorian_fast
        t = @year * 12 + (@month - 1) + n
        y = t / 12
        m = (t % 12) + 1
        d = @day

        leap = (y % 4 == 0) && (y % 100 != 0 || y % 400 == 0)
        last = MONTH_DAYS[leap ? 1 : 0][m]
        d = last if d > last

        obj = self.class.allocate
        obj._init_simple_with_civil(y, m, d, sg)
        return obj
      end
    end

    # Calculate years and months
    t = m_real_year * 12 + (m_mon - 1) + n

    if t.is_a?(Integer) && t.abs < (1 << 62)
      # Fixnum
      y = t / 12
      m = (t % 12) + 1
    else
      # Bignum
      y = t.div(12)
      m = (t % 12).to_i + 1
    end

    d = m_mday
    sg = m_sg

    # Decrement days until a valid date.
    result = nil
    loop do
      result = self.class.send(:valid_civil_p, y, m, d, sg)
      break if result

      d -= 1
      raise Error if d < 1
    end

    nth = result[:nth]
    rjd = result[:rjd]
    rjd2 = self.class.send(:encode_jd, nth, rjd)

    self + (rjd2 - m_real_local_jd)
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
  def <<(n)
    if n.is_a?(Integer) && @of.nil? && @nth == 0 && @has_civil
      sg = @sg
      gregorian_fast = if sg.is_a?(Float) && sg.infinite?
                         sg < 0
                       elsif sg.is_a?(Integer) && sg >= REFORM_BEGIN_JD && sg <= REFORM_END_JD
                         @year > REFORM_END_YEAR
                       end
      if gregorian_fast
        t = @year * 12 + (@month - 1) - n
        y = t / 12
        m = (t % 12) + 1
        d = @day

        leap = (y % 4 == 0) && (y % 100 != 0 || y % 400 == 0)
        last = MONTH_DAYS[leap ? 1 : 0][m]
        d = last if d > last

        obj = self.class.allocate
        obj._init_simple_with_civil(y, m, d, sg)
        return obj
      end
    end

    raise TypeError, "expected numeric" unless n.is_a?(Numeric)

    t = m_real_year * 12 + (m_mon - 1) - n

    if t.is_a?(Integer) && t.abs < (1 << 62)
      y = t / 12
      m = (t % 12) + 1
    else
      y = t.div(12)
      m = (t % 12).to_i + 1
    end

    d = m_mday
    sg = m_sg

    result = nil
    loop do
      result = self.class.send(:valid_civil_p, y, m, d, sg)
      break if result

      d -= 1
      raise Error if d < 1
    end

    nth = result[:nth]
    rjd = result[:rjd]
    rjd2 = self.class.send(:encode_jd, nth, rjd)

    self + (rjd2 - m_real_local_jd)
  end

  def ==(other) # :nodoc:
    if other.is_a?(Date) &&
       @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       other.instance_variable_get(:@nth) == 0 &&
       other.instance_variable_get(:@has_jd) &&
       other.instance_variable_get(:@df).nil? &&
       other.instance_variable_get(:@sf).nil? &&
       other.instance_variable_get(:@of).nil?
      return @jd == other.instance_variable_get(:@jd)
    end

    return false unless other.is_a?(Date)

    m_canonicalize_jd
    other.send(:m_canonicalize_jd)

    m_nth == other.send(:m_nth) &&
    m_jd == other.send(:m_jd) &&
    m_df == other.send(:m_df) &&
    m_sf == other.send(:m_sf)
  end

  def eql?(other) # :nodoc:
    if other.is_a?(Date) &&
       @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       other.instance_variable_get(:@nth) == 0 &&
       other.instance_variable_get(:@has_jd) &&
       other.instance_variable_get(:@df).nil? &&
       other.instance_variable_get(:@sf).nil? &&
       other.instance_variable_get(:@of).nil?
      return @jd == other.instance_variable_get(:@jd) &&
             @sg == other.instance_variable_get(:@sg)
    end

    return false unless other.is_a?(Date)

    m_canonicalize_jd
    other.send(:m_canonicalize_jd)

    m_nth == other.send(:m_nth) &&
    m_jd == other.send(:m_jd) &&
    @sg == other.instance_variable_get(:@sg)
  end

  def hash # :nodoc:
    if @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_jd &&
       @jd >= 0 && @jd < CM_PERIOD
      return [0, @jd, @sg].hash
    end
    m_canonicalize_jd
    [m_nth, m_jd, @sg].hash
  end

  # call-seq:
  #    d + other  ->  date
  #
  # Returns a date object pointing +other+ days after self.  The other
  # should be a numeric value.  If the other is a fractional number,
  # assumes its precision is at most nanosecond.
  #
  #    Date.new(2001,2,3) + 1    #=> #<Date: 2001-02-04 ...>
  #    DateTime.new(2001,2,3) + Rational(1,2)
  #                              #=> #<DateTime: 2001-02-03T12:00:00+00:00 ...>
  #    DateTime.new(2001,2,3) + Rational(-1,2)
  #                              #=> #<DateTime: 2001-02-02T12:00:00+00:00 ...>
  #    DateTime.jd(0,12) + DateTime.new(2001,2,3).ajd
  #                              #=> #<DateTime: 2001-02-03T00:00:00+00:00 ...>
  def +(other)
    if other.is_a?(Integer) && @of.nil? && @nth == 0
      if @has_jd
        jd = @jd + other
      elsif @has_civil
        sg = @sg
        gregorian_fast = if sg.is_a?(Float) && sg.infinite?
                           sg < 0
                         elsif sg.is_a?(Integer) && sg >= REFORM_BEGIN_JD && sg <= REFORM_END_JD
                           @year > REFORM_END_YEAR
                         end
        if gregorian_fast
          j = (@month < 3) ? 1 : 0
          y0 = @year - j
          m0 = j.nonzero? ? @month + 12 : @month
          d0 = @day - 1
          q1 = y0 / 100
          yc = (NS_DAYS_IN_4_YEARS * y0) / 4 - q1 + q1 / 4
          mc = (NS_DAYS_BEFORE_NEW_YEAR * m0 - 914) / 10
          jd = yc + mc + d0 + NS_EPOCH + other
        end
      end
      if jd && jd >= 0 && jd < CM_PERIOD
        obj = self.class.allocate
        obj._init_simple_with_jd(jd, @sg)
        return obj
      end
    end

    case other
    when Integer
      nth = m_nth
      jd = m_jd

      if (other / CM_PERIOD).nonzero?
        nth = nth + (other / CM_PERIOD)
        other = other % CM_PERIOD
      end

      if other.nonzero?
        jd = jd + other
        nth, jd = canonicalize_jd(nth, jd)
      end

      obj = self.class.allocate
      if simple_dat_p?
        obj._init_with_jd(nth, jd, nil, nil, nil, @sg)
      else
        obj._init_with_jd(nth, jd, @df || 0, @sf || 0, @of || 0, @sg)
      end
      obj
    when Float
      s = other >= 0 ? 1 : -1
      o = other.abs

      tmp, o = o.divmod(1.0)

      if (tmp / CM_PERIOD).floor.zero?
        nth = 0
        jd = tmp.to_i
      else
        i, f = (tmp / CM_PERIOD).divmod(1.0)
        nth = i.floor
        jd = (f * CM_PERIOD).to_i
      end

      o *= DAY_IN_SECONDS
      df, o = o.divmod(1.0)
      df = df.to_i
      o *= SECOND_IN_NANOSECONDS
      sf = o.round

      if s < 0
        jd = -jd
        df = -df
        sf = -sf
      end

      if sf.nonzero?
        sf = 0 + sf
        if sf < 0
          df -= 1
          sf += SECOND_IN_NANOSECONDS
        elsif sf >= SECOND_IN_NANOSECONDS
          df += 1
          sf -= SECOND_IN_NANOSECONDS
        end
      end

      if df.nonzero?
        df = 0 + df
        if df < 0
          jd -= 1
          df += DAY_IN_SECONDS
        elsif df >= DAY_IN_SECONDS
          jd += 1
          df -= DAY_IN_SECONDS
        end
      end

      if jd.nonzero?
        jd = m_jd + jd
        nth, jd = canonicalize_jd(nth, jd)
      else
        jd = m_jd
      end

      nth = nth.nonzero? ? @nth + nth : @nth

      obj = self.class.allocate
      if df.zero? && sf.zero? && (@of.nil? || @of.zero?)
        obj._init_with_jd(nth, jd, nil, nil, nil, @sg)
      else
        obj._init_with_jd(nth, jd, df, sf, @of || 0, @sg)
      end
      obj
    when Rational
      return self + other.numerator if other.denominator == 1

      s = other >= 0 ? 1 : -1
      other = other.abs

      nth = other.div(CM_PERIOD)
      t = other % CM_PERIOD

      jd = t.div(1).to_i
      t = t % 1

      t = t * DAY_IN_SECONDS
      df = t.div(1).to_i
      t = t % 1

      sf = t * SECOND_IN_NANOSECONDS

      if s < 0
        nth = -nth
        jd = -jd
        df = -df
        sf = -sf
      end

      if sf.nonzero?
        sf = (@sf || 0) + sf
        if sf < 0
          df -= 1
          sf += SECOND_IN_NANOSECONDS
        elsif sf >= SECOND_IN_NANOSECONDS
          df += 1
          sf -= SECOND_IN_NANOSECONDS
        end
      else
        sf = @sf || 0
      end

      if df.nonzero?
        df = (@df || 0) + df
        if df < 0
          jd -= 1
          df += DAY_IN_SECONDS
        elsif df >= DAY_IN_SECONDS
          jd += 1
          df -= DAY_IN_SECONDS
        end
      else
        df = @df || 0
      end

      if jd.nonzero?
        jd = m_jd + jd
        nth, jd = canonicalize_jd(nth, jd)
      else
        jd = m_jd
      end

      nth = nth.nonzero? ? @nth + nth : @nth

      obj = self.class.allocate
      if df.zero? && sf.zero?
        obj._init_with_jd(nth, jd, nil, nil, nil, @sg)
      else
        obj._init_with_jd(nth, jd, df, sf, @of || 0, @sg)
      end
      obj
    else
      raise TypeError, "expected numeric" unless other.is_a?(Numeric)

      other = other.to_r
      raise TypeError, "expected numeric" unless other.is_a?(Rational)

      self + other
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
  #     Date.new(2001,2,3) - 1                              #=> #<Date: 2001-02-02 ...>
  #     DateTime.new(2001,2,3) - Rational(1,2)              #=> #<DateTime: 2001-02-02T12:00:00+00:00 ...>
  #     Date.new(2001,2,3) - Date.new(2001)                 #=> (33/1)
  #     DateTime.new(2001,2,3) - DateTime.new(2001,2,2,12)  #=> (1/2)
  def -(other)
    if other.is_a?(Integer) && @of.nil? && @nth == 0 && @has_jd
      jd = @jd - other
      if jd >= 0 && jd < CM_PERIOD
        obj = self.class.allocate
        obj._init_simple_with_jd(jd, @sg)
        return obj
      end
    end

    return minus_dd(other) if other.is_a?(Date)

    raise TypeError, "expected numeric" unless other.is_a?(Numeric)

    # Add a negative value for numbers.
    # Works with all types: Integer, Float, Rational, Bignum, etc.
    self + (-other)
  end

  # call-seq:
  #   gregorian -> new_date
  #
  # Equivalent to Date#new_start with argument Date::GREGORIAN.
  def gregorian
    dup_obj_with_new_start(GREGORIAN)
  end

  # call-seq:
  #   gregorian? -> true or false
  #
  # Returns +true+ if the date is on or after
  # the date of calendar reform, +false+ otherwise:
  #
  #   Date.new(1582, 10, 15).gregorian?       # => true
  #   (Date.new(1582, 10, 15) - 1).gregorian? # => false
  def gregorian?
    m_gregorian_p?
  end

  # call-seq:
  #   italy -> new_date
  #
  # Equivalent to Date#new_start with argument Date::ITALY.
  def italy
    dup_obj_with_new_start(ITALY)
  end

  # call-seq:
  #   england -> new_date
  #
  # Equivalent to Date#new_start with argument Date::ENGLAND.
  def england
    dup_obj_with_new_start(ENGLAND)
  end

  # call-seq:
  #   julian -> new_date
  #
  # Equivalent to Date#new_start with argument Date::JULIAN.
  def julian
    dup_obj_with_new_start(JULIAN)
  end

  # call-seq:
  #   d.julian? -> true or false
  #
  # Returns +true+ if the date is before the date of calendar reform,
  # +false+ otherwise:
  #
  #   (Date.new(1582, 10, 15) - 1).julian? # => true
  #   Date.new(1582, 10, 15).julian?       # => false
  def julian?
    m_julian_p?
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
  def ld
    m_real_local_jd - 2299160
  end

  # call-seq:
  #   leap? -> true or false
  #
  # Returns +true+ if the year is a leap year, +false+ otherwise:
  #
  #   Date.new(2000).leap? # => true
  #   Date.new(2001).leap? # => false
  def leap?
    if gregorian?
      # For the Gregorian calendar, get m_year to determine if it is a leap year.
      y = m_year

      return self.class.send(:c_gregorian_leap_p?, y)
    end

    # For the Julian calendar, calculate JD for March 1st.
    y = m_year
    sg = m_virtual_sg
    rjd, _ = self.class.send(:c_civil_to_jd, y, 3, 1, sg)

    # Get the date of the day before March 1st (the last day of February).
    _, _, rd = self.class.send(:c_jd_to_civil, rjd - 1, sg)

    # If February 29th exists, it is a leap year.
    rd == 29
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
  def new_start(start = DEFAULT_SG)
    sg = start ? val2sg(start) : DEFAULT_SG

    dup_obj_with_new_start(sg)
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
  def next
    next_day
  end
  alias_method :succ, :next

  # call-seq:
  #   next_year(n = 1) -> new_date
  #
  # Equivalent to #>> with argument <tt>n * 12</tt>.
  def next_year(n = 1)
    self >> (n * 12)
  end

  # call-seq:
  #   prev_year(n = 1) -> new_date
  #
  # Equivalent to #<< with argument <tt>n * 12</tt>.
  def prev_year(n = 1)
    self << (n * 12)
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
  #   sunday? -> true or false
  #
  # Returns +true+ if +self+ is a Sunday, +false+ otherwise.
  def sunday?
    m_wday.zero?
  end

  # call-seq:
  #   monday? -> true or false
  #
  # Returns +true+ if +self+ is a Monday, +false+ otherwise.
  def monday?
    m_wday == 1
  end

  # call-seq:
  #   tuesday? -> true or false
  #
  # Returns +true+ if +self+ is a Tuesday, +false+ otherwise.
  def tuesday?
    m_wday == 2
  end

  # call-seq:
  #   wednesday? -> true or false
  #
  # Returns +true+ if +self+ is a Wednesday, +false+ otherwise.
  def wednesday?
    m_wday == 3
  end

  # call-seq:
  #   thursday? -> true or false
  #
  # Returns +true+ if +self+ is a Thursday, +false+ otherwise.
  def thursday?
    m_wday == 4
  end

  # call-seq:
  #   friday? -> true or false
  #
  # Returns +true+ if +self+ is a Friday, +false+ otherwise.
  def friday?
    m_wday == 5
  end

  # call-seq:
  #   saturday? -> true or false
  #
  # Returns +true+ if +self+ is a Saturday, +false+ otherwise.
  def saturday?
    m_wday == 6
  end

  # call-seq:
  #   wday -> integer
  #
  # Returns the day of week in range (0..6); Sunday is 0:
  #
  #   Date.new(2001, 2, 3).wday # => 6
  def wday
    m_wday
  end

  # call-seq:
  #   yday -> integer
  #
  # Returns the day of the year, in range (1..366):
  #
  #   Date.new(2001, 2, 3).yday # => 34
  def yday
    m_yday
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
  def deconstruct_keys(keys)
    if keys.nil?
      return {
        year: year,
        month: month,
        day: day,
        yday: yday,
        wday: wday
      }
    end

    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.is_a?(Array)

    h = {}
    keys.each do |key|
      case key
      when :year  then h[:year]  = year
      when :month then h[:month] = month
      when :day   then h[:day]   = day
      when :yday  then h[:yday]  = yday
      when :wday  then h[:wday]  = wday
      when :zone  then h[:zone]  = zone
      end
    end
    h
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
    raise ArgumentError, "step must be numeric" unless step.respond_to?(:<=>)

    return to_enum(:step, limit, step) unless block_given?

    date = self
    cmp = step <=> 0

    raise ArgumentError, "step must be numeric" if cmp.nil?

    case cmp
    when -1
      # If step is negative (reverse order)
      while (date <=> limit) >= 0
        yield date
        date = date + step
      end
    when 0
      # If step is 0 (infinite loop)
      loop do
        yield date
      end
    else
      # If step is positive (forward direction)
      while (date <=> limit) <= 0
        yield date
        date = date + step
      end
    end

    self
  end

  # call-seq:
  #   upto(max){|date| ... } -> self
  #
  # Equivalent to #step with arguments +max+ and +1+.
  def upto(max)
    return to_enum(:upto, max) unless block_given?

    date = self

    while (date <=> max) <= 0
      yield date
      date = date + 1
    end

    self
  end

  # call-seq:
  #   downto(min){|date| ... } -> self
  #
  # Equivalent to #step with arguments +min+ and <tt>-1</tt>.
  def downto(min)
    return to_enum(:downto, min) unless block_given?

    date = self

    while (date <=> min) >= 0
      yield date
      date = date - 1
    end

    self
  end

  # call-seq:
  #   day_fraction -> rational
  #
  # Returns the fractional part of the day in range (Rational(0, 1)...Rational(1, 1)):
  #
  #   DateTime.new(2001,2,3,12).day_fraction # => (1/2)
  def day_fraction
    simple_dat_p? ? 0 : m_fr
  end

  # call-seq:
  #    d.mjd  ->  integer
  #
  # Returns the modified Julian day number.  This is a whole number,
  # which is adjusted by the offset as the local time.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').mjd  #=> 51943
  #    DateTime.new(2001,2,3,4,5,6,'-7').mjd  #=> 51943
  def mjd
    m_real_local_jd - 2_400_001
  end

  # call-seq:
  #   cwyear -> integer
  #
  # Returns commercial-date year for +self+
  # (see Date.commercial):
  #
  #   Date.new(2001, 2, 3).cwyear # => 2001
  #   Date.new(2000, 1, 1).cwyear # => 1999
  def cwyear
    m_real_cwyear
  end

  # call-seq:
  #   cweek -> integer
  #
  # Returns commercial-date week index for +self+
  # (see Date.commercial):
  #
  #   Date.new(2001, 2, 3).cweek # => 5
  def cweek
    m_cweek
  end

  # call-seq:
  #   cwday -> integer
  #
  # Returns the commercial-date weekday index for +self+
  # (see Date.commercial);
  # 1 is Monday:
  #
  #   Date.new(2001, 2, 3).cwday # => 6
  def cwday
    m_cwday
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
  def to_time
    # Julian calendar converted to Gregorian calendar.
    date = m_julian_p? ? gregorian : self

    # Create a Time object using Time.local.
    Time.local(
      date.send(:m_real_year),
      date.send(:m_mon),
      date.send(:m_mday)
    )
  end

  # call-seq:
  #   to_date -> self
  #
  # Returns +self+.
  def to_date
    self
  end

  # call-seq:
  #   to_datetime -> datetime
  #
  # Returns a DateTime whose value is the same as +self+.
  def to_datetime
    # Use internal constructor to bypass validation (reform-gap safety)
    nth, ry = self.class.send(:decode_year, year, -1)
    rjd, _ = self.class.send(:c_civil_to_jd, ry, month, day, Date::GREGORIAN)
    obj = DateTime.send(:new_with_jd_and_time, nth, rjd, 0, 0, 0, Date::GREGORIAN)
    obj.send(:set_sg, start)
    obj
  end

  # call-seq:
  #    d.ajd  ->  rational
  #
  # Returns the astronomical Julian day number.  This is a fractional
  # number, which is not adjusted by the offset.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').ajd    #=> (11769328217/4800)
  #    DateTime.new(2001,2,2,14,5,6,'-7').ajd   #=> (11769328217/4800)
  def ajd
    m_ajd
  end

  # call-seq:
  #    d.amjd  ->  rational
  #
  # Returns the astronomical modified Julian day number.  This is
  # a fractional number, which is not adjusted by the offset.
  #
  #    DateTime.new(2001,2,3,4,5,6,'+7').amjd   #=> (249325817/4800)
  #    DateTime.new(2001,2,2,14,5,6,'-7').amjd  #=> (249325817/4800)
  def amjd
    m_amjd
  end

  # :nodoc:
  # C: d_lite_initialize_copy
  def initialize_copy(other)
    unless other.is_a?(Date)
      raise TypeError, "initialize_copy should take same class object"
    end
    @nth = other.instance_variable_get(:@nth)
    @jd = other.instance_variable_get(:@jd)
    @sg = other.instance_variable_get(:@sg)
    @df = other.instance_variable_get(:@df)
    @sf = other.instance_variable_get(:@sf)
    @of = other.instance_variable_get(:@of)
    @year = other.instance_variable_get(:@year)
    @month = other.instance_variable_get(:@month)
    @day = other.instance_variable_get(:@day)
    @has_jd = other.instance_variable_get(:@has_jd)
    @has_civil = other.instance_variable_get(:@has_civil)
    self
  end

  # :nodoc:
  def marshal_dump
    [
      m_nth,
      m_jd,
      m_df,
      m_sf,
      m_of,
      @sg
    ]
  end

  # :nodoc:
  # C: d_lite_marshal_load
  # Supports 3 historical formats:
  #   2 elements (1.4/1.6): [jd_like, sg_or_bool]
  #   3 elements (1.8/1.9.2): [ajd, of, sg]
  #   6 elements (current): [nth, jd, df, sf, of, sg]
  def marshal_load(array)
    raise TypeError, "expected an array" unless array.is_a?(Array)

    case array.size
    when 2 # Ruby 1.4/1.6
      # C: ajd = f_sub(a[0], half_days_in_day); vof = 0; vsg = a[1]
      ajd = array[0] - Rational(1, 2)
      vof = 0
      vsg = array[1]
      unless vsg.is_a?(Numeric)
        vsg = vsg ? -Float::INFINITY : Float::INFINITY
      end
      nth, jd, df, sf, of_sec, sg = old_to_new(ajd, vof, vsg)

    when 3 # Ruby 1.8 / 1.9.2
      ajd = array[0]
      vof = array[1]
      vsg = array[2]
      nth, jd, df, sf, of_sec, sg = old_to_new(ajd, vof, vsg)

    when 6 # Current format
      nth, jd, df, sf, of_sec, sg = array

    else
      raise TypeError, "invalid size"
    end

    @nth = nth
    @jd = jd
    @df = (!df || df == 0) ? nil : df
    @sf = (!sf || sf == 0) ? nil : sf
    @of = (!of_sec || of_sec == 0) ? nil : of_sec
    @sg = sg

    @has_jd = true
    @has_civil = false
    @year = nil
    @month = nil
    @day = nil
  end

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
    strftime('%a %b %e %H:%M:%S %Y')
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
  def iso8601
    strftime('%Y-%m-%d')
  end
  alias_method :xmlschema, :iso8601

  # call-seq:
  #   rfc3339 -> string
  #
  # Equivalent to #strftime with argument <tt>'%FT%T%:z'</tt>;
  # see {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc]:
  #
  #   Date.new(2001, 2, 3).rfc3339 # => "2001-02-03T00:00:00+00:00"
  def rfc3339
    strftime('%Y-%m-%dT%H:%M:%S%:z')
  end

  # call-seq:
  #   rfc2822 -> string
  #
  # Equivalent to #strftime with argument <tt>'%a, %-d %b %Y %T %z'</tt>;
  # see {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc]:
  #
  #   Date.new(2001, 2, 3).rfc2822 # => "Sat, 3 Feb 2001 00:00:00 +0000"
  def rfc2822
    strftime('%a, %-d %b %Y %T %z')
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
    # For Date objects, offset is always 0, so we can directly call strftime
    strftime('%a, %d %b %Y %T GMT')
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
    jd = m_real_local_jd
    y = m_real_year

    fmt = jisx0301_date_format(jd, y)
    strftime(fmt)
  end

  def to_s
    s = sprintf("%04d-%02d-%02d", year, month, day)
    s.force_encoding(Encoding::US_ASCII)
  end

  # call-seq:
  #   inspect -> string
  #
  # Returns a string representation of +self+:
  #
  #   Date.new(2001, 2, 3).inspect
  #   # => "#<Date: 2001-02-03 ((2451944j,0s,0n),+0s,2299161j)>"
  def inspect
    s = if simple_dat_p?
      inspect_raw
    else
      # In the case of complex, time information is also displayed.
      strftime("%Y-%m-%d %H:%M:%S")
    end
    s.force_encoding(Encoding::US_ASCII) if s.ascii_only?
    s
  end

  # override
  def freeze
    # Force lazy computation before freezing so Ractor-shared objects work.
    if simple_dat_p?
      get_s_jd
      get_s_civil
      canonicalize_s_jd
    else
      get_c_jd
      get_c_civil
      get_c_df
      get_c_time
      canonicalize_c_jd
    end
    super
  end

  private

  def inspect_raw
    # If @sg is infinity
    if @sg.infinite?
      if @sg < 0
        return "#<Date: -Inf-XX-XX ((0j,0s,0n),+0s,Inf)>"
      else
        return "#<Date: +Inf-XX-XX ((0j,0s,0n),+0s,-Inf)>"
      end
    end

    date_str = strftime("%Y-%m-%d")
    jd_val = @jd || 0
    sg_val = @sg.infinite? ? (@sg < 0 ? "Inf" : "-Inf") : @sg.to_i

    "#<Date: #{date_str} ((#{jd_val}j,0s,0n),+0s,#{sg_val}j)>"
  end

  def valid_civil?(y, m, d)
    return false if m < 1 || m > 12

    last = last_day_of_month(y, m)
    d >= 1 && d <= last
  end

  def last_day_of_month(y, m)
    last_day_of_month_gregorian(y, m)
  end

  def civil_to_jd(y, m, d, sg)
    self.class.send(:gregorian_civil_to_jd, y, m, d)
  end

  def jd_to_civil(jd, sg)
    decode_jd(jd)
    self.class.send(:c_jd_to_civil, jd, sg)
  end

  def extract_fraction(value)
    self.class.send(:extract_fraction, value)
  end

  def decode_year(year, style)
    self.class.send(:decode_year, year, style)
  end

  def valid_gregorian?(y, m, d)
    return false if m < 1 || m > 12

    # Handling negative months and days
    m = m + 13 if m < 0
    return false if m < 1 || m > 12

    last_day = last_day_of_month_gregorian(y, m)
    d = last_day + d + 1 if d < 0

    d >= 1 && d <= last_day
  end

  def add_with_fraction(n)
    int_part = n.floor
    frac_part = n - int_part

    result = add_days(int_part)

    result = result.send(:add_fraction, frac_part) if frac_part.nonzero?

    result
  end

  def add_days(days)
    new_jd = @jd + days
    new_nth = @nth

    while new_jd < 0
      new_nth -= 1
      new_jd += CM_PERIOD
    end

    while new_jd >= CM_PERIOD
      new_nth += 1
      new_jd -= CM_PERIOD
    end

    obj = self.class.allocate
    obj.instance_variable_set(:@nth, new_nth)
    obj.instance_variable_set(:@jd, new_jd)
    obj.instance_variable_set(:@sg, @sg)
    obj.instance_variable_set(:@flags, HAVE_JD)
    obj.instance_variable_set(:@year, nil)
    obj.instance_variable_set(:@month, nil)
    obj.instance_variable_set(:@day, nil)

    obj
  end

  def add_fraction(frac)
    # In the C implementation, Date.jd(2451944.5) becomes 2451945,
    # so if there is a decimal point, it will be rounded up by one day.
    if frac > 0
      add_days(1)
    else
      self
    end
  end

  def last_day_of_month_gregorian(y, m)
    self.class.send(:last_day_of_month_gregorian, y, m)
  end

  def last_day_of_month_julian(y, m)
    self.class.send(:last_day_of_month_julian, y, m)
  end

  def valid_civil_date?(year, month, day, sg)
    self.class.send(:valid_civil_date?, year, month, day, sg)
  end

  protected

  def _init_with_jd(nth, jd, df, sf, of, start)
    @nth = nth
    @jd = jd
    @sg = start
    @df = df
    @sf = sf
    @of = of
    @year = nil
    @month = nil
    @day = nil
    @has_jd = true
    @has_civil = false
  end

  def _init_simple_with_jd(jd, start)
    @nth = 0
    @jd = jd
    @sg = start
    @has_jd = true
  end

  def _init_simple_with_civil(year, month, day, start)
    @nth = 0
    @sg = start
    @year = year
    @month = month
    @day = day
    @has_civil = true
  end

  private

  def canonicalize_jd(nth, jd)
    if jd < 0
      nth = nth - 1
      jd += CM_PERIOD
    end
    if jd >= CM_PERIOD
      nth = nth + 1
      jd -= CM_PERIOD
    end

    [nth, jd]
  end

  # If any of @df, @sf, or @of is not nil, it is considered complex.
  def simple_dat_p?
    @df.nil? && @sf.nil? && @of.nil?
  end

  def complex_dat_p?
    !simple_dat_p?
  end

  def m_gregorian_p?
    !m_julian_p?
  end

  def m_julian_p?
    # Divide the processing into simple and complex.
    if simple_dat_p?
      get_s_jd
      jd = @jd
      sg = s_virtual_sg
    else
      get_c_jd
      jd = @jd
      sg = c_virtual_sg
    end

    return sg == JULIAN if sg.infinite?

    jd < sg
  end

  def m_year
    simple_dat_p? ? get_s_civil : get_c_civil

    @year
  end

  def m_virtual_sg
    simple_dat_p? ? s_virtual_sg : c_virtual_sg
  end

  def get_s_jd
    # For simple data, if JD has not yet been calculated.
    return if @has_jd

    return unless simple_dat_p?

    return unless @has_civil

    # Calculate JD from civil.
    jd, _ = self.class.send(:c_civil_to_jd, @year, @month, @day, s_virtual_sg)
    @jd = jd
    @has_jd = true
  end

  def get_s_civil
    # For simple data, if civil has not yet been calculated.
    return if @has_civil

    # If not simple or there is no JD, do nothing.
    return unless simple_dat_p?
    return unless @has_jd

    # Calculate civil from JD.
    y, m, d = self.class.send(:c_jd_to_civil, @jd, s_virtual_sg)
    @year = y
    @month = m
    @day = d
    @has_civil = true
  end

  def get_c_jd
    # For complex data, if JD has not yet been calculated.
    return if @has_jd

    # Make sure you have civil data.
    raise "No civil data" unless @has_civil

    # Calculate JD from civil.
    jd, _ = self.class.send(:c_civil_to_jd, @year, @month, @day, c_virtual_sg)

    # Consider time data.
    get_c_time

    # Convert from local to UTC.
    @jd = jd_local_to_utc(jd, time_to_df(@hour || 0, @min || 0, @sec || 0), @of || 0)
    @has_jd = true
  end

  def get_c_civil
    # For complex data, if civil has not yet been calculated.
    return if @has_civil

    # Make sure you have a JD.
    raise "No JD data" unless @has_jd

    get_c_df

    # Convert UTC to local.
    jd = jd_utc_to_local(@jd, @df || 0, @of || 0)

    # Calculate civil from JD.
    y, m, d = self.class.send(:c_jd_to_civil, jd, c_virtual_sg)
    @year = y
    @month = m
    @day = d
    @has_civil = true
  end

  def get_c_df
    # If df (day fraction) has not yet been calculated.
    return if @df

    # Check that time data is available.
    raise "No time data" if @hour.nil? && @min.nil? && @sec.nil?

    # Convert time to df
    @df = df_local_to_utc(time_to_df(@hour, @min, @sec), @of || 0)
  end

  def get_c_time
    # If the time data has not yet been calculated.
    return unless @hour.nil?

    # Make sure df exists.
    raise "No df data" if @df.nil?

    # Convert df to time.
    r = df_utc_to_local(@df, @of || 0)

    @hour, @min, @sec = df_to_time(r)
  end

  # For SimpleDateData (effectively a common implementation)
  def s_virtual_sg
    return @sg if @sg.infinite?
    return @sg if self.class.send(:f_zero_p?, @nth)

    @nth < 0 ? JULIAN : GREGORIAN
  end

  # For ComplexDateData (effectively a common implementation)
  def c_virtual_sg
    return @sg if @sg.infinite?
    return @sg if self.class.send(:f_zero_p?, @nth)

    @nth < 0 ? JULIAN : GREGORIAN
  end

  def jd_local_to_utc(jd, df, of)
    df -= of
    if df < 0
      jd -= 1
    elsif df >= DAY_IN_SECONDS
      jd += 1
    end

    jd
  end

  def jd_utc_to_local(jd, df, of)
    df += of
    if df < 0
      jd -= 1
    elsif df >= DAY_IN_SECONDS
      jd += 1
    end

    jd
  end

  def df_local_to_utc(df, of)
    df -= of
    if df < 0
      df += DAY_IN_SECONDS
    elsif df >= DAY_IN_SECONDS
      df -= DAY_IN_SECONDS
    end

    df
  end

  def df_utc_to_local(df, of)
    df += of
    if df < 0
      df += DAY_IN_SECONDS
    elsif df >= DAY_IN_SECONDS
      df -= DAY_IN_SECONDS
    end

    df
  end

  def time_to_df(h, min, s)
    h * HOUR_IN_SECONDS + min * MINUTE_IN_SECONDS + s
  end

  def df_to_time(df)
    h = df / HOUR_IN_SECONDS
    df %= HOUR_IN_SECONDS
    min = df / MINUTE_IN_SECONDS
    s = df % MINUTE_IN_SECONDS

    [h, min, s]
  end

  def minus_dd(other)
    n = m_nth - other.send(:m_nth)
    d = m_jd - other.send(:m_jd)
    df = m_df - other.send(:m_df)
    sf = m_sf - other.send(:m_sf)

    n, d = canonicalize_jd(n, d)

    # Canonicalize df
    if df < 0
      d -= 1
      df += DAY_IN_SECONDS
    elsif df >= DAY_IN_SECONDS
      d += 1
      df -= DAY_IN_SECONDS
    end

    # Canonicalize sf
    if sf < 0
      df -= 1
      sf += SECOND_IN_NANOSECONDS
    elsif sf >= SECOND_IN_NANOSECONDS
      df += 1
      sf -= SECOND_IN_NANOSECONDS
    end

    r = n.zero? ? 0 : n * CM_PERIOD
    r = r + Rational(d, 1) if d.nonzero?
    r = r + isec_to_day(df) if df.nonzero?
    r = r + ns_to_day(sf) if sf.nonzero?

    r.is_a?(Rational) ? r : Rational(r, 1)
  end

  def m_jd
    simple_dat_p? ? get_s_jd : get_c_jd

    @jd
  end

  def m_df
    if simple_dat_p?
      0
    else
      get_c_df
      @df || 0
    end
  end

  def m_sf
    simple_dat_p? ? 0 : @sf || 0
  end

  def m_of
    if simple_dat_p?
      0
    else
      get_c_jd
      @of || 0
    end
  end

  def m_real_year
    return @year if @nth == 0 && @has_civil

    nth = @nth
    year = m_year

    return year if self.class.send(:f_zero_p?, nth)

    encode_year(nth, year, gregorian? ? -1 : 1)
  end

  def m_mon
    return @month if @has_civil

    simple_dat_p? ? get_s_civil : get_c_civil
    @month
  end

  def m_mday
    return @day if @has_civil

    simple_dat_p? ? get_s_civil : get_c_civil
    @day
  end

  def m_sg
    get_c_jd unless simple_dat_p?

    @sg
  end

  def encode_year(nth, y, style)
    period = (style < 0) ? CM_PERIOD_GCY : CM_PERIOD_JCY

    self.class.send(:f_zero_p?, nth) ? y : period * nth + y
  end

  def m_real_local_jd
    nth = m_nth
    jd = m_local_jd

    self.class.send(:encode_jd, nth, jd)
  end

  def m_local_jd
    if simple_dat_p?
      get_s_jd
      @jd
    else
      get_c_jd
      get_c_df
      local_jd
    end
  end

  def local_jd
    jd = @jd
    df = @df || 0
    of = @of || 0

    df += of
    if df < 0
      jd -= 1
    elsif df >= DAY_IN_SECONDS
      jd += 1
    end

    jd
  end

  def m_nth
    # For complex, get civil data and then return nth.
    get_c_civil unless simple_dat_p?

    @nth
  end

  def equal_gen(other)
    if other.is_a?(Numeric)
      m_real_local_jd == other
    elsif other.is_a?(Date)
      m_real_local_jd == other.send(:m_real_local_jd)
    else
      begin
        coerced = other.coerce(self)
        coerced[0] == coerced[1]
      rescue
        false
      end
    end
  end

  def m_canonicalize_jd
    if simple_dat_p?
      get_s_jd
      canonicalize_s_jd
    else
      get_c_jd
      canonicalize_c_jd
    end
  end

  # Simple
  def canonicalize_s_jd
    return if frozen?

    j = @jd

    @nth, @jd = canonicalize_jd(@nth, @jd)

    # Invalidate civil data if JD changes.
    @has_civil = false if @jd != j
  end

  # Complex
  def canonicalize_c_jd
    return if frozen?

    j = @jd

    @nth, @jd = canonicalize_jd(@nth, @jd)

    # Invalidate civil data if JD changes.
    @has_civil = false if @jd != j
  end

  def f_jd(other)
    # Get JD from another Date object.
    other.send(:m_real_local_jd)
  end

  def dup_obj_with_new_start(sg)
    dup = dup_obj
    dup.send(:set_sg, sg)

    dup
  end

  def dup_obj
    if simple_dat_p?
      # Simple data replication
      new_obj = self.class.send(:d_lite_s_alloc_simple)

      new_obj.instance_variable_set(:@nth, canon(@nth))
      new_obj.instance_variable_set(:@jd, @jd)
      new_obj.instance_variable_set(:@sg, @sg)
      new_obj.instance_variable_set(:@year, @year)
      new_obj.instance_variable_set(:@month, @month)
      new_obj.instance_variable_set(:@day, @day)
      new_obj.instance_variable_set(:@has_jd, @has_jd)
      new_obj.instance_variable_set(:@has_civil, @has_civil)
      new_obj.instance_variable_set(:@df, nil)
      new_obj.instance_variable_set(:@sf, nil)
      new_obj.instance_variable_set(:@of, nil)

      new_obj
    else
      # Complex data replication
      new_obj = self.class.send(:d_lite_s_alloc_complex)

      new_obj.instance_variable_set(:@nth, canon(@nth))
      new_obj.instance_variable_set(:@jd, @jd)
      new_obj.instance_variable_set(:@sg, @sg)
      new_obj.instance_variable_set(:@year, @year)
      new_obj.instance_variable_set(:@month, @month)
      new_obj.instance_variable_set(:@day, @day)
      new_obj.instance_variable_set(:@hour, @hour)
      new_obj.instance_variable_set(:@min, @min)
      new_obj.instance_variable_set(:@sec, @sec)
      new_obj.instance_variable_set(:@df, @df)
      new_obj.instance_variable_set(:@sf, canon(@sf))
      new_obj.instance_variable_set(:@of, @of)
      new_obj.instance_variable_set(:@has_jd, @has_jd)
      new_obj.instance_variable_set(:@has_civil, @has_civil)

      new_obj
    end
  end

  def set_sg(sg)
    if simple_dat_p?
      get_s_jd if @has_jd || @has_civil
    else
      get_c_jd
      get_c_df
    end

    clear_civil

    @sg = sg
  end

  def clear_civil
    @has_civil = false
    @year = nil
    @month = nil
    @day = nil
  end

  # If the argument is Rational and the denominator is 1, return the numerator.
  def canon(x)
    x.is_a?(Rational) && x.denominator == 1 ? x.numerator : x
  end

  def val2sg(vsg)
    # Convert to Number.
    sg = vsg.to_f

    # Check for a valid start.
    unless c_valid_start_p?(sg)
      warn "invalid start is ignored"
      sg = DEFAULT_SG
    end

    sg
  end

  def c_valid_start_p?(sg)
    # Invalid for NaN.
    return false if sg.respond_to?(:nan?) && sg.nan?

    # Valid for Infinity.
    return true if sg.respond_to?(:infinite?) && sg.infinite?

    # If it is a finite value, check if it is within the range
    # from REFORM_BEGIN_JD to REFORM_END_JD
    return false if sg < REFORM_BEGIN_JD || sg > REFORM_END_JD

    true
  end

  def m_wday
    return (@jd + 1) % 7 if @has_jd && @of.nil?

    c_jd_to_wday(m_local_jd)
  end

  def c_jd_to_wday(jd)
    (jd + 1) % 7
  end

  def m_yday
    if @has_civil && @of.nil?
      sg = @sg
      if (sg.is_a?(Float) && sg.infinite? && sg < 0) ||
         (sg.is_a?(Integer) && @has_jd && (@jd - sg) > 366)
        leap = self.class.send(:c_gregorian_leap_p?, @year)
        return YEARTAB[leap ? 1 : 0][@month] + @day
      end
    end

    jd = m_local_jd
    sg = m_virtual_sg

    # proleptic gregorian or if more than 366 days have passed since the calendar change
    return c_gregorian_to_yday(m_year, m_mon, m_mday) if m_proleptic_gregorian_p? || (jd - sg) > 366

    # proleptic Julian
    return c_julian_to_yday(m_year, m_mon, m_mday) if m_proleptic_julian_p?

    # Otherwise, convert from JD to ordinal.
    _, rd = self.class.send(:c_jd_to_ordinal, jd, sg)

    rd
  end

  def m_proleptic_gregorian_p?
    sg = @sg

    sg.infinite? && sg < 0
  end

  def m_proleptic_julian_p?
    sg = @sg

    sg.infinite? && sg > 0
  end

  def c_gregorian_to_yday(year, month, day)
    leap = self.class.send(:c_gregorian_leap_p?, year)

    YEARTAB[leap ? 1 : 0][month] + day
  end

  def c_julian_to_yday(year, month, day)
    leap = self.class.send(:c_julian_leap_p?, year)

    YEARTAB[leap ? 1 : 0][month] + day
  end

  def d_trunc_with_frac(value)
    if value.is_a?(Integer)
      [value, 0]
    elsif value.is_a?(Float)
      trunc = value.truncate
      frac = value - trunc

      [trunc, frac]
    elsif value.is_a?(Rational)
      trunc = value.truncate
      frac = value - trunc

      [trunc, frac]
    else
      [value.to_i, 0]
    end
  end

  def m_real_jd
    # C: m_real_jd uses m_jd (raw/UTC JD), NOT m_local_jd
    nth = m_nth
    if simple_dat_p?
      get_s_jd
    else
      get_c_jd
    end
    self.class.send(:encode_jd, nth, @jd)
  end

  def m_fr
    if simple_dat_p?
      0
    else
      df = m_local_df
      sf = m_sf

      fr = isec_to_day(df)
      fr = fr + ns_to_day(sf) if sf.nonzero?

      fr
    end
  end

  def m_local_df
    if simple_dat_p?
      0
    else
      get_c_df
      local_df
    end
  end

  def local_df
    df_utc_to_local(@df || 0, @of || 0)
  end

  def isec_to_day(s)
    sec_to_day(s)
  end

  def sec_to_day(s)
    s.is_a?(Integer) ? Rational(s, DAY_IN_SECONDS) : s.quo(DAY_IN_SECONDS)
  end

  def ns_to_day(n)
    if n.is_a?(Integer)
      Rational(n, DAY_IN_SECONDS * SECOND_IN_NANOSECONDS)
    else
      n.quo(DAY_IN_SECONDS * SECOND_IN_NANOSECONDS)
    end
  end

  def m_real_cwyear
    nth = m_nth
    year = m_cwyear

    nth.zero? ? year : encode_year(nth, year, m_gregorian_p? ? -1 : 1)
  end

  def m_cwyear
    jd = m_local_jd
    sg = m_virtual_sg

    ry, _, _ = self.class.send(:c_jd_to_commercial, jd, sg)

    ry
  end

  def m_cweek
    jd = m_local_jd
    sg = m_virtual_sg

    _, rw, _ = self.class.send(:c_jd_to_commercial, jd, sg)

    rw
  end

  def m_cwday
    w = m_wday
    # ISO 8601 places Sunday at 7.
    w.zero? ? 7 : w
  end

  def m_ajd
    if simple_dat_p?
      # For simple date:
      r = m_real_jd

      # Optimization: Integer operations within Fixnum range
      if r.is_a?(Integer) && r <= (2**62 - 1) / 2 && r >= (-(2**62) + 1) / 2
        ir = r * 2 - 1
        return Rational(ir, 2)
      else
        return Rational(r * 2 - 1, 2)
      end
    end

    # For complex date:
    r = m_real_jd
    df = m_df

    # Subtract half a day (12 hours) from df.
    df -= HALF_DAYS_IN_SECONDS

    # If df is not zero, add.
    r = r + isec_to_day(df) if df != 0

    # If sf is not zero, add.
    sf = m_sf
    r = r + ns_to_day(sf) if sf != 0

    r
  end

  def m_amjd
    r = m_real_jd

    # Optimization: Integer operations within Fixnum range
    if r.is_a?(Integer) && r >= (-(2**62) + 2400001)
      ir = r - 2400001
      r = Rational(ir, 1)
    else
      r = Rational(m_real_jd - 2400001, 1)
    end

    # For simple date, stop here.
    return r if simple_dat_p?

    # For complex date, add df and sf.
    df = m_df
    r = r + isec_to_day(df) if df != 0

    sf = m_sf
    r = r + ns_to_day(sf) if sf != 0

    r
  end

  def m_wnumx(f)
    _, rw, _ = c_jd_to_weeknum(m_local_jd, f, m_virtual_sg)

    rw
  end

  def c_jd_to_weeknum(jd, f, sg)
    ry, _, _ = self.class.send(:c_jd_to_civil, jd, sg)
    rjd, _ = self.class.send(:c_find_fdoy, ry, sg)

    rjd += 6

    mod_val = euclidean_mod((rjd - f) + 1, 7)
    j = jd - (rjd - mod_val) + 7

    rw = euclidean_div(j, 7)
    rd = euclidean_mod(j, 7)

    [ry, rw, rd]
  end

  # Euclidean division (equivalent to the DIV macro in C)
  def euclidean_div(a, b)
    q = a / b
    r = a % b
    # In Ruby, a remainder of a negative number is negative, so adjust it accordingly.
    if r < 0
      if b > 0
        q -= 1
      else
        q += 1
      end
    end

    q
  end

  # Euclidean modulo (equivalent to the MOD macro in C)
  def euclidean_mod(a, b)
    r = a % b
    # In Ruby, a remainder of a negative number is negative, so adjust it accordingly.
    if r < 0
      if b > 0
        r += b
      else
        r -= b
      end
    end

    r
  end

  def jisx0301_date_format(jd, year)
    # If jd is not a Fixnum (Integer in Ruby), use ISO format
    return '%Y-%m-%d' unless jd.is_a?(Integer)

    # Determine the era based on Julian Day Number
    if jd < 2405160
      # Before Meiji era (before 1868-01-25)
      '%Y-%m-%d'
    elsif jd < 2419614
      # Meiji era (M) 1868-01-25 to 1912-07-29
      era_char = 'M'
      era_start = 1867
      format_era(era_char, year, era_start)
    elsif jd < 2424875
      # Taisho era (T) 1912-07-30 to 1926-12-24
      era_char = 'T'
      era_start = 1911
      format_era(era_char, year, era_start)
    elsif jd < 2447535
      # Showa era (S) 1926-12-25 to 1989-01-07
      era_char = 'S'
      era_start = 1925
      format_era(era_char, year, era_start)
    elsif jd < 2458605
      # Heisei era (H) 1989-01-08 to 2019-04-30
      era_char = 'H'
      era_start = 1988
      format_era(era_char, year, era_start)
    else
      # Reiwa era (R) 2019-05-01 onwards
      era_char = 'R'
      era_start = 2018
      format_era(era_char, year, era_start)
    end
  end

  def format_era(era_char, year, era_start)
    era_year = year - era_start
    "#{era_char}%02d.%%m.%%d" % era_year
  end

  def zone
    of = @parsed_offset || 0
    s = of < 0 ? '-' : '+'
    a = of.abs
    h = a / HOUR_IN_SECONDS
    m = a % HOUR_IN_SECONDS / MINUTE_IN_SECONDS
    "%c%02d:%02d" % [s, h, m]
  end

  # C: old_to_new — converts old ajd/of/sg format to new nth/jd/df/sf/of/sg
  def old_to_new(ajd, of, sg)
    # C: decode_day(ajd + half_days_in_day, &jd, &df, &sf)
    d = ajd + Rational(1, 2)

    # div_day: jd = floor(d), f = d mod 1
    jd_full = d.floor
    f = d - jd_full

    # div_df: df = floor(f * DAY_IN_SECONDS), remainder
    df_rational = f * 86400
    df = df_rational.floor
    sf_frac = df_rational - df

    # sec_to_ns: sf = round(sf_frac * SECOND_IN_NANOSECONDS)
    sf = (sf_frac * 1_000_000_000).round

    # C: day_to_sec(of) then round
    of_sec = (of * 86400).round.to_i

    # C: decode_jd(jd, &nth, &rjd)
    nth = jd_full.div(CM_PERIOD)
    rjd = (jd_full % CM_PERIOD).to_i

    # Validations (C: old_to_new)
    raise Error, "invalid day fraction" if df < 0 || df >= 86400
    if of_sec < -86400 || of_sec > 86400
      of_sec = 0
      warn "invalid offset is ignored"
    end

    # Convert Infinity to Float (C: NUM2DBL(sg))
    if sg.is_a?(Infinity)
      sg = case sg.send(:d)
           when -1 then -Float::INFINITY
           when  1 then  Float::INFINITY
           else DEFAULT_SG
           end
    end

    [nth, rjd, df, sf, of_sec, sg]
  end
end
