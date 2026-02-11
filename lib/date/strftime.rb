# Implementation of ruby/date/ext/date/date_strftime.c
class Date
  # call-seq:
  #   strftime(format = '%F') -> string
  #
  # Returns a string representation of the date in +self+,
  # formatted according the given +format+:
  #
  #   Date.new(2001, 2, 3).strftime # => "2001-02-03"
  #
  # For other formats, see
  # {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc].
  def strftime(format = STRFTIME_DEFAULT_FMT)
    # If format is not a string, convert it to a string.
    format = format.to_str unless format.is_a?(String)

    # Check for ASCII compatible encoding.
    raise ArgumentError, "format should have ASCII compatible encoding" unless format.encoding.ascii_compatible?

    # Empty format returns empty string
    return '' if format.empty?

    # What to do if format string contains a "\0".
    if format.include?("\0")
      result = String.new
      parts = format.split("\0", -1)

      parts.each_with_index do |part, i|
        result << strftime_format(part) unless part.empty?
        result << "\0" if i < parts.length - 1
      end

      result.force_encoding(format.encoding)

      return result
    end

    # Normal processing without "\0" in format string.
    result = strftime_format(format)
    result.force_encoding(format.encoding)

    result
  end

  private

  def tmx_year
    m_real_year
  end

  def tmx_mon
    mon
  end

  def tmx_mday
    mday
  end

  def tmx_yday
    yday
  end

  def tmx_cwyear
    m_real_cwyear
  end

  def tmx_cweek
    cweek
  end

  def tmx_cwday
    cwday
  end

  def tmx_wday
    wday
  end

  def tmx_wnum0
    # Week number (Sunday start, 00-53)
    m_wnumx(0)
  end

  def tmx_wnum1
    # Week number (Monday start, 00-53)
    m_wnumx(1)
  end

  def tmx_hour
    if simple_dat_p?
      0
    else
      df = df_utc_to_local(m_df, m_of)
      (df / 3600).floor
    end
  end

  def tmx_min
    if simple_dat_p?
      0
    else
      df = df_utc_to_local(m_df, m_of)
      ((df % 3600) / 60).floor
    end
  end

  def tmx_sec
    if simple_dat_p?
      0
    else
      df = df_utc_to_local(m_df, m_of)
      df % 60
    end
  end

  def tmx_sec_fraction
    if simple_dat_p?
      Rational(0, 1)
    else
      # (Decimal part of df) + sf
      df_frac = m_df - m_df.floor
      sf_frac = m_sf == 0 ? 0 : Rational(m_sf, SECOND_IN_NANOSECONDS)
      df_frac + sf_frac
    end
  end

  def tmx_secs
    # C: tmx_m_secs (date_core.c:7306)
    # s = day_to_sec(m_real_jd - UNIX_EPOCH_IN_CJD)
    # if complex: s += m_df
    s = jd_to_unix_time(m_real_jd)
    return s if simple_dat_p?
    df = m_df
    s += df if df != 0
    s
  end

  def tmx_msecs
    # C: tmx_m_msecs (date_core.c:7322)
    # s = tmx_m_secs * 1000
    # if complex: s += m_sf / MILLISECOND_IN_NANOSECONDS
    s = tmx_secs * SECOND_IN_MILLISECONDS
    return s if simple_dat_p?
    sf = m_sf
    s += (sf / (SECOND_IN_NANOSECONDS / SECOND_IN_MILLISECONDS)).to_i if sf != 0
    s
  end

  def tmx_offset
    simple_dat_p? ? 0 : m_of
  end

  def tmx_zone
    if simple_dat_p? || tmx_offset.zero?
      "+00:00"
    else
      of2str(m_of)
    end
  end

  def of2str(of)
    s, h, m = decode_offset(of)
    sprintf('%c%02d:%02d', s, h, m)
  end

  def decode_offset(of)
    s = (of < 0) ? '-' : '+'
    a = of.abs
    h = a / HOUR_IN_SECONDS
    m = (a % HOUR_IN_SECONDS) / MINUTE_IN_SECONDS
    [s, h, m]
  end

  # Processing format strings.
  def strftime_format(format)
    result = String.new
    i = 0

    while i < format.length
      if format[i] == '%' && i + 1 < format.length
        # Skip '%'
        i += 1

        # C: Parse all modifiers in a flat loop (flags, width, colons, E/O)
        flags = String.new
        width = String.new
        modifier = nil
        colons = 0

        while i < format.length
          c = format[i]
          case c
          when 'E', 'O'
            modifier = c
            i += 1
          when ':'
            colons += 1
            i += 1
          when '-', '_', '^', '#'
            flags << c
            i += 1
          when '0'
            # '0' is a flag only when width is still empty
            if width.empty?
              flags << c
              i += 1
            else
              width << c
              i += 1
            end
          when /[1-9]/
            width << c
            i += 1
            # Continue reading remaining digits
            while i < format.length && format[i] =~ /[0-9]/
              width << format[i]
              i += 1
            end
          else
            break
          end
        end

        # Invalid if both E/O and colon modifiers are present.
        if modifier && colons > 0
          if i < format.length
            spec = format[i]
            result << "%#{modifier}#{':' * colons}#{spec}"
            i += 1
          end
          next
        end

        # Width specifier overflow check
        unless width.empty?
          if width.length > 10 || (width.length == 10 && width > '2147483647')
            raise Errno::ERANGE, "Result too large"
          end
          if width.to_i >= 1024
            raise Errno::ERANGE, "Result too large"
          end
        end

        if i < format.length
          spec = format[i]

          if modifier
            # E/O modifier check must come first
            valid = case modifier
            when 'E'
              %w[c C x X y Y].include?(spec)
            when 'O'
              %w[d e H k I l m M S u U V w W y].include?(spec)
            else
              false
            end

            if valid
              formatted = format_spec(spec, flags, width)
              result << formatted
            else
              result << "%#{modifier}#{flags}#{width}#{spec}"
            end
          elsif spec == 'z'
            # %z with any combination of colons/width/flags
            formatted = format_z(tmx_offset, width, flags, colons)
            result << formatted
          elsif colons > 0
            # Colon modifier is only valid for 'z'.
            result << "%#{':' * colons}#{flags}#{width}#{spec}"
          else
            formatted = format_spec(spec, flags, width)
            result << formatted
          end

          i += 1
        end
      else
        result << format[i]
        i += 1
      end
    end

    result.force_encoding('US-ASCII') if result.ascii_only?

    result
  end

  def format_spec(spec, flags = '', width = '')
    # N/L: width controls precision (number of fractional digits)
    if spec == 'N' || spec == 'L'
      precision = if !width.empty?
                    width.to_i
                  elsif spec == 'L'
                    3
                  else
                    9
                  end
      frac = tmx_sec_fraction
      digits = (frac * (10 ** precision)).floor
      return sprintf("%0#{precision}d", digits)
    end

    # Get basic formatting results.
    base_result = get_base_format(spec, flags)

    # Apply case change flags (before width/precision)
    base_result = apply_case_flags(base_result, spec, flags)

    # Apply width specifier.
    if !width.empty?
      width_num = width.to_i
      default_pad = if NUMERIC_SPECS.include?(spec)
                      '0'
                    elsif SPACE_PAD_SPECS.include?(spec)
                      ' '
                    else
                      ' '
                    end
      apply_width(base_result, width_num, flags, default_pad)
    else
      base_result
    end
  end

  # C: Apply ^ (UPPER) and # (CHCASE) flags
  def apply_case_flags(str, spec, flags)
    if flags.include?('^')
      str.upcase
    elsif flags.include?('#')
      if CHCASE_UPPER_SPECS.include?(spec)
        str.upcase
      elsif CHCASE_LOWER_SPECS.include?(spec)
        str.downcase
      else
        str.swapcase
      end
    else
      str
    end
  end

  # format specifiers
  def get_base_format(spec, flags = '')
    case spec
    when 'Y' # 4-digit year
      y = tmx_year
      raise Errno::ERANGE, "Result too large" if y.is_a?(Integer) && y.bit_length > 128
      # C: FMT('0', y >= 0 ? 4 : 5, "ld", y)
      prec = y < 0 ? 5 : 4
      if flags.include?('-')
        y.to_s
      elsif flags.include?('_')
        sprintf("%#{prec}d", y)
      else
        sprintf("%0#{prec}d", y)
      end
    when 'C' # Century
      sprintf('%02d', tmx_year / 100)
    when 'y' # Two-digit year
      sprintf('%02d', tmx_year % 100)
    when 'm' # Month (01-12)
      sprintf('%02d', tmx_mon)
    when 'B' # Full month name
      MONTHNAMES[tmx_mon] || '?'
    when 'b', 'h' # Abbreviated month name
      (ABBR_MONTHNAMES[tmx_mon] || '?')[0, 3]
    when 'd' # Day (01-31)
      if flags.include?('-')
        # Left-justified (no padding)
        tmx_mday.to_s
      elsif flags.include?('_')
        # Space-padded
        sprintf('%2d', tmx_mday)
      else
        # Zero-padded (default)
        sprintf('%02d', tmx_mday)
      end
    when 'e' # Day (1-31) blank filled
      if flags.include?('-')
        tmx_mday.to_s
      elsif flags.include?('0')
        sprintf('%02d', tmx_mday)
      else
        sprintf('%2d', tmx_mday)
      end
    when 'j' # Day of the year (001-366)
      if flags.include?('-')
        tmx_yday.to_s
      else
        sprintf('%03d', tmx_yday)
      end
    when 'H' # Hour (00-23)
      if flags.include?('-')
        tmx_hour.to_s
      elsif flags.include?('_')
        sprintf('%2d', tmx_hour)
      else
        sprintf('%02d', tmx_hour)
      end
    when 'k' # Hour (0-23) blank-padded
      sprintf('%2d', tmx_hour)
    when 'I' # Hour (01-12)
      h = tmx_hour % 12
      h = 12 if h.zero?
      if flags.include?('-')
        h.to_s
      elsif flags.include?('_')
        sprintf('%2d', h)
      else
        sprintf('%02d', h)
      end
    when 'l' # Hour (1-12) blank filled
      h = tmx_hour % 12
      h = 12 if h.zero?
      sprintf('%2d', h)
    when 'M' # Minutes (00-59)
      if flags.include?('-')
        tmx_min.to_s
      elsif flags.include?('_')
        sprintf('%2d', tmx_min)
      else
        sprintf('%02d', tmx_min)
      end
    when 'S' # Seconds (00-59)
      if flags.include?('-')
        tmx_sec.to_s
      elsif flags.include?('_')
        sprintf('%2d', tmx_sec)
      else
        sprintf('%02d', tmx_sec)
      end
    when 'L' # Milliseconds (000-999)
      sprintf('%09d', (tmx_sec_fraction * 1_000_000_000).floor)
    when 'N' # Fractional seconds digits
      # C: width controls precision (number of digits), default 9.
      # %3N → 3 digits (milliseconds), %6N → 6 digits (microseconds),
      # %9N → 9 digits (nanoseconds), %12N → 12 digits (picoseconds, zero-padded).
      # The 'width' variable is handled specially in format_spec for 'N'.
      sprintf('%09d', (tmx_sec_fraction * 1_000_000_000).floor)
    when 'P' # am/pm
      tmx_hour < 12 ? 'am' : 'pm'
    when 'p' # AM/PM
      tmx_hour < 12 ? 'AM' : 'PM'
    when 'A' # Full name of the day of the week
      DAYNAMES[tmx_wday] || '?'
    when 'a' # Abbreviated day of the week
      (ABBR_DAYNAMES[tmx_wday] || '?')[0, 3]
    when 'w' # Day of the week (0-6, Sunday is 0)
      tmx_wday.to_s
    when 'u' # Day of the week (1-7, Monday is 1)
      tmx_cwday.to_s
    when 'U' # Week number (00-53, Sunday start)
      sprintf('%02d', tmx_wnum0)
    when 'W' # Week number (00-53, Monday start)
      sprintf('%02d', tmx_wnum1)
    when 'V' # ISO week number (01-53)
      sprintf('%02d', tmx_cweek)
    when 'G' # ISO week year
      y = tmx_cwyear
      prec = y < 0 ? 5 : 4
      if flags.include?('-')
        y.to_s
      elsif flags.include?('_')
        sprintf("%#{prec}d", y)
      else
        sprintf("%0#{prec}d", y)
      end
    when 'g' # ISO week year (2 digits)
      sprintf('%02d', tmx_cwyear % 100)
    when 'z' # Time Zone Offset (+0900) — handled by format_z in format_spec
      format_z(tmx_offset, '', '', 0)
    when 'Z' # Time Zone Name
      tmx_zone || ''
    when 's' # Number of seconds since the Unix epoch
      tmx_secs.to_s
    when 'Q' # Milliseconds since the Unix epoch
      tmx_msecs.to_s
    when 'n' # Line breaks
      "\n"
    when 't' # Tab
      "\t"
    when '%' # % symbol
      '%'
    when 'F' # %Y-%m-%d
      strftime_format('%Y-%m-%d')
    when 'D' # %m/%d/%y
      strftime_format('%m/%d/%y')
    when 'x' # %m/%d/%y
      strftime_format('%m/%d/%y')
    when 'T', 'X' # %H:%M:%S
      strftime_format('%H:%M:%S')
    when 'R' # %H:%M
      strftime_format('%H:%M')
    when 'r' # %I:%M:%S %p
      strftime_format('%I:%M:%S %p')
    when 'c' # %a %b %e %H:%M:%S %Y
      strftime_format('%a %b %e %H:%M:%S %Y')
    when 'v' # %e-%^b-%Y (3-FEB-2001 format)
      day_str = sprintf('%2d', tmx_mday)
      month_str = (ABBR_MONTHNAMES[tmx_mon] || '?')[0, 3].upcase
      year_str = sprintf('%04d', tmx_year)
      "#{day_str}-#{month_str}-#{year_str}"
    when '+' # %a %b %e %H:%M:%S %Z %Y
      strftime_format('%a %b %e %H:%M:%S %Z %Y')
    else
      # Unknown specifiers are output as is.
      "%#{spec}"
    end
  end

  def apply_width(str, width, flags, default_pad = ' ')
    # '-' flag means no padding at all
    return str if flags.include?('-')
    return str if str.length >= width

    # Determine a padding character.
    padding =
      if flags.include?('0')
        '0'
      elsif flags.include?('_')
        ' '
      else
        default_pad
      end

    str.rjust(width, padding)
  end

  # C: format %z with width/flags/colons support
  # Matches date_strftime.c case 'z' logic exactly.
  def format_z(offset, width_str, flags, colons)
    sign = offset < 0 ? '-' : '+'
    aoff = offset.abs
    hours = aoff / 3600
    minutes = (aoff % 3600) / 60
    seconds = aoff % 60

    hl = hours < 10 ? 1 : 2  # actual digits needed for hours
    hw = 2                     # default hour width
    hw = 1 if flags.include?('-') && hl == 1

    precision = width_str.empty? ? -1 : width_str.to_i

    # Calculate fixed chars (everything except hour digits) per colons variant
    fixed = case colons
            when 0 then 3  # sign(1) + mm(2)
            when 1 then 4  # sign(1) + :(1) + mm(2)
            when 2 then 7  # sign(1) + :(1) + mm(2) + :(1) + ss(2)
            when 3
              if (aoff % 3600).zero?
                1  # sign(1) only
              elsif (aoff % 60).zero?
                4  # sign(1) + :(1) + mm(2)
              else
                7  # sign(1) + :(1) + mm(2) + :(1) + ss(2)
              end
            else
              3
            end

    # C: hour_precision = precision <= (fixed + hw) ? hw : precision - fixed
    hp = precision <= (fixed + hw) ? hw : precision - fixed

    result = String.new

    # C: space padding — print spaces before sign, reduce hour precision
    if flags.include?('_') && hp > hl
      result << ' ' * (hp - hl)
      hp = hl
    end

    result << sign
    result << sprintf("%0#{hp}d", hours)

    # Append minutes/seconds based on colons
    case colons
    when 0
      result << sprintf('%02d', minutes)
    when 1
      result << sprintf(':%02d', minutes)
    when 2
      result << sprintf(':%02d:%02d', minutes, seconds)
    when 3
      unless (aoff % 3600).zero?
        result << sprintf(':%02d', minutes)
        unless (aoff % 60).zero?
          result << sprintf(':%02d', seconds)
        end
      end
    end

    result
  end

  def jd_to_unix_time(jd)
    unix_epoch_jd = 2440588
    (jd - unix_epoch_jd) * DAY_IN_SECONDS
  end
end
