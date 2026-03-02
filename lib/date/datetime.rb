# frozen_string_literal: true

class DateTime < Date

  STRFTIME_DATETIME_DEFAULT_FMT = '%FT%T%:z'.encode(Encoding::US_ASCII)
  private_constant :STRFTIME_DATETIME_DEFAULT_FMT

  # ---------------------------------------------------------------------------
  # Initializer
  # ---------------------------------------------------------------------------

  # call-seq:
  #   DateTime.new(year=-4712, month=1, day=1, hour=0, minute=0, second=0, offset=0, start=Date::ITALY) -> datetime
  def initialize(year = -4712, month = 1, day = 1, hour = 0, minute = 0, second = 0, offset = 0, start = ITALY)
    year   = Integer(year)
    month  = Integer(month)
    of_sec = _str_offset_to_sec(offset)

    raise TypeError, "expected numeric" unless day.is_a?(Numeric)

    # Fractional day/hour/minute: propagate fraction to smaller units
    day_r    = day.to_r
    day_i    = day_r.floor
    day_frac = day_r - day_i
    day      = day_i

    jd = self.class.__send__(:internal_valid_civil?, year, month, day, start)
    raise Date::Error, "invalid date" unless jd

    raise TypeError, "expected numeric" unless hour.is_a?(Numeric)
    raise TypeError, "expected numeric" unless minute.is_a?(Numeric)
    raise TypeError, "expected numeric" unless second.is_a?(Numeric)

    # Propagate fractions to smaller units
    hour_r    = hour.to_r   + day_frac   * 24
    hour_i    = hour_r.floor
    hour_frac = hour_r - hour_i

    minute_r    = minute.to_r + hour_frac   * 60
    minute_i    = minute_r.floor
    minute_frac = minute_r - minute_i

    second_r  = second.to_r + minute_frac * 60
    sec_i     = second_r.floor
    sec_f     = second_r - sec_i
    jd, hour, minute, sec_i = self.class.__send__(:_normalize_hms, jd, hour_i, minute_i, sec_i)

    _init_datetime(jd, hour, minute, sec_i, sec_f, of_sec, start)
  end

  # ---------------------------------------------------------------------------
  # Instance attributes
  # ---------------------------------------------------------------------------

  # call-seq:
  #   hour -> integer
  #
  # Returns the hour in range (0..23):
  #
  #   DateTime.new(2001, 2, 3, 4, 5, 6).hour # => 4
  def hour
    @hour
  end

  # call-seq:
  #   min -> integer
  #
  # Returns the minute in range (0..59):
  #
  #   DateTime.new(2001, 2, 3, 4, 5, 6).min # => 5
  def min
    @min
  end
  alias minute min

  # call-seq:
  #   sec -> integer
  #
  # Returns the second in range (0..59):
  #
  #   DateTime.new(2001, 2, 3, 4, 5, 6).sec # => 6
  def sec
    @sec_i
  end
  alias second sec

  # call-seq:
  #   sec_fraction -> rational
  #
  # Returns the fractional part of the second in range
  # (Rational(0, 1)...Rational(1, 1)):
  #
  #   DateTime.new(2001, 2, 3, 4, 5, 6.5).sec_fraction # => (1/2)
  def sec_fraction
    @sec_frac
  end
  alias second_fraction sec_fraction

  # call-seq:
  #    d.offset  ->  rational
  #
  # Returns the offset.
  #
  #    DateTime.parse('04pm+0730').offset	#=> (5/16)
  def offset
    Rational(@of, 86400)
  end

  # call-seq:
  #    d.zone  ->  string
  #
  # Returns the timezone.
  #
  #    DateTime.parse('04pm+0730').zone		#=> "+07:30"
  def zone
    _of2str(@of)
  end

  # call-seq:
  #   day_fraction -> rational
  #
  # Returns the fractional part of the day in range (Rational(0, 1)...Rational(1, 1)):
  #
  #   DateTime.new(2001,2,3,12).day_fraction # => (1/2)
  def day_fraction
    Rational(@hour * 3600 + @min * 60 + @sec_i, 86400) +
      Rational(@sec_frac.numerator, @sec_frac.denominator * 86400)
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
    jd_r = Rational(@jd)
    time_r = Rational(@hour * 3600 + @min * 60 + @sec_i, 86400) +
             Rational(@sec_frac.numerator, @sec_frac.denominator * 86400)
    of_r = Rational(@of, 86400)
    jd_r + time_r - of_r - Rational(1, 2)
  end

  # ---------------------------------------------------------------------------
  # Arithmetic (override for fractional day support)
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
      self.class.__send__(:_new_dt_from_jd_time,@jd + other, @hour, @min, @sec_i, @sec_frac, @of, @sg)
    when Rational, Float
      # other is days (may be fractional) — add as seconds
      extra_sec = other.to_r * 86400
      total_r   = Rational(@jd) * 86400 + @hour * 3600 + @min * 60 + @sec_i + @sec_frac + extra_sec
      _from_total_sec_r(total_r)
    when Numeric
      r = other.to_r
      raise TypeError, "#{other.class} can't be coerced into Integer" unless r.is_a?(Rational)
      extra_sec = r * 86400
      total_r   = Rational(@jd) * 86400 + @hour * 3600 + @min * 60 + @sec_i + @sec_frac + extra_sec
      _from_total_sec_r(total_r)
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
      ajd - other.ajd
    when Integer
      self.class.__send__(:_new_dt_from_jd_time,@jd - other, @hour, @min, @sec_i, @sec_frac, @of, @sg)
    when Rational, Float
      self + (-other)
    when Numeric
      r = other.to_r
      raise TypeError, "#{other.class} can't be coerced into Integer" unless r.is_a?(Rational)
      self + (-r)
    else
      raise TypeError, "expected numeric"
    end
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
  def new_start(start = Date::ITALY)
    self.class.__send__(:_new_dt_from_jd_time, @jd, @hour, @min, @sec_i, @sec_frac, @of, start)
  end

  # call-seq:
  #    d.new_offset([offset=0])  ->  date
  #
  # Duplicates self and resets its offset.
  #
  #    d = DateTime.new(2001,2,3,4,5,6,'-02:00')
  #				#=> #<DateTime: 2001-02-03T04:05:06-02:00 ...>
  #    d.new_offset('+09:00')	#=> #<DateTime: 2001-02-03T15:05:06+09:00 ...>
  def new_offset(of = 0)
    of_sec = _str_offset_to_sec(of)
    self.class.__send__(:_new_dt_from_jd_time,@jd, @hour, @min, @sec_i, @sec_frac, of_sec, @sg)
  end

  # ---------------------------------------------------------------------------
  # String formatting
  # ---------------------------------------------------------------------------

  # call-seq:
  #   strftime(format = '%FT%T%:z') -> string
  #
  # Returns a string representation of +self+,
  # formatted according the given +format:
  #
  #   DateTime.now.strftime # => "2022-07-01T11:03:19-05:00"
  #
  # For other formats,
  # see {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc]:
  def strftime(format = STRFTIME_DATETIME_DEFAULT_FMT)
    super(format)
  end

  # call-seq:
  #    dt.jisx0301([n=0])  ->  string
  #
  # Returns a string in a JIS X 0301 format.
  # The optional argument +n+ is the number of digits for fractional seconds.
  #
  #    DateTime.parse('2001-02-03T04:05:06.123456789+07:00').jisx0301(9)
  #				#=> "H13.02.03T04:05:06.123456789+07:00"
  def jisx0301(n = 0)
    n = n.to_i
    ERA_TABLE.each do |start_jd, era, base_year|
      if @jd >= start_jd
        era_year = year - base_year
        if n == 0
          return format('%s%02d.%02d.%02dT%02d:%02d:%02d%s',
                        era, era_year, month, day, hour, min, sec, zone)
        else
          sf   = sec_fraction
          frac = '.' + (sf * (10**n)).to_i.to_s.rjust(n, '0')
          return format('%s%02d.%02d.%02dT%02d:%02d:%02d%s%s',
                        era, era_year, month, day, hour, min, sec, frac, zone)
        end
      end
    end
    iso8601(n)
  end

  # call-seq:
  #    dt.iso8601([n=0])    ->  string
  #    dt.xmlschema([n=0])  ->  string
  #
  # This method is equivalent to strftime('%FT%T%:z').
  # The optional argument +n+ is the number of digits for fractional seconds.
  #
  #    DateTime.parse('2001-02-03T04:05:06.123456789+07:00').iso8601(9)
  #				#=> "2001-02-03T04:05:06.123456789+07:00"
  def iso8601(n = 0)
    n = n.to_i
    if n == 0
      strftime('%Y-%m-%dT%H:%M:%S%:z')
    else
      sf   = sec_fraction
      frac = '.' + (sf * (10**n)).to_i.to_s.rjust(n, '0')
      strftime("%Y-%m-%dT%H:%M:%S#{frac}%:z")
    end
  end
  alias_method :xmlschema, :iso8601

  # call-seq:
  #    dt.rfc3339([n=0])  ->  string
  #
  # This method is equivalent to strftime('%FT%T%:z').
  # The optional argument +n+ is the number of digits for fractional seconds.
  #
  #    DateTime.parse('2001-02-03T04:05:06.123456789+07:00').rfc3339(9)
  #				#=> "2001-02-03T04:05:06.123456789+07:00"
  alias_method :rfc3339,   :iso8601

  #  call-seq:
  #    deconstruct_keys(array_of_names_or_nil) -> hash
  #
  #  Returns a hash of the name/value pairs, to use in pattern matching.
  #  Possible keys are: <tt>:year</tt>, <tt>:month</tt>, <tt>:day</tt>,
  #  <tt>:wday</tt>, <tt>:yday</tt>, <tt>:hour</tt>, <tt>:min</tt>,
  #  <tt>:sec</tt>, <tt>:sec_fraction</tt>, <tt>:zone</tt>.
  #
  #  Possible usages:
  #
  #    dt = DateTime.new(2022, 10, 5, 13, 30)
  #
  #    if d in wday: 1..5, hour: 10..18  # uses deconstruct_keys underneath
  #      puts "Working time"
  #    end
  #    #=> prints "Working time"
  #
  #    case dt
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
  #    if d in DateTime(wday: 1..5, hour: 10..18, day: ..7)
  #      puts "Working time, first week of the month"
  #    end
  def deconstruct_keys(keys)
    if keys
      if keys.size == 1
        case keys[0]
        when :year
          internal_civil unless @year
          { year: @year }
        when :month
          internal_civil unless @year
          { month: @month }
        when :day
          internal_civil unless @year
          { day: @day }
        when :wday         then { wday: (@jd + 1) % 7 }
        when :yday         then { yday: yday }
        when :hour         then { hour: @hour }
        when :min          then { min: @min }
        when :sec          then { sec: @sec_i }
        when :sec_fraction then { sec_fraction: @sec_frac }
        when :zone         then { zone: _of2str(@of) }
        else {}
        end
      else
        internal_civil unless @year
        h = {}
        keys.each do |k|
          case k
          when :year         then h[:year] = @year
          when :month        then h[:month] = @month
          when :day          then h[:day] = @day
          when :wday         then h[:wday] = (@jd + 1) % 7
          when :yday         then h[:yday] = yday
          when :hour         then h[:hour] = @hour
          when :min          then h[:min] = @min
          when :sec          then h[:sec] = @sec_i
          when :sec_fraction then h[:sec_fraction] = @sec_frac
          when :zone         then h[:zone] = _of2str(@of)
          end
        end
        h
      end
    else
      internal_civil unless @year
      { year: @year, month: @month, day: @day, wday: (@jd + 1) % 7, yday: yday,
        hour: @hour, min: @min, sec: @sec_i, sec_fraction: @sec_frac, zone: _of2str(@of) }
    end
  end

  DATETIME_TO_S_FMT = '%Y-%m-%dT%H:%M:%S%:z'.encode(Encoding::US_ASCII).freeze
  private_constant :DATETIME_TO_S_FMT

  # call-seq:
  #    dt.to_s  ->  string
  #
  # Returns a string in an ISO 8601 format. (This method doesn't use the
  # expanded representations.)
  #
  #     DateTime.new(2001,2,3,4,5,6,'-7').to_s
  #				#=> "2001-02-03T04:05:06-07:00"
  def to_s
    strftime(DATETIME_TO_S_FMT)
  end

  def hash
    if @hour == 0 && @min == 0 && @sec_i == 0
      [@jd, @sg].hash
    else
      [@jd, @hour, @min, @sec_i, @sg].hash
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization override
  # ---------------------------------------------------------------------------

  # :nodoc:
  def marshal_dump
    # 6-element format: [nth, jd, df, sf, of, sg]
    df = @hour * 3600 + @min * 60 + @sec_i
    sf = (@sec_frac * 1_000_000_000).to_r  # nanoseconds as Rational
    [0, @jd, df, sf, @of, @sg]
  end

  # :nodoc:
  def marshal_load(array)
    case array.length
    when 2
      jd_like, sg_or_bool = array
      sg = sg_or_bool == true ? ITALY : (sg_or_bool == false ? JULIAN : sg_or_bool.to_f)
      _init_datetime(jd_like.to_i, 0, 0, 0, Rational(0), 0, sg)
    when 3
      ajd, of_r, sg = array
      of_sec = (of_r * 86400).to_i
      # Reconstruct local JD and time from AJD
      local_r = ajd + Rational(1, 2) + of_r
      jd      = local_r.floor
      rem_r   = (local_r - jd) * 86400
      h       = rem_r.to_i / 3600
      rem_r -= h * 3600
      m       = rem_r.to_i / 60
      s_r = rem_r - m * 60
      s_i, s_f = _split_second(s_r)
      _init_datetime(jd, h, m, s_i, s_f, of_sec, sg)
    when 6
      _nth, jd, df, sf, of, sg = array
      h  = df / 3600
      df -= h * 3600
      m  = df / 60
      s  = df % 60
      sf_r = sf.is_a?(Rational) ? (sf / 1_000_000_000) : Rational(sf.to_i, 1_000_000_000)
      _init_datetime(jd, h, m, s, sf_r, of, sg)
    else
      raise TypeError, "invalid marshal data"
    end
  end

  # ---------------------------------------------------------------------------
  # Type conversions
  # ---------------------------------------------------------------------------

  # call-seq:
  #    dt.to_date  ->  date
  #
  # Returns a Date object which denotes self.
  def to_date
    Date.__send__(:new_from_jd, @jd, @sg)
  end

  # call-seq:
  #    dt.to_datetime  ->  self
  #
  # Returns self.
  def to_datetime
    self
  end

  # call-seq:
  #    dt.to_time  ->  time
  #
  # Returns a Time object which denotes self.
  def to_time
    y, m, d = self.class.__send__(:jd_to_gregorian, @jd)
    if @of == 0
      Time.utc(y, m, d, @hour, @min, @sec_i + @sec_frac)
    else
      Time.new(y, m, d, @hour, @min, @sec_i + @sec_frac, @of)
    end
  end

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  class << self
    def new(year = -4712, month = 1, day = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      instance = allocate
      instance.__send__(:initialize, year, month, day, hour, minute, second, offset, start)
      instance
    end
    alias_method :civil, :new

    undef_method :today

    # call-seq:
    #    DateTime._strptime(string[, format='%FT%T%z'])  ->  hash
    #
    # Parses the given representation of date and time with the given
    # template, and returns a hash of parsed elements.  _strptime does
    # not support specification of flags and width unlike strftime.
    #
    # See also strptime(3) and #strftime.
    def _strptime(string = JULIAN_EPOCH_DATETIME, format = '%FT%T%z')
      Date._strptime(string, format)
    end

    # call-seq:
    #    DateTime.strptime([string='-4712-01-01T00:00:00+00:00'[, format='%FT%T%z'[ ,start=Date::ITALY]]])  ->  datetime
    #
    # Parses the given representation of date and time with the given
    # template, and creates a DateTime object.  strptime does not support
    # specification of flags and width unlike strftime.
    #
    #    DateTime.strptime('2001-02-03T04:05:06+07:00', '%Y-%m-%dT%H:%M:%S%z')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.strptime('03-02-2001 04:05:06 PM', '%d-%m-%Y %I:%M:%S %p')
    #				#=> #<DateTime: 2001-02-03T16:05:06+00:00 ...>
    #    DateTime.strptime('2001-W05-6T04:05:06+07:00', '%G-W%V-%uT%H:%M:%S%z')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.strptime('2001 04 6 04 05 06 +7', '%Y %U %w %H %M %S %z')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.strptime('2001 05 6 04 05 06 +7', '%Y %W %u %H %M %S %z')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.strptime('-1', '%s')
    #				#=> #<DateTime: 1969-12-31T23:59:59+00:00 ...>
    #    DateTime.strptime('-1000', '%Q')
    #				#=> #<DateTime: 1969-12-31T23:59:59+00:00 ...>
    #    DateTime.strptime('sat3feb014pm+7', '%a%d%b%y%H%p%z')
    #				#=> #<DateTime: 2001-02-03T16:00:00+07:00 ...>
    #
    # See also strptime(3) and #strftime.
    def strptime(string = JULIAN_EPOCH_DATETIME, format = '%FT%T%z', start = Date::ITALY)
      hash = _strptime(string, format)
      _dt_new_by_frags(hash, start)
    end

    # call-seq:
    #    DateTime.jd([jd=0[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]])  ->  datetime
    #
    # Creates a DateTime object denoting the given chronological Julian
    # day number.
    #
    #    DateTime.jd(2451944)	#=> #<DateTime: 2001-02-03T00:00:00+00:00 ...>
    #    DateTime.jd(2451945)	#=> #<DateTime: 2001-02-04T00:00:00+00:00 ...>
    #    DateTime.jd(Rational('0.5'))
    #				#=> #<DateTime: -4712-01-01T12:00:00+00:00 ...>
    def jd(jd = 0, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      raise TypeError, "no implicit conversion of #{jd.class} into Integer" unless jd.is_a?(Numeric)
      jd_r = jd.to_r
      jd_i = jd_r.floor
      h = Integer(hour)
      m = Integer(minute)
      of_sec = _parse_of(offset)
      if jd_i != jd_r
        # Fractional JD: convert fraction to extra seconds and handle overflow
        frac_sec = (jd_r - jd_i) * 86400
        second = second.to_r + frac_sec
        sec_i, sec_f = _split_sec(second)
        if sec_i >= 60
          carry_m, sec_i = sec_i.divmod(60)
          m += carry_m
        end
        if m >= 60
          carry_h, m = m.divmod(60)
          h += carry_h
        end
        if h >= 24
          carry_d, h = h.divmod(24)
          jd_i += carry_d
        end
      else
        # Integer JD: pass raw values to _normalize_hms (non-cascading)
        sec_i, sec_f = _split_sec(second)
      end
      _new_dt_from_jd_time(jd_i, h, m, sec_i, sec_f, of_sec, start)
    end

    # call-seq:
    #    DateTime.ordinal([year=-4712[, yday=1[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]]])  ->  datetime
    #
    # Creates a DateTime object denoting the given ordinal date.
    #
    #    DateTime.ordinal(2001,34)	#=> #<DateTime: 2001-02-03T00:00:00+00:00 ...>
    #    DateTime.ordinal(2001,34,4,5,6,'+7')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.ordinal(2001,-332,-20,-55,-54,'+7')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    def ordinal(year = -4712, yday = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      jd_v = internal_valid_ordinal?(Integer(year), Integer(yday), start)
      raise Date::Error, "invalid date" unless jd_v
      of_sec = _parse_of(offset)
      sec_i, sec_f = _split_sec(second)
      _new_dt_from_jd_time(jd_v, Integer(hour), Integer(minute), sec_i, sec_f, of_sec, start)
    end

    # call-seq:
    #    DateTime.commercial([cwyear=-4712[, cweek=1[, cwday=1[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]]]])  ->  datetime
    #
    # Creates a DateTime object denoting the given week date.
    #
    #    DateTime.commercial(2001)	#=> #<DateTime: 2001-01-01T00:00:00+00:00 ...>
    #    DateTime.commercial(2002)	#=> #<DateTime: 2001-12-31T00:00:00+00:00 ...>
    #    DateTime.commercial(2001,5,6,4,5,6,'+7')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    def commercial(cwyear = -4712, cweek = 1, cwday = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      jd_v = internal_valid_commercial?(Integer(cwyear), Integer(cweek), Integer(cwday), start)
      raise Date::Error, "invalid date" unless jd_v
      of_sec = _parse_of(offset)
      sec_i, sec_f = _split_sec(second)
      _new_dt_from_jd_time(jd_v, Integer(hour), Integer(minute), sec_i, sec_f, of_sec, start)
    end

    # call-seq:
    #    DateTime.now([start=Date::ITALY])  ->  datetime
    #
    # Creates a DateTime object denoting the present time.
    #
    #    DateTime.now		#=> #<DateTime: 2011-06-11T21:20:44+09:00 ...>
    def now(start = Date::ITALY)
      t = Time.now
      jd = civil_to_jd(t.year, t.mon, t.mday, start)
      sec_f = Rational(t.subsec)
      _new_dt_from_jd_time(jd, t.hour, t.min, t.sec, sec_f, t.utc_offset, start)
    end

    # call-seq:
    #   DateTime.weeknum(year=-4712, week=0, wday=1, wstart=0, hour=0, min=0, sec=0, offset=0, start=Date::ITALY) -> datetime
    def weeknum(year = -4712, week = 0, wday = 1, wstart = 0,
                hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      jd     = weeknum_to_jd(Integer(year), Integer(week), Integer(wday), Integer(wstart), start)
      of_sec = _parse_of(offset)
      sec_i, sec_f = _split_sec(second)
      _new_dt_from_jd_time(jd, Integer(hour), Integer(minute), sec_i, sec_f, of_sec, start)
    end

    # call-seq:
    #   DateTime.nth_kday(year=-4712, month=1, n=1, k=1, hour=0, min=0, sec=0, offset=0, start=Date::ITALY) -> datetime
    def nth_kday(year = -4712, month = 1, n = 1, k = 1,
                 hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
      jd     = nth_kday_to_jd(Integer(year), Integer(month), Integer(n), Integer(k), start)
      of_sec = _parse_of(offset)
      sec_i, sec_f = _split_sec(second)
      _new_dt_from_jd_time(jd, Integer(hour), Integer(minute), sec_i, sec_f, of_sec, start)
    end

    # :nodoc:
    def _new_dt_from_jd_time(jd, h, m, s, sf, of, sg)
      jd, h, m, s = _normalize_hms(jd, h, m, s)
      obj = allocate
      obj.__send__(:_init_datetime, jd, h, m, s, sf, of, sg)
      obj
    end

    # Normalize hour/min/sec.
    # Negative values: add one period (non-cascading, matching C's c_valid_time_f?).
    # After normalization, validate ranges and raise Date::Error if out of range.
    # 24:00:00 is valid (normalizes to next day 00:00:00).
    def _normalize_hms(jd, h, m, s)
      s += 60 if s < 0
      m += 60 if m < 0
      h += 24 if h < 0
      raise Date::Error, "invalid date" if s >= 60
      raise Date::Error, "invalid date" if m >= 60
      raise Date::Error, "invalid date" if h >  24 || h < 0
      raise Date::Error, "invalid date" if h == 24 && (m != 0 || s != 0)
      if h == 24
        jd += 1
        h = 0
      end
      [jd, h, m, s]
    end

    # call-seq:
    #    DateTime.parse(string='-4712-01-01T00:00:00+00:00'[, comp=true[, start=Date::ITALY]], limit: 128)  ->  datetime
    #
    # Parses the given representation of date and time, and creates a
    # DateTime object.
    #
    # This method *does* *not* function as a validator.  If the input
    # string does not match valid formats strictly, you may get a cryptic
    # result.  Should consider to use DateTime.strptime instead of this
    # method as possible.
    #
    # If the optional second argument is true and the detected year is in
    # the range "00" to "99", makes it full.
    #
    #    DateTime.parse('2001-02-03T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.parse('20010203T040506+0700')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.parse('3rd Feb 2001 04:05:06 PM')
    #				#=> #<DateTime: 2001-02-03T16:05:06+00:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def parse(string = '-4712-01-01T00:00:00+00:00', comp = true, start = Date::ITALY, limit: 128)
      hash = Date._parse(string, comp, limit: limit)
      _dt_new_by_frags(hash, start)
    end

    # call-seq:
    #    DateTime.iso8601(string='-4712-01-01T00:00:00+00:00'[, start=Date::ITALY], limit: 128)  ->  datetime
    #
    # Creates a new DateTime object by parsing from a string according to
    # some typical ISO 8601 formats.
    #
    #    DateTime.iso8601('2001-02-03T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.iso8601('20010203T040506+0700')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #    DateTime.iso8601('2001-W05-6T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def iso8601(string = '-4712-01-01T00:00:00+00:00', start = Date::ITALY, limit: 128)
      hash = Date._iso8601(string, limit: limit)
      _dt_new_by_frags(hash, start)
    end

    # call-seq:
    #    DateTime.rfc3339(string='-4712-01-01T00:00:00+00:00'[, start=Date::ITALY], limit: 128)  ->  datetime
    #
    # Creates a new DateTime object by parsing from a string according to
    # some typical RFC 3339 formats.
    #
    #    DateTime.rfc3339('2001-02-03T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def rfc3339(string = '-4712-01-01T00:00:00+00:00', start = Date::ITALY, limit: 128)
      hash = Date._rfc3339(string, limit: limit)
      _dt_new_by_frags(hash, start)
    end

    # call-seq:
    #    DateTime.xmlschema(string='-4712-01-01T00:00:00+00:00'[, start=Date::ITALY], limit: 128)  ->  datetime
    #
    # Creates a new DateTime object by parsing from a string according to
    # some typical XML Schema formats.
    #
    #    DateTime.xmlschema('2001-02-03T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def xmlschema(string = '-4712-01-01T00:00:00+00:00', start = Date::ITALY, limit: 128)
      hash = Date._xmlschema(string, limit: limit)
      _dt_new_by_frags(hash, start)
    end

    # call-seq:
    #    DateTime.rfc2822(string='Mon, 1 Jan -4712 00:00:00 +0000'[, start=Date::ITALY], limit: 128)  ->  datetime
    #    DateTime.rfc822(string='Mon, 1 Jan -4712 00:00:00 +0000'[, start=Date::ITALY], limit: 128)   ->  datetime
    #
    # Creates a new DateTime object by parsing from a string according to
    # some typical RFC 2822 formats.
    #
    #     DateTime.rfc2822('Sat, 3 Feb 2001 04:05:06 +0700')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def rfc2822(string = 'Mon, 1 Jan -4712 00:00:00 +0000', start = Date::ITALY, limit: 128)
      hash = Date._rfc2822(string, limit: limit)
      _dt_new_by_frags(hash, start)
    end
    alias rfc822 rfc2822

    # call-seq:
    #    DateTime.httpdate(string='Mon, 01 Jan -4712 00:00:00 GMT'[, start=Date::ITALY])  ->  datetime
    #
    # Creates a new DateTime object by parsing from a string according to
    # some RFC 2616 format.
    #
    #    DateTime.httpdate('Sat, 03 Feb 2001 04:05:06 GMT')
    #				#=> #<DateTime: 2001-02-03T04:05:06+00:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def httpdate(string = 'Mon, 01 Jan -4712 00:00:00 GMT', start = Date::ITALY, limit: 128)
      hash = Date._httpdate(string, limit: limit)
      _dt_new_by_frags(hash, start)
    end

    # call-seq:
    #    DateTime.jisx0301(string='-4712-01-01T00:00:00+00:00'[, start=Date::ITALY], limit: 128)  ->  datetime
    #
    # Creates a new DateTime object by parsing from a string according to
    # some typical JIS X 0301 formats.
    #
    #    DateTime.jisx0301('H13.02.03T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #
    # For no-era year, legacy format, Heisei is assumed.
    #
    #    DateTime.jisx0301('13.02.03T04:05:06+07:00')
    #				#=> #<DateTime: 2001-02-03T04:05:06+07:00 ...>
    #
    # Raise an ArgumentError when the string length is longer than _limit_.
    # You can stop this check by passing <code>limit: nil</code>, but note
    # that it may take a long time to parse.
    def jisx0301(string = '-4712-01-01T00:00:00+00:00', start = Date::ITALY, limit: 128)
      hash = Date._jisx0301(string, limit: limit)
      _dt_new_by_frags(hash, start)
    end

    private

    # Create a DateTime object from parsed fragment hash.
    # Uses the same fragment rewrite/complete/validate logic as Date._new_by_frags
    # but additionally extracts time components (hour, min, sec, offset, sec_fraction).
    def _dt_new_by_frags(hash, sg) # rubocop:disable Metrics/MethodLength
      raise Date::Error, 'invalid date' if hash.nil?
      hash = _sp_rewrite_frags(hash)
      orig_sec = hash[:sec]
      hash = _sp_complete_frags(DateTime, hash)
      jd   = _sp_valid_date_frags_p(hash, sg)
      raise Date::Error, 'invalid date' if jd.nil?

      h  = hash[:hour] || 0
      m  = hash[:min]  || 0
      s  = hash[:sec]  || 0
      raise Date::Error, 'invalid date' if orig_sec && orig_sec > 60
      s  = 59 if s > 59
      of = hash[:offset] || 0
      if of.is_a?(Numeric) && (of < -86400 || of > 86400)
        warn("invalid offset is ignored: #{of}", uplevel: 0)
        of = 0
      end
      sf = hash[:sec_fraction] || Rational(0)
      _new_dt_from_jd_time(jd, h, m, s, sf, of, sg)
    end

    def _parse_of(offset)
      case offset
      when String
        Date.__send__(:offset_str_to_sec, offset)
      when Rational
        (offset * 86400).to_i
      when Numeric
        (offset * 86400).to_i
      else
        0
      end
    end

    def _split_sec(second)
      if second.is_a?(Rational) || second.is_a?(Float)
        s_r = second.to_r
        s_i = s_r.floor
        [s_i, s_r - s_i]
      else
        [Integer(second), Rational(0)]
      end
    end

  end

  # ---------------------------------------------------------------------------
  # Private helpers (strftime overrides)
  # ---------------------------------------------------------------------------

  private

  def internal_hour
    @hour
  end

  def internal_min
    @min
  end

  def internal_sec
    @sec_i
  end

  def _sec_frac
    @sec_frac
  end

  def _of_seconds
    @of
  end

  def _zone_str
    _of2str(@of)
  end

  def _init_datetime(jd, h, m, s, sf, of, sg)
    @jd       = jd
    @sg       = sg
    @hour     = h
    @min      = m
    @sec_i    = s
    @sec_frac = sf.is_a?(Rational) ? sf : Rational(sf)
    @of       = of.to_i
  end

  def _split_second(second)
    if second.is_a?(Rational) || second.is_a?(Float)
      s_r = second.to_r
      s_i = s_r.floor
      [s_i, s_r - s_i]
    else
      [Integer(second), Rational(0)]
    end
  end

  def _str_offset_to_sec(offset)
    case offset
    when String
      self.class.__send__(:_parse_of, offset)
    when Rational
      (offset * 86400).to_i
    when Numeric
      r = offset.to_r
      raise TypeError, "#{offset.class} can't be used as offset" unless r.is_a?(Rational)
      (r * 86400).to_i
    else
      0
    end
  end

  def _of2str(of)
    sign = of < 0 ? '-' : '+'
    abs  = of.abs
    h    = abs / 3600
    m    = (abs % 3600) / 60
    format('%s%02d:%02d'.encode(Encoding::US_ASCII), sign, h, m)
  end

  def _from_total_sec_r(total_r)
    jd  = (total_r / 86400).floor
    rem = total_r - jd * 86400
    h   = rem.to_i / 3600
    rem -= h * 3600
    m   = rem.to_i / 60
    s_r = rem - m * 60
    s_i = s_r.floor
    s_f = s_r - s_i
    self.class.__send__(:_new_dt_from_jd_time,jd, h, m, s_i, s_f, @of, @sg)
  end

end
