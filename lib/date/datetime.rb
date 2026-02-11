# frozen_string_literal: true

# Implementation of DateTime from ruby/date/ext/date/date_core.c
# DateTime is a subclass of Date that includes time-of-day and timezone.
class DateTime < Date
  # call-seq:
  #   DateTime.new(year=-4712, month=1, day=1, hour=0, minute=0, second=0, offset=0, start=Date::ITALY) -> datetime
  #
  # Creates a new DateTime object.
  def initialize(year = -4712, month = 1, day = 1, hour = 0, minute = 0, second = 0, offset = 0, start = ITALY)
    y = year
    m = month
    d = day
    h = hour
    min = minute
    s = second
    fr2 = 0

    # argument type checking
    raise TypeError, "invalid year (not numeric)" unless y.is_a?(Numeric)
    raise TypeError, "invalid month (not numeric)" unless m.is_a?(Numeric)
    raise TypeError, "invalid day (not numeric)" unless d.is_a?(Numeric)
    raise TypeError, "invalid hour (not numeric)" unless h.is_a?(Numeric)
    raise TypeError, "invalid minute (not numeric)" unless min.is_a?(Numeric)
    raise TypeError, "invalid second (not numeric)" unless s.is_a?(Numeric)

    # Handle fractional day (C: d_trunc)
    d_trunc, fr = d_trunc_with_frac(d)
    d = d_trunc
    fr2 = fr if fr.nonzero?

    # Handle fractional hour (C: h_trunc via num2int_with_frac)
    h_int = h.to_i
    h_frac = h - h_int
    if h_frac.nonzero?
      fr2 = fr2 + Rational(h_frac) / 24
      h = h_int
    end

    # Handle fractional minute (C: min_trunc)
    min_int = min.to_i
    min_frac = min - min_int
    if min_frac.nonzero?
      fr2 = fr2 + Rational(min_frac) / 1440
      min = min_int
    end

    # Handle fractional second (C: s_trunc)
    # C converts sub-second fraction to day fraction: fr2 = frac / DAY_IN_SECONDS
    s_int = s.to_i
    s_frac = s - s_int
    if s_frac.nonzero?
      fr2 = fr2 + Rational(s_frac) / DAY_IN_SECONDS
      s = s_int
    end

    # Convert offset to integer seconds (C: val2off → offset_to_sec)
    rof = offset_to_sec(offset)

    sg = self.class.send(:valid_sg, start)
    style = self.class.send(:guess_style, y, sg)

    # Validate time (C: c_valid_time_p)
    h, min, s = validate_time(h, min, s)

    # Handle hour 24 (C: canon24oc)
    if h == 24
      h = 0
      fr2 = fr2 + 1
    end

    if style < 0
      # gregorian calendar only
      result = self.class.send(:valid_gregorian_p, y, m, d)
      raise Error, "invalid date" unless result

      nth, ry = self.class.send(:decode_year, y, -1)
      rm = result[:rm]
      rd = result[:rd]

      rjd, _ = self.class.send(:c_civil_to_jd, ry, rm, rd, GREGORIAN)
      rjd2 = jd_local_to_utc(rjd, time_to_df(h, min, s), rof)

      @nth = canon(nth)
      @jd = rjd2
      @sg = sg
      @year = ry
      @month = rm
      @day = rd
      @has_jd = true
      @has_civil = true
      @hour = h
      @min = min
      @sec = s
      @df = df_local_to_utc(time_to_df(h, min, s), rof)
      @sf = 0
      @of = rof
    else
      # full validation
      result = self.class.send(:valid_civil_p, y, m, d, sg)
      raise Error, "invalid date" unless result

      nth = result[:nth]
      ry = result[:ry]
      rm = result[:rm]
      rd = result[:rd]
      rjd = result[:rjd]

      rjd2 = jd_local_to_utc(rjd, time_to_df(h, min, s), rof)

      @nth = canon(nth)
      @jd = rjd2
      @sg = sg
      @year = ry
      @month = rm
      @day = rd
      @has_jd = true
      @has_civil = true
      @hour = h
      @min = min
      @sec = s
      @df = df_local_to_utc(time_to_df(h, min, s), rof)
      @sf = 0
      @of = rof
    end

    # Add accumulated fractional parts (C: add_frac)
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
      @hour = new_date.instance_variable_get(:@hour)
      @min = new_date.instance_variable_get(:@min)
      @sec = new_date.instance_variable_get(:@sec)
      @df = new_date.instance_variable_get(:@df) || @df
      @sf = new_date.instance_variable_get(:@sf) || @sf
      @of = new_date.instance_variable_get(:@of) || @of
    end

    self
  end

  # --- DateTime accessors (C: d_lite_hour etc.) ---

  # call-seq:
  #   hour -> integer
  #
  # Returns the hour in range (0..23).
  def hour
    if simple_dat_p?
      0
    else
      get_c_time
      @hour || 0
    end
  end

  # call-seq:
  #   min -> integer
  #
  # Returns the minute in range (0..59).
  def min
    if simple_dat_p?
      0
    else
      get_c_time
      @min || 0
    end
  end
  alias minute min

  # call-seq:
  #   sec -> integer
  #
  # Returns the second in range (0..59).
  def sec
    if simple_dat_p?
      0
    else
      get_c_time
      @sec || 0
    end
  end
  alias second sec

  # call-seq:
  #   sec_fraction -> rational
  #
  # Returns the fractional part of the second:
  #
  #   DateTime.new(2001, 2, 3, 4, 5, 6.5).sec_fraction # => (1/2)
  #
  # C: m_sf_in_sec = ns_to_sec(m_sf)
  def sec_fraction
    ns = m_sf
    ns.zero? ? Rational(0) : Rational(ns, SECOND_IN_NANOSECONDS)
  end
  alias second_fraction sec_fraction

  # call-seq:
  #   offset -> rational
  #
  # Returns the offset as a fraction of day:
  #
  #   DateTime.parse('04pm+0730').offset # => (5/16)
  #
  # C: m_of_in_day = isec_to_day(m_of)
  def offset
    of = m_of
    of.zero? ? Rational(0) : Rational(of, DAY_IN_SECONDS)
  end

  # call-seq:
  #   zone -> string
  #
  # Returns the timezone as a string:
  #
  #   DateTime.parse('04pm+0730').zone # => "+07:30"
  #
  # C: m_zone → of2str(m_of)
  def zone
    if simple_dat_p?
      "+00:00".encode(Encoding::US_ASCII)
    else
      of = m_of
      s = of < 0 ? '-' : '+'
      a = of < 0 ? -of : of
      h = a / HOUR_IN_SECONDS
      m = a % HOUR_IN_SECONDS / MINUTE_IN_SECONDS
      ("%c%02d:%02d" % [s, h, m]).encode(Encoding::US_ASCII)
    end
  end

  STRFTIME_DATETIME_DEFAULT_FMT = '%FT%T%:z'.encode(Encoding::US_ASCII)
  private_constant :STRFTIME_DATETIME_DEFAULT_FMT

  # Override Date#strftime with DateTime default format
  def strftime(format = STRFTIME_DATETIME_DEFAULT_FMT)
    super(format)
  end

  # Override Date#jisx0301 for DateTime (includes time)
  def jisx0301(n = 0)
    n = n.to_i
    if n == 0
      jd_val = send(:m_real_local_jd)
      y = send(:m_real_year)
      fmt = jisx0301_date_format(jd_val, y) + 'T%T%:z'
      strftime(fmt)
    else
      s = jisx0301(0)
      # insert fractional seconds before timezone
      tz = s[-6..]  # "+00:00"
      base = s[0...-6]
      frac = sec_fraction
      if frac != 0
        f = format("%.#{n}f", frac.to_f)[1..]
        base += f
      else
        base += '.' + '0' * n
      end
      base + tz
    end
  end

  # DateTime instance method - overrides Date#iso8601
  def iso8601(n = 0)
    n = n.to_i
    if n == 0
      strftime('%FT%T%:z')
    else
      s = strftime('%FT%T')
      frac = sec_fraction
      if frac != 0
        f = format("%.#{n}f", frac.to_f)[1..]
        s += f
      else
        s += '.' + '0' * n
      end
      s + strftime('%:z')
    end
  end
  alias_method :xmlschema, :iso8601
  alias_method :rfc3339, :iso8601

  # call-seq:
  #   deconstruct_keys(array_of_names_or_nil) -> hash
  #
  # Returns name/value pairs for pattern matching.
  # Includes Date keys (:year, :month, :day, :wday, :yday)
  # plus DateTime keys (:hour, :min, :sec, :sec_fraction, :zone).
  #
  # C: dt_lite_deconstruct_keys (is_datetime=true)
  def deconstruct_keys(keys)
    if keys.nil?
      return {
        year: year,
        month: month,
        day: day,
        yday: yday,
        wday: wday,
        hour: hour,
        min: min,
        sec: sec,
        sec_fraction: sec_fraction,
        zone: zone
      }
    end

    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.is_a?(Array)

    h = {}
    keys.each do |key|
      case key
      when :year         then h[:year]         = year
      when :month        then h[:month]        = month
      when :day          then h[:day]          = day
      when :yday         then h[:yday]         = yday
      when :wday         then h[:wday]         = wday
      when :hour         then h[:hour]         = hour
      when :min          then h[:min]          = min
      when :sec          then h[:sec]          = sec
      when :sec_fraction then h[:sec_fraction] = sec_fraction
      when :zone         then h[:zone]         = zone
      end
    end
    h
  end

  # call-seq:
  #   to_s -> string
  #
  # Returns a string in ISO 8601 DateTime format:
  #
  #   DateTime.new(2001, 2, 3, 4, 5, 6, '+7').to_s
  #   # => "2001-02-03T04:05:06+07:00"
  def to_s
    sprintf("%04d-%02d-%02dT%02d:%02d:%02d%s".encode(Encoding::US_ASCII), year, month, day, hour, min, sec, zone)
  end

  # call-seq:
  #   new_offset(offset = 0) -> datetime
  #
  # Returns a new DateTime object with the same date and time,
  # but with the given +offset+.
  #
  # C: d_lite_new_offset
  def new_offset(of = 0)
    if of.is_a?(String)
      of = Rational(offset_to_sec(of), DAY_IN_SECONDS)
    elsif of.is_a?(Integer) && of == 0
      of = Rational(0)
    end
    raise TypeError, "invalid offset" unless of.is_a?(Rational) || of.is_a?(Integer) || of.is_a?(Float)
    of = Rational(of) unless of.is_a?(Rational)
    self.class.new(year, month, day, hour, min, sec + sec_fraction, of, start)
  end

  # call-seq:
  #   to_date -> date
  #
  # Returns a Date for this DateTime (time information is discarded).
  # C: dt_lite_to_date → copy civil, reset time
  def to_date
    nth, ry = self.class.send(:decode_year, year, -1)
    Date.send(:d_simple_new_internal,
              nth, 0,
              @sg,
              ry, month, day,
              0x04)  # HAVE_CIVIL
  end

  # call-seq:
  #   to_datetime -> self
  #
  # Returns self.
  def to_datetime
    self
  end

  # call-seq:
  #   to_time -> time
  #
  # Returns a Time for this DateTime.
  # C: dt_lite_to_time
  def to_time
    # C: dt_lite_to_time — converts Julian dates to Gregorian for Time compatibility
    d = julian? ? gregorian : self
    Time.new(d.year, d.month, d.day, d.hour, d.min, d.sec + d.sec_fraction, d.send(:m_of))
  end

  class << self
    # Same as DateTime.new
    alias_method :civil, :new

    undef_method :today

    # call-seq:
    #   DateTime.jd(jd=0, hour=0, minute=0, second=0, offset=0, start=Date::ITALY) -> datetime
    #
    # Creates a new DateTime from a Julian Day Number.
    # C: dt_lite_s_jd
    def jd(jd = 0, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      # Validate jd
      raise TypeError, "invalid jd (not numeric)" unless jd.is_a?(Numeric)
      raise TypeError, "invalid hour (not numeric)" unless hour.is_a?(Numeric)
      raise TypeError, "invalid minute (not numeric)" unless minute.is_a?(Numeric)
      raise TypeError, "invalid second (not numeric)" unless second.is_a?(Numeric)

      j, fr = value_trunc(jd)
      nth, rjd = decode_jd(j)

      sg = valid_sg(start)

      # Validate time
      h = hour.to_i
      h_frac = hour - h
      min_i = minute.to_i
      min_frac = minute - min_i
      s_i = second.to_i
      s_frac = second - s_i

      fr2 = fr
      fr2 = fr2 + Rational(h_frac) / 24 if h_frac.nonzero?
      fr2 = fr2 + Rational(min_frac) / 1440 if min_frac.nonzero?
      fr2 = fr2 + Rational(s_frac) / 86400 if s_frac.nonzero?

      rof = _offset_to_sec(offset)

      h += 24 if h < 0
      min_i += 60 if min_i < 0
      s_i += 60 if s_i < 0
      unless (0..24).cover?(h) && (0..59).cover?(min_i) && (0..59).cover?(s_i) &&
             !(h == 24 && (min_i > 0 || s_i > 0))
        raise Date::Error, "invalid date"
      end
      if h == 24
        h = 0
        fr2 = fr2 + 1
      end

      df = h * 3600 + min_i * 60 + s_i
      df_utc = df - rof
      jd_utc = rjd
      if df_utc < 0
        jd_utc -= 1
        df_utc += 86400
      elsif df_utc >= 86400
        jd_utc += 1
        df_utc -= 86400
      end

      obj = new_with_jd_and_time(nth, jd_utc, df_utc, 0, rof, sg)

      obj = obj + fr2 if fr2.nonzero?

      obj
    end

    # call-seq:
    #   DateTime.ordinal(year=-4712, yday=1, hour=0, minute=0, second=0, offset=0, start=Date::ITALY) -> datetime
    #
    # Creates a new DateTime from an ordinal date.
    # C: dt_lite_s_ordinal
    def ordinal(year = -4712, yday = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      raise TypeError, "invalid year (not numeric)" unless year.is_a?(Numeric)
      raise TypeError, "invalid yday (not numeric)" unless yday.is_a?(Numeric)
      raise TypeError, "invalid hour (not numeric)" unless hour.is_a?(Numeric)
      raise TypeError, "invalid minute (not numeric)" unless minute.is_a?(Numeric)
      raise TypeError, "invalid second (not numeric)" unless second.is_a?(Numeric)

      # Truncate fractional yday
      yday_int = yday.to_i
      yday_frac = yday.is_a?(Integer) ? 0 : yday - yday_int

      result = valid_ordinal_p(year, yday_int, start)
      raise Date::Error, "invalid date" unless result

      nth = result[:nth]
      rjd = result[:rjd]
      sg = valid_sg(start)

      rof = _offset_to_sec(offset)

      h = hour.to_i
      h_frac = hour - h
      min_i = minute.to_i
      min_frac = minute - min_i
      s_i = second.to_i
      s_frac = second - s_i

      fr2 = yday_frac.nonzero? ? Rational(yday_frac) : 0
      fr2 = fr2 + Rational(h_frac) / 24 if h_frac.nonzero?
      fr2 = fr2 + Rational(min_frac) / 1440 if min_frac.nonzero?
      fr2 = fr2 + Rational(s_frac) / 86400 if s_frac.nonzero?

      h += 24 if h < 0
      min_i += 60 if min_i < 0
      s_i += 60 if s_i < 0
      unless (0..24).cover?(h) && (0..59).cover?(min_i) && (0..59).cover?(s_i) &&
             !(h == 24 && (min_i > 0 || s_i > 0))
        raise Date::Error, "invalid date"
      end
      if h == 24
        h = 0
        fr2 = fr2 + 1
      end

      df = h * 3600 + min_i * 60 + s_i
      df_utc = df - rof
      jd_utc = rjd
      if df_utc < 0
        jd_utc -= 1
        df_utc += 86400
      elsif df_utc >= 86400
        jd_utc += 1
        df_utc -= 86400
      end

      obj = new_with_jd_and_time(nth, jd_utc, df_utc, 0, rof, sg)

      obj = obj + fr2 if fr2.nonzero?

      obj
    end

    # call-seq:
    #   DateTime.commercial(cwyear=-4712, cweek=1, cwday=1, hour=0, minute=0, second=0, offset=0, start=Date::ITALY) -> datetime
    #
    # Creates a new DateTime from a commercial date.
    # C: dt_lite_s_commercial
    def commercial(cwyear = -4712, cweek = 1, cwday = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      raise TypeError, "invalid cwyear (not numeric)" unless cwyear.is_a?(Numeric)
      raise TypeError, "invalid cweek (not numeric)" unless cweek.is_a?(Numeric)
      raise TypeError, "invalid cwday (not numeric)" unless cwday.is_a?(Numeric)
      raise TypeError, "invalid hour (not numeric)" unless hour.is_a?(Numeric)
      raise TypeError, "invalid minute (not numeric)" unless minute.is_a?(Numeric)
      raise TypeError, "invalid second (not numeric)" unless second.is_a?(Numeric)

      # Truncate fractional cwday
      cwday_int = cwday.to_i
      cwday_frac = cwday.is_a?(Integer) ? 0 : cwday - cwday_int

      result = valid_commercial_p(cwyear, cweek, cwday_int, start)
      raise Date::Error, "invalid date" unless result

      nth = result[:nth]
      rjd = result[:rjd]
      sg = valid_sg(start)

      rof = _offset_to_sec(offset)

      h = hour.to_i
      h_frac = hour - h
      min_i = minute.to_i
      min_frac = minute - min_i
      s_i = second.to_i
      s_frac = second - s_i

      fr2 = cwday_frac.nonzero? ? Rational(cwday_frac) : 0
      fr2 = fr2 + Rational(h_frac) / 24 if h_frac.nonzero?
      fr2 = fr2 + Rational(min_frac) / 1440 if min_frac.nonzero?
      fr2 = fr2 + Rational(s_frac) / 86400 if s_frac.nonzero?

      h += 24 if h < 0
      min_i += 60 if min_i < 0
      s_i += 60 if s_i < 0
      unless (0..24).cover?(h) && (0..59).cover?(min_i) && (0..59).cover?(s_i) &&
             !(h == 24 && (min_i > 0 || s_i > 0))
        raise Date::Error, "invalid date"
      end
      if h == 24
        h = 0
        fr2 = fr2 + 1
      end

      df = h * 3600 + min_i * 60 + s_i
      df_utc = df - rof
      jd_utc = rjd
      if df_utc < 0
        jd_utc -= 1
        df_utc += 86400
      elsif df_utc >= 86400
        jd_utc += 1
        df_utc -= 86400
      end

      obj = new_with_jd_and_time(nth, jd_utc, df_utc, 0, rof, sg)

      obj = obj + fr2 if fr2.nonzero?

      obj
    end

    # call-seq:
    #   DateTime.strptime(string='-4712-01-01T00:00:00+00:00', format='%FT%T%z', start=Date::ITALY) -> datetime
    #
    # Parses +string+ according to +format+ and creates a DateTime.
    # C: dt_lite_s_strptime
    def strptime(string = '-4712-01-01T00:00:00+00:00', format = '%FT%T%z', start = Date::ITALY)
      hash = _strptime(string, format)
      dt_new_by_frags(hash, start)
    end

    # Override Date._strptime default format for DateTime
    def _strptime(string, format = '%FT%T%z')
      super(string, format)
    end

    # call-seq:
    #   DateTime.now(start = Date::ITALY) -> datetime
    #
    # Creates a DateTime for the current time.
    #
    # C: datetime_s_now
    def now(start = Date::ITALY)
      t = Time.now
      sg = valid_sg(start)

      of = t.utc_offset  # integer seconds

      new(
        t.year, t.mon, t.mday,
        t.hour, t.min, t.sec + Rational(t.nsec, 1_000_000_000),
        Rational(of, 86400),
        sg
      )
    end

    # call-seq:
    #   DateTime.parse(string, comp = true, start = Date::ITALY, limit: 128) -> datetime
    #
    # Parses +string+ and creates a DateTime.
    #
    # C: date_parse → dt_new_by_frags
    def parse(string = JULIAN_EPOCH_DATETIME, comp = true, start = Date::ITALY, limit: 128)
      hash = _parse(string, comp, limit: limit)
      dt_new_by_frags(hash, start)
    end

    # Format-specific constructors delegate to _xxx + dt_new_by_frags

    def iso8601(string = JULIAN_EPOCH_DATETIME, start = Date::ITALY, limit: 128)
      hash = _iso8601(string, limit: limit)
      dt_new_by_frags(hash, start)
    end

    def rfc3339(string = JULIAN_EPOCH_DATETIME, start = Date::ITALY, limit: 128)
      hash = _rfc3339(string, limit: limit)
      dt_new_by_frags(hash, start)
    end

    def xmlschema(string = JULIAN_EPOCH_DATETIME, start = Date::ITALY, limit: 128)
      hash = _xmlschema(string, limit: limit)
      dt_new_by_frags(hash, start)
    end

    def rfc2822(string = JULIAN_EPOCH_DATETIME_RFC2822, start = Date::ITALY, limit: 128)
      hash = _rfc2822(string, limit: limit)
      dt_new_by_frags(hash, start)
    end
    alias_method :rfc822, :rfc2822

    def httpdate(string = JULIAN_EPOCH_DATETIME_HTTPDATE, start = Date::ITALY, limit: 128)
      hash = _httpdate(string, limit: limit)
      dt_new_by_frags(hash, start)
    end

    def jisx0301(string = JULIAN_EPOCH_DATETIME, start = Date::ITALY, limit: 128)
      hash = _jisx0301(string, limit: limit)
      dt_new_by_frags(hash, start)
    end

    private

    JULIAN_EPOCH_DATETIME = '-4712-01-01T00:00:00+00:00'
    JULIAN_EPOCH_DATETIME_RFC2822 = 'Mon, 1 Jan -4712 00:00:00 +0000'
    JULIAN_EPOCH_DATETIME_HTTPDATE = 'Mon, 01 Jan -4712 00:00:00 GMT'

    # C: offset_to_sec / val2off (class method version for use in class << self)
    def _offset_to_sec(of)
      case of
      when Integer
        of
      when Rational
        (of * 86400).to_i
      when Float
        (of * 86400).to_i
      when String
        if of.strip.upcase == 'Z'
          0
        elsif of =~ /\A([+-])(\d{1,2}):(\d{2})\z/
          sign = $1 == '-' ? -1 : 1
          sign * ($2.to_i * 3600 + $3.to_i * 60)
        elsif of =~ /\A([+-])(\d{2})(\d{2})?\z/
          sign = $1 == '-' ? -1 : 1
          sign * ($2.to_i * 3600 + ($3 ? $3.to_i * 60 : 0))
        else
          0
        end
      else
        0
      end
    end

    # C: dt_new_by_frags (date_core.c:8434)
    #
    # Structure matches C exactly:
    # 1. Fast path: year+mon+mday present, no jd/yday
    #    - Validate civil, default time to 0, clamp sec==60 → 59
    # 2. Slow path: rt_rewrite_frags → rt_complete_frags → rt__valid_date_frags_p
    # 3. Validate time (c_valid_time_p), handle sec_fraction, offset
    # 4. Construct DateTime
    def dt_new_by_frags(hash, sg)
      raise Date::Error, "invalid date" if hash.nil? || hash.empty?

      # --- Fast path (C: lines 8447-8466) ---
      if !hash.key?(:jd) && !hash.key?(:yday) &&
         hash[:year] && hash[:mon] && hash[:mday]

        y = hash[:year]; m = hash[:mon]; d = hash[:mday]
        raise Date::Error, "invalid date" unless valid_civil?(y, m, d, sg)

        # C: default time fields, clamp sec==60
        hash[:hour] = 0 unless hash.key?(:hour)
        hash[:min]  = 0 unless hash.key?(:min)
        if !hash.key?(:sec)
          hash[:sec] = 0
        elsif hash[:sec] == 60
          hash[:sec] = 59
        end

      # --- Slow path (C: lines 8467-8470) ---
      # rt_complete_frags needs DateTime as klass for time-only fill-in.
      # rt__valid_date_frags_p needs Date for validation (calls ordinal/new).
      else
        hash = Date.send(:rt_rewrite_frags, hash)
        hash = Date.send(:rt_complete_frags, self, hash)
        jd_val = Date.send(:rt__valid_date_frags_p, hash, sg)
        raise Date::Error, "invalid date" unless jd_val

        # Convert JD to civil for constructor
        y, m, d = Date.send(:c_jd_to_civil, jd_val, sg)
      end

      # --- Time validation (C: c_valid_time_p, lines 8473-8480) ---
      h   = hash[:hour] || 0
      min = hash[:min]  || 0
      s   = hash[:sec]  || 0

      # C: c_valid_time_p normalizes negative values and validates range.
      rh   = h   < 0 ? h + 24 : h
      rmin = min < 0 ? min + 60 : min
      rs   = s   < 0 ? s + 60 : s
      unless (0..24).cover?(rh) && (0..59).cover?(rmin) && (0..59).cover?(rs) &&
             !(rh == 24 && (rmin > 0 || rs > 0))
        raise Date::Error, "invalid date"
      end

      # --- sec_fraction (C: lines 8482-8486) ---
      sf = hash[:sec_fraction]
      s_with_frac = sf ? rs + sf : rs

      # --- offset (C: lines 8488-8495) ---
      of_sec = hash[:offset] || 0
      if of_sec.abs > 86400
        warn "invalid offset is ignored"
        of_sec = 0
      end
      of = Rational(of_sec, 86400)

      # --- Construct DateTime ---
      new(y, m, d, rh, rmin, s_with_frac, of, sg)
    end
  end

  private

  # Convert offset argument to integer seconds.
  # Accepts: Integer (seconds), Rational (fraction of day), String ("+HH:MM"), 0
  # C: offset_to_sec / val2off
  def offset_to_sec(of)
    case of
    when Integer
      of
    when Float
      # Fraction of day to seconds
      (of * DAY_IN_SECONDS).to_i
    when Rational
      # Fraction of day to seconds
      (of * DAY_IN_SECONDS).to_i
    when String
      if of.strip.upcase == 'Z'
        0
      elsif of =~ /\A([+-])(\d{2}):(\d{2})\z/
        sign = $1 == '-' ? -1 : 1
        sign * ($2.to_i * HOUR_IN_SECONDS + $3.to_i * MINUTE_IN_SECONDS)
      elsif of =~ /\A([+-])(\d{2})(\d{2})?\z/
        sign = $1 == '-' ? -1 : 1
        sign * ($2.to_i * HOUR_IN_SECONDS + ($3 ? $3.to_i * MINUTE_IN_SECONDS : 0))
      else
        0
      end
    else
      0
    end
  end

  # Validate time fields (C: c_valid_time_p)
  def validate_time(h, min, s)
    h += 24 if h < 0
    min += 60 if min < 0
    s += 60 if s < 0
    unless (0..24).cover?(h) && (0..59).cover?(min) && (0..59).cover?(s) &&
           !(h == 24 && (min > 0 || s > 0))
      raise Error, "invalid date"
    end
    [h, min, s]
  end
end
