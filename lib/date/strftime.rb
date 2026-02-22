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

    # Fast path: simple Date (no time/offset, @nth == 0) with civil fields cached.
    # Covers the most common case for Date objects created via Date.new or Date.civil.
    if @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_civil && !format.include?("\0")
      y = @year
      case format
      when '%Y-%m-%d', '%F'
        str = if y >= 0 && y <= 9999
                "#{FOUR_DIGIT[y]}-#{TWO_DIGIT[@month]}-#{TWO_DIGIT[@day]}"
              elsif y >= 0
                sprintf("%04d-%02d-%02d", y, @month, @day)
              else
                sprintf("%05d-%02d-%02d", y, @month, @day)
              end
        return str.force_encoding(format.encoding)
      when '%Y-%m-%dT%H:%M:%S%z'
        str = if y >= 0 && y <= 9999
                "#{FOUR_DIGIT[y]}-#{TWO_DIGIT[@month]}-#{TWO_DIGIT[@day]}T00:00:00+0000"
              elsif y >= 0
                sprintf("%04d-%02d-%02dT00:00:00+0000", y, @month, @day)
              else
                sprintf("%05d-%02d-%02dT00:00:00+0000", y, @month, @day)
              end
        return str.force_encoding(format.encoding)
      when '%x'
        # %x = %m/%d/%y
        str = "#{TWO_DIGIT[@month]}/#{TWO_DIGIT[@day]}/#{TWO_DIGIT[y % 100]}"
        return str.force_encoding(format.encoding)
      end

      # Formats that also require wday (needs @jd).
      if @has_jd
        wday = (@jd + 1) % 7
        case format
        when '%c'
          # %c = %a %b %e %H:%M:%S %Y  (always 24 chars for 4-digit year)
          ed = @day < 10 ? " #{@day}" : @day.to_s
          y_str = (y >= 0 && y <= 9999) ? FOUR_DIGIT[y] : (y >= 0 ? sprintf("%04d", y) : sprintf("%05d", y))
          str = "#{ABBR_DAYNAMES[wday]} #{ABBR_MONTHNAMES[@month]} #{ed} 00:00:00 #{y_str}"
          return str.force_encoding(format.encoding)
        when '%A, %B %d, %Y'
          y_str = (y >= 0 && y <= 9999) ? FOUR_DIGIT[y] : (y >= 0 ? sprintf("%04d", y) : sprintf("%05d", y))
          str = "#{DAYNAMES[wday]}, #{MONTHNAMES[@month]} #{TWO_DIGIT[@day]}, #{y_str}"
          return str.force_encoding(format.encoding)
        end
      end
    end

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
  # Uses format.index('%') to scan literal sections in bulk, avoiding
  # per-character String allocation from format[i] indexing.
  def strftime_format(format)
    result = String.new
    pos = 0
    fmt_len = format.length

    # Detect simple Date (no time/offset) with both civil and JD fields cached.
    # Precompute frequently accessed values to bypass the tmx_* method chain.
    if @df.nil? && @sf.nil? && @of.nil? && @nth == 0 && @has_civil && @has_jd
      f_year  = @year
      f_month = @month
      f_day   = @day
      f_wday  = (@jd + 1) % 7
      is_simple = true
    else
      is_simple = false
    end

    while pos < fmt_len
      # Find next '%' starting from current position.
      pct = format.index('%', pos)

      if pct.nil?
        # No more format specs — append remaining literal text as a block.
        result << format[pos..] if pos < fmt_len
        break
      end

      # Append literal text before this '%' as a single block copy.
      result << format[pos, pct - pos] if pct > pos

      i = pct + 1
      if i >= fmt_len
        # Trailing '%' with nothing after — append as literal (matches C behavior).
        result << '%'
        break
      end

      # Parse all modifiers in a flat loop (flags, width, colons, E/O).
      # flags: integer bitmask (FLAG_MINUS | FLAG_SPACE | FLAG_UPPER | FLAG_CHCASE | FLAG_ZERO)
      # width: integer (-1 = not specified)
      flags = 0
      width = -1
      modifier = nil
      colons = 0

      while i < fmt_len
        c = format[i]
        case c
        when 'E', 'O'
          modifier = c
          i += 1
        when ':'
          colons += 1
          i += 1
        when '-'
          flags |= FLAG_MINUS
          i += 1
        when '_'
          flags |= FLAG_SPACE
          i += 1
        when '^'
          flags |= FLAG_UPPER
          i += 1
        when '#'
          flags |= FLAG_CHCASE
          i += 1
        when '0'
          # '0' is a flag only when width is not yet started
          if width == -1
            flags |= FLAG_ZERO
          else
            width = width * 10
          end
          i += 1
        when '1'..'9'
          width = format[i].ord - 48
          i += 1
          # Continue reading remaining digits
          while i < fmt_len
            d = format[i]
            break if d < '0' || d > '9'
            width = width * 10 + (d.ord - 48)
            i += 1
          end
        else
          break
        end
      end

      # Invalid if both E/O and colon modifiers are present.
      if modifier && colons > 0
        if i < fmt_len
          spec = format[i]
          result << "%#{modifier}#{':' * colons}#{spec}"
          i += 1
        end
        pos = i
        next
      end

      # Width specifier overflow check
      if width != -1 && width >= 1024
        raise Errno::ERANGE, "Result too large"
      end

      if i < fmt_len
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
            result << format_spec(spec, flags, width)
          else
            result << "%#{modifier}#{flags_to_s(flags)}#{width == -1 ? '' : width}#{spec}"
          end
        elsif spec == 'z'
          if is_simple && flags == 0 && width == -1 && colons == 0
            # Simple Date: offset is always 0, result is always '+0000'.
            result << '+0000'
          else
            result << format_z(tmx_offset, width, flags, colons)
          end
        elsif colons > 0
          # Colon modifier is only valid for 'z'.
          result << "%#{':' * colons}#{flags_to_s(flags)}#{width == -1 ? '' : width}#{spec}"
        elsif is_simple && flags == 0 && width == -1
          # Fast path: simple Date with no flags or width — bypass tmx_* method chain.
          case spec
          when 'Y'
            raise Errno::ERANGE, "Result too large" if f_year.bit_length > 128
            if f_year >= 0 && f_year <= 9999
              result << FOUR_DIGIT[f_year]
            else
              result << sprintf("%0#{f_year < 0 ? 5 : 4}d", f_year)
            end
          when 'C'
            c = f_year / 100
            result << (c >= 0 && c < 100 ? TWO_DIGIT[c] : sprintf('%02d', c))
          when 'y'
            result << TWO_DIGIT[f_year % 100]
          when 'm'
            result << TWO_DIGIT[f_month]
          when 'd'
            result << TWO_DIGIT[f_day]
          when 'e'
            result << sprintf('%2d', f_day)
          when 'A'
            result << (DAYNAMES[f_wday] || '?')
          when 'a'
            result << (ABBR_DAYNAMES[f_wday] || '?')[0, 3]
          when 'B'
            result << (MONTHNAMES[f_month] || '?')
          when 'b', 'h'
            result << (ABBR_MONTHNAMES[f_month] || '?')[0, 3]
          when 'H', 'M', 'S'
            result << '00'
          when 'I', 'l'
            # hour=0 → h = 0%12 = 0 → h = 12
            result << '12'
          when 'k'
            # sprintf('%2d', 0) = ' 0'
            result << ' 0'
          when 'P'
            result << 'am'  # hour=0 < 12
          when 'p'
            result << 'AM'
          when 'w'
            result << f_wday.to_s
          when 'Z'
            result << '+00:00'
          when '%'
            result << '%'
          when 'n'
            result << "\n"
          when 't'
            result << "\t"
          else
            result << format_spec(spec, flags, width)
          end
        else
          result << format_spec(spec, flags, width)
        end

        i += 1
      end

      pos = i
    end

    result.force_encoding('US-ASCII') if result.ascii_only?

    result
  end

  def flags_to_s(flags)
    return '' if flags == 0
    s = ''.dup
    s << '-' if flags & FLAG_MINUS  != 0
    s << '_' if flags & FLAG_SPACE  != 0
    s << '^' if flags & FLAG_UPPER  != 0
    s << '#' if flags & FLAG_CHCASE != 0
    s << '0' if flags & FLAG_ZERO   != 0
    s
  end

  def format_spec(spec, flags = 0, width = -1)
    # N/L: width controls precision (number of fractional digits)
    if spec == 'N' || spec == 'L'
      precision = if width != -1
                    width
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
    if width != -1
      default_pad = if NUMERIC_SPECS.include?(spec)
                      '0'
                    elsif SPACE_PAD_SPECS.include?(spec)
                      ' '
                    else
                      ' '
                    end
      apply_width(base_result, width, flags, default_pad)
    else
      base_result
    end
  end

  # C: Apply ^ (UPPER) and # (CHCASE) flags
  def apply_case_flags(str, spec, flags)
    if flags & FLAG_UPPER != 0
      str.upcase
    elsif flags & FLAG_CHCASE != 0
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
  def get_base_format(spec, flags = 0)
    case spec
    when 'Y' # 4-digit year
      y = tmx_year
      raise Errno::ERANGE, "Result too large" if y.is_a?(Integer) && y.bit_length > 128
      # C: FMT('0', y >= 0 ? 4 : 5, "ld", y)
      if flags & FLAG_MINUS != 0
        y.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf("%#{y < 0 ? 5 : 4}d", y)
      elsif y >= 0 && y <= 9999
        FOUR_DIGIT[y]
      else
        sprintf("%0#{y < 0 ? 5 : 4}d", y)
      end
    when 'C' # Century
      c = tmx_year / 100
      c >= 0 && c < 100 ? TWO_DIGIT[c] : sprintf('%02d', c)
    when 'y' # Two-digit year
      TWO_DIGIT[tmx_year % 100]
    when 'm' # Month (01-12)
      if flags & FLAG_MINUS != 0
        tmx_mon.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf('%2d', tmx_mon)
      else
        TWO_DIGIT[tmx_mon]
      end
    when 'B' # Full month name
      MONTHNAMES[tmx_mon] || '?'
    when 'b', 'h' # Abbreviated month name
      (ABBR_MONTHNAMES[tmx_mon] || '?')[0, 3]
    when 'd' # Day (01-31)
      if flags & FLAG_MINUS != 0
        tmx_mday.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf('%2d', tmx_mday)
      else
        TWO_DIGIT[tmx_mday]
      end
    when 'e' # Day (1-31) blank filled
      if flags & FLAG_MINUS != 0
        tmx_mday.to_s
      elsif flags & FLAG_ZERO != 0
        TWO_DIGIT[tmx_mday]
      else
        sprintf('%2d', tmx_mday)
      end
    when 'j' # Day of the year (001-366)
      if flags & FLAG_MINUS != 0
        tmx_yday.to_s
      else
        sprintf('%03d', tmx_yday)
      end
    when 'H' # Hour (00-23)
      if flags & FLAG_MINUS != 0
        tmx_hour.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf('%2d', tmx_hour)
      else
        TWO_DIGIT[tmx_hour]
      end
    when 'k' # Hour (0-23) blank-padded
      sprintf('%2d', tmx_hour)
    when 'I' # Hour (01-12)
      h = tmx_hour % 12
      h = 12 if h.zero?
      if flags & FLAG_MINUS != 0
        h.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf('%2d', h)
      else
        TWO_DIGIT[h]
      end
    when 'l' # Hour (1-12) blank filled
      h = tmx_hour % 12
      h = 12 if h.zero?
      sprintf('%2d', h)
    when 'M' # Minutes (00-59)
      if flags & FLAG_MINUS != 0
        tmx_min.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf('%2d', tmx_min)
      else
        TWO_DIGIT[tmx_min]
      end
    when 'S' # Seconds (00-59)
      if flags & FLAG_MINUS != 0
        tmx_sec.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf('%2d', tmx_sec)
      else
        TWO_DIGIT[tmx_sec]
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
      TWO_DIGIT[tmx_wnum0]
    when 'W' # Week number (00-53, Monday start)
      TWO_DIGIT[tmx_wnum1]
    when 'V' # ISO week number (01-53)
      TWO_DIGIT[tmx_cweek]
    when 'G' # ISO week year
      y = tmx_cwyear
      if flags & FLAG_MINUS != 0
        y.to_s
      elsif flags & FLAG_SPACE != 0
        sprintf("%#{y < 0 ? 5 : 4}d", y)
      elsif y >= 0 && y <= 9999
        FOUR_DIGIT[y]
      else
        sprintf("%0#{y < 0 ? 5 : 4}d", y)
      end
    when 'g' # ISO week year (2 digits)
      TWO_DIGIT[tmx_cwyear % 100]
    when 'z' # Time Zone Offset (+0900) — handled by format_z in format_spec
      format_z(tmx_offset, -1, 0, 0)
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
    return str if flags & FLAG_MINUS != 0
    return str if str.length >= width

    # Determine a padding character.
    padding =
      if flags & FLAG_ZERO != 0
        '0'
      elsif flags & FLAG_SPACE != 0
        ' '
      else
        default_pad
      end

    str.rjust(width, padding)
  end

  # C: format %z with width/flags/colons support
  # Matches date_strftime.c case 'z' logic exactly.
  # width: integer (-1 = not specified), flags: integer bitmask
  def format_z(offset, width, flags, colons)
    sign = offset < 0 ? '-' : '+'
    aoff = offset.abs
    hours = aoff / 3600
    minutes = (aoff % 3600) / 60
    seconds = aoff % 60

    hl = hours < 10 ? 1 : 2  # actual digits needed for hours
    hw = 2                     # default hour width
    hw = 1 if flags & FLAG_MINUS != 0 && hl == 1

    precision = width  # -1 means not specified

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
    if flags & FLAG_SPACE != 0 && hp > hl
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
