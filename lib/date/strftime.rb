# frozen_string_literal: true

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
  def strftime(format = DEFAULT_STRFTIME_FMT)
    if format.equal?(DEFAULT_STRFTIME_FMT)
      internal_civil unless @year
      return _fast_ymd.force_encoding(Encoding::US_ASCII)
    end
    fmt = format.to_str
    if fmt == YMD_FMT
      internal_civil unless @year
      return _fast_ymd.force_encoding(Encoding::US_ASCII)
    end
    internal_strftime(fmt).force_encoding(fmt.encoding)
  end

  private

  def internal_strftime(fmt) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
    # Fast path for common format strings (whole-string match)
    case fmt
    when '%Y-%m-%d', '%F'
      internal_civil unless @year
      return _fast_ymd
    when '%H:%M:%S', '%T', '%X'
      return instance_of?(Date) ? +'00:00:00' : "#{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]}"
    when '%m/%d/%y', '%D', '%x'
      internal_civil unless @year
      return "#{PAD2[@month]}/#{PAD2[@day]}/#{PAD2[@year.abs % 100]}"
    when '%Y-%m-%dT%H:%M:%S%z'
      internal_civil unless @year
      if instance_of?(Date)
        return _fast_ymd << 'T00:00:00+0000'
      else
        of = _of_seconds
        sign = of < 0 ? '-' : '+'
        abs = of.abs
        return "#{_fast_ymd}T#{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]}#{sign}#{PAD2[abs / 3600]}#{PAD2[(abs % 3600) / 60]}"
      end
    when '%a %b %e %H:%M:%S %Y', '%c'
      internal_civil unless @year
      return _fmt_asctime_str
    when '%A, %B %d, %Y'
      internal_civil unless @year
      w = (@jd + 1) % 7
      y = @year
      y_s = y >= 1000 ? y.to_s : (y >= 0 ? format('%04d', y) : format('-%04d', -y))
      return "#{DAY_FULL_COMMA[w]}#{MONTH_FULL_SPACE[@month]}#{PAD2[@day]}, #{y_s}"
    end

    result = +''.encode(fmt.encoding)
    i      = 0
    len    = fmt.bytesize

    while i < len
      b = fmt.getbyte(i)

      # Batch collect literal (non-%) characters
      if b != 37  # '%'
        lit_start = i
        i += 1
        i += 1 while i < len && fmt.getbyte(i) != 37
        result << fmt.byteslice(lit_start, i - lit_start)
        next
      end

      i += 1  # skip '%'
      if i >= len
        result << '%'
        break
      end

      # Quick dispatch: if next byte is a simple letter spec (A-Z or a-z,
      # excluding E/O locale modifiers), skip flag/width/prec parsing entirely.
      # Flag chars '-'(45) '_'(95) '0'(48) '^'(94) '#'(35) ':'(58) are all
      # outside A-Z(65-90) and a-z(97-122) ranges.
      b = fmt.getbyte(i)
      if (b >= 65 && b <= 90 && b != 69 && b != 79) || (b >= 97 && b <= 122)
        fast = _fast_spec(b)
        if fast
          result << fast
          i += 1
          next
        end
      end

      # Parse flags (bitmask — no Hash allocation)
      flags = 0
      colons = 0
      loop do
        b = fmt.getbyte(i)
        case b
        when 45 then flags |= FL_LEFT   # '-'
        when 95 then flags |= FL_SPACE  # '_'
        when 48 then flags |= FL_ZERO   # '0'
        when 94 then flags |= FL_UPPER  # '^'
        when 35 then flags |= FL_CHCASE # '#'
        when 58  # ':'
          colons += 1
          i += 1
          redo if fmt.getbyte(i) == 58
          break
        else break
        end
        i += 1
      end

      # Parse width (byte range check — no Regexp)
      width = nil
      b = fmt.getbyte(i)
      if b && b >= 48 && b <= 57  # '0'..'9'
        width = b - 48
        i += 1
        b = fmt.getbyte(i)
        while b && b >= 48 && b <= 57
          width = width * 10 + (b - 48)
          i += 1
          b = fmt.getbyte(i)
        end
        raise Errno::ERANGE, "strftime" if width > STRFTIME_MAX_WIDTH
      end

      # Parse precision (after '.')
      prec = nil
      if fmt.getbyte(i) == 46  # '.'
        i += 1
        prec = 0
        b = fmt.getbyte(i)
        while b && b >= 48 && b <= 57
          prec = prec * 10 + (b - 48)
          i += 1
          b = fmt.getbyte(i)
        end
      end

      # Post-width colons (for %8:z, %11::z etc.)
      while fmt.getbyte(i) == 58  # ':'
        colons += 1
        i += 1
      end

      # Locale modifier (%E or %O)
      locale_mod = nil
      b = fmt.getbyte(i)
      if b == 69 || b == 79  # 'E' or 'O'
        locale_mod = b
        i += 1
      end

      spec = fmt.getbyte(i)
      i += 1

      # Inline fast path: no flags, no width, no prec, no locale mod, no colons
      if flags == 0 && width.nil? && prec.nil? && locale_mod.nil? && colons == 0
        fast = _fast_spec(spec)
        if fast
          result << fast
          next
        end
      end

      result << _format_spec_b(spec, flags, colons, width, prec, locale_mod)
    end

    result
  end

  # Format "%a %b %e %H:%M:%S %Y" directly (used by %c expansion and asctime)
  def _fmt_asctime_str
    w = (@jd + 1) % 7
    d = @day
    d_s = d < 10 ? " #{d}" : d.to_s
    y = @year
    y_s = y >= 1000 ? y.to_s : (y >= 0 ? format('%04d', y) : format('-%04d', -y))
    if instance_of?(Date)
      "#{ASCTIME_PREFIX[w][@month]}#{d_s} 00:00:00 #{y_s}"
    else
      "#{ASCTIME_PREFIX[w][@month]}#{d_s} #{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]} #{y_s}"
    end
  end

  # Inline fast path for common specs with default formatting (no flags/width/prec)
  def _fast_spec(spec) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
    case spec
    when 89  # 'Y'
      internal_civil unless @year
      y = @year
      if y >= 1000
        s = y.to_s
        raise Errno::ERANGE, "strftime" if s.length >= STRFTIME_MAX_COPY_LEN
        s
      elsif y >= 0
        format('%04d', y)
      else
        format('-%04d', -y)
      end
    when 109 # 'm'
      internal_civil unless @year
      PAD2[@month]
    when 100 # 'd'
      internal_civil unless @year
      PAD2[@day]
    when 101 # 'e'
      internal_civil unless @year
      d = @day
      d < 10 ? " #{d}" : d.to_s
    when 72  # 'H'
      PAD2[internal_hour]
    when 77  # 'M'
      PAD2[internal_min]
    when 83  # 'S'
      PAD2[internal_sec]
    when 97  # 'a'
      STRFTIME_DAYS_ABBR[(@jd + 1) % 7]
    when 65  # 'A'
      STRFTIME_DAYS_FULL[(@jd + 1) % 7]
    when 98, 104  # 'b', 'h'
      internal_civil unless @year
      STRFTIME_MONTHS_ABBR[@month]
    when 66  # 'B'
      internal_civil unless @year
      STRFTIME_MONTHS_FULL[@month]
    when 112 # 'p'
      internal_hour < 12 ? 'AM' : 'PM'
    when 80  # 'P'
      internal_hour < 12 ? 'am' : 'pm'
    when 37  # '%'
      '%'
    when 110 # 'n'
      "\n"
    when 116 # 't'
      "\t"
    when 106 # 'j'
      yd = yday
      if yd < 10
        "00#{yd}"
      elsif yd < 100
        "0#{yd}"
      else
        yd.to_s
      end
    when 119 # 'w'
      ((@jd + 1) % 7).to_s
    when 117 # 'u'
      cwday.to_s
    when 121 # 'y'
      internal_civil unless @year
      PAD2[@year.abs % 100]
    when 90  # 'Z'
      _zone_str
    when 122 # 'z'
      of = _of_seconds
      sign = of < 0 ? '-' : '+'
      abs = of.abs
      "#{sign}#{PAD2[abs / 3600]}#{PAD2[(abs % 3600) / 60]}"
    when 115 # 's'
      ((@jd - 2440588) * 86400 - _of_seconds + internal_hour * 3600 + internal_min * 60 + internal_sec).to_s
    # Composite specs — inline expansion
    when 99  # 'c'
      internal_civil unless @year
      _fmt_asctime_str
    when 70  # 'F'
      internal_civil unless @year
      _fast_ymd
    when 84, 88  # 'T', 'X'
      instance_of?(Date) ? '00:00:00' : "#{PAD2[internal_hour]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]}"
    when 68, 120  # 'D', 'x'
      internal_civil unless @year
      "#{PAD2[@month]}/#{PAD2[@day]}/#{PAD2[@year.abs % 100]}"
    when 82  # 'R'
      instance_of?(Date) ? '00:00' : "#{PAD2[internal_hour]}:#{PAD2[internal_min]}"
    when 114  # 'r'
      if instance_of?(Date)
        '12:00:00 AM'
      else
        h = internal_hour % 12
        h = 12 if h == 0
        "#{PAD2[h]}:#{PAD2[internal_min]}:#{PAD2[internal_sec]} #{internal_hour < 12 ? 'AM' : 'PM'}"
      end
    else
      nil  # fall through to _format_spec_b
    end
  end

  # Full spec handling with bitmask flags (called when _fast_spec returns nil or flags/width/prec present)
  def _format_spec_b(spec, flags, colons, width, prec, locale_mod) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
    # Handle %E/%O locale modifiers
    if locale_mod
      valid = locale_mod == 69 ? STRFTIME_E_VALID_BYTES : STRFTIME_O_VALID_BYTES  # 69='E'
      unless valid.include?(spec)
        mod_chr = locale_mod == 69 ? 'E' : 'O'
        return "%#{mod_chr}#{spec&.chr}"
      end
    end

    case spec
    when 89, 71  # 'Y', 'G'
      y = spec == 89 ? year : cwyear
      _fmt_year(y, width, prec, flags)
    when 67  # 'C'
      cent = year.div(100)
      _pad_num(cent, width || 2, flags)
    when 121 # 'y'
      _pad_num(year.abs % 100, width || 2, flags, zero: true)
    when 103 # 'g'
      _pad_num(cwyear.abs % 100, width || 2, flags, zero: true)
    when 109 # 'm'
      _pad_num(month, width || 2, flags, zero: true)
    when 100 # 'd'
      _pad_num(day, width || 2, flags, zero: true)
    when 101 # 'e'
      _pad_num(day, width || 2, flags, zero: false)
    when 106 # 'j'
      _pad_num(yday, width || 3, flags, zero: true)
    when 72  # 'H'
      _pad_num(internal_hour, width || 2, flags, zero: true)
    when 107 # 'k'
      _pad_num(internal_hour, width || 2, flags, zero: false)
    when 73  # 'I'
      h = internal_hour % 12
      h = 12 if h == 0
      _pad_num(h, width || 2, flags, zero: true)
    when 108 # 'l'
      h = internal_hour % 12
      h = 12 if h == 0
      _pad_num(h, width || 2, flags, zero: false)
    when 77  # 'M'
      _pad_num(internal_min, width || 2, flags, zero: true)
    when 83  # 'S'
      _pad_num(internal_sec, width || 2, flags, zero: true)
    when 76  # 'L'
      w = width || 3
      ms = (_sec_frac * (10**w)).floor
      ms.to_s.rjust(w, '0')
    when 78  # 'N'
      w = width || prec || 9
      ns = (_sec_frac * (10**w)).floor
      ns.to_s.rjust(w, '0')
    when 115 # 's'
      unix = (@jd - 2440588) * 86400 - _of_seconds +
             internal_hour * 3600 + internal_min * 60 + internal_sec
      _pad_num(unix, width || 1, flags)
    when 81  # 'Q'
      ms = ((@jd - 2440588) * 86400 - _of_seconds +
            internal_hour * 3600 + internal_min * 60 + internal_sec) * 1000 +
           (_sec_frac * 1000).floor
      _pad_num(ms, width || 1, flags)
    when 65  # 'A'
      _fmt_str(STRFTIME_DAYS_FULL[wday], width, flags)
    when 97  # 'a'
      _fmt_str(STRFTIME_DAYS_ABBR[wday], width, flags)
    when 66  # 'B'
      _fmt_str(STRFTIME_MONTHS_FULL[month], width, flags)
    when 98, 104  # 'b', 'h'
      _fmt_str(STRFTIME_MONTHS_ABBR[month], width, flags)
    when 112 # 'p'
      _fmt_str(internal_hour < 12 ? 'AM' : 'PM', width, flags)
    when 80  # 'P'
      _fmt_str(internal_hour < 12 ? 'am' : 'pm', width, flags)
    when 90  # 'Z'
      _fmt_str(_zone_str, width, flags)
    when 122 # 'z'
      _fmt_z(colons, width, prec, flags)
    when 117 # 'u'
      _pad_num(cwday, width || 1, flags)
    when 119 # 'w'
      _pad_num(wday, width || 1, flags)
    when 85  # 'U'
      _pad_num(_week_number(0), width || 2, flags, zero: true)
    when 87  # 'W'
      _pad_num(_week_number(1), width || 2, flags, zero: true)
    when 86  # 'V'
      _pad_num(cweek, width || 2, flags, zero: true)
    when 37  # '%'
      '%'
    when 43  # '+'
      s = internal_strftime('%a %b %e %H:%M:%S %Z %Y')
      _fmt_str(s, width, flags)
    else
      # Try composite
      expansion = STRFTIME_COMPOSITE_BYTE[spec]
      if expansion
        s = internal_strftime(expansion)
        _fmt_str(s, width, flags)
      else
        "%#{spec&.chr}"
      end
    end
  end

  # Format year (handles negative years, precision, and all flag variants)
  def _fmt_year(y, width, prec, flags)
    if prec
      s = y.abs.to_s.rjust(prec, '0')
      s = (y < 0 ? '-' : '') + s
    elsif flags & FL_LEFT != 0
      s = (y < 0 ? '-' : '') + y.abs.to_s
    else
      default_w = y < 0 ? 5 : 4
      w = width || default_w
      if flags & FL_SPACE != 0
        raw = (y < 0 ? '-' : '') + y.abs.to_s
        s = raw.rjust(w, ' ')
      else
        s = y.abs.to_s.rjust(w - (y < 0 ? 1 : 0), '0')
        s = (y < 0 ? '-' : '') + s
      end
    end
    raise Errno::ERANGE, "strftime" if s.length >= STRFTIME_MAX_COPY_LEN
    if flags & (FL_UPPER | FL_CHCASE) != 0
      s.upcase
    else
      s
    end
  end

  def _pad_num(n, default_w, flags, zero: nil)
    sign = n < 0 ? '-' : ''
    abs  = n.abs.to_s
    w    = default_w

    if flags & FL_LEFT != 0
      sign + abs
    elsif flags & FL_SPACE != 0 || (flags & FL_ZERO == 0 && zero == false)
      sign + abs.rjust(w - sign.length, ' ')
    else
      pad = (flags & FL_ZERO != 0 || zero) ? '0' : ' '
      sign + abs.rjust([w - sign.length, abs.length].max, pad)
    end
  end

  def _fmt_str(s, width, flags)
    s = s.dup
    if flags & FL_CHCASE != 0
      s = (s == s.upcase) ? s.downcase : s.upcase
    elsif flags & FL_UPPER != 0
      s = s.upcase
    end
    if flags & FL_LEFT != 0
      s
    elsif width
      pad = flags & FL_ZERO != 0 ? '0' : ' '
      s.rjust(width, pad)
    else
      s
    end
  end

  # Week number (0=first partial week)
  def _week_number(ws)
    yd   = yday
    wd   = wday  # 0=Sun
    if ws == 1
      # Monday-based
      wd = wd == 0 ? 6 : wd - 1
    end
    (yd - wd + 6).div(7)
  end

  # Format %z with colons variant and GNU extension flag support
  def _fmt_z(colons, width, _prec, flags)
    of   = _of_seconds
    sign = of < 0 ? '-' : '+'
    abs  = of.abs
    hh   = abs / 3600
    mm   = (abs % 3600) / 60
    ss   = abs % 60

    no_lead = flags & (FL_LEFT | FL_SPACE) != 0

    if no_lead
      case colons
      when 0
        s = format('%s%d%02d', sign, hh, mm)
      when 1
        s = format('%s%d:%02d', sign, hh, mm)
      when 2
        s = format('%s%d:%02d:%02d', sign, hh, mm, ss)
      when 3
        if ss != 0
          s = format('%s%d:%02d:%02d', sign, hh, mm, ss)
        elsif mm != 0
          s = format('%s%d:%02d', sign, hh, mm)
        else
          s = format('%s%d', sign, hh)
        end
      else
        s = format('%s%d:%02d', sign, hh, mm)
      end
    else
      case colons
      when 0
        s = format('%s%02d%02d', sign, hh, mm)
      when 1
        s = format('%s%02d:%02d', sign, hh, mm)
      when 2
        s = format('%s%02d:%02d:%02d', sign, hh, mm, ss)
      when 3
        if ss != 0
          s = format('%s%02d:%02d:%02d', sign, hh, mm, ss)
        elsif mm != 0
          s = format('%s%02d:%02d', sign, hh, mm)
        else
          s = format('%s%02d', sign, hh)
        end
      else
        s = format('%s%02d:%02d', sign, hh, mm)
      end
    end

    if width
      if flags & FL_LEFT != 0
        s
      elsif flags & FL_SPACE != 0
        s.rjust(width, ' ')
      else
        digits = s[1..]
        sign + digits.rjust(width - 1, '0')
      end
    else
      s
    end
  end

  # Fast path helper: format '%Y-%m-%d' without allocation overhead
  def _fast_ymd
    y = @year
    suffix = MONTH_DAY_SUFFIX[@month][@day]
    if y >= 1000
      y.to_s << suffix
    elsif y >= 0
      format('%04d', y) << suffix
    else
      format('-%04d', -y) << suffix
    end
  end

  # Helpers for DateTime override
  def internal_hour
    0
  end

  def internal_min
    0
  end

  def internal_sec
    0
  end

  def _sec_frac
    Rational(0)
  end

  def _of_seconds
    0
  end

  def _zone_str
    '+00:00'
  end

end
