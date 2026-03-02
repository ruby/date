# frozen_string_literal: true

class Date
  class << self
    # call-seq:
    #   Date._strptime(string, format = '%F') -> hash
    #
    # Returns a hash of values parsed from +string+
    # according to the given +format+:
    #
    #   Date._strptime('2001-02-03', '%Y-%m-%d') # => {:year=>2001, :mon=>2, :mday=>3}
    #
    # For other formats, see
    # {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc].
    # (Unlike Date.strftime, does not support flags and width.)
    #
    # See also {strptime(3)}[https://man7.org/linux/man-pages/man3/strptime.3.html].
    #
    # Related: Date.strptime (returns a \Date object).
    def _strptime(string, format = '%F')
      string = String === string ? string : string.to_str
      format = String === format ? format : format.to_str
      if format == '%F' || format == '%Y-%m-%d'
        return _strptime_ymd(string)
      end
      if format == '%a %b %d %Y'
        return _strptime_abdy(string)
      end
      hash = {}
      si = _sp_run(string, 0, format, hash)
      return nil if hash.delete(:_fail)
      hash[:leftover] = string[si..] if si < string.length
      if (cent = hash.delete(:_cent))
        hash[:year]   = hash[:year]   + cent * 100 if hash.key?(:year)
        hash[:cwyear] = hash[:cwyear] + cent * 100 if hash.key?(:cwyear)
      end
      if (merid = hash.delete(:_merid))
        hash[:hour] = hash[:hour] % 12 + merid if hash.key?(:hour)
      end
      hash
    end

    # call-seq:
    #   Date.strptime(string = '-4712-01-01', format = '%F', start = Date::ITALY) -> date
    #
    # Returns a new \Date object with values parsed from +string+,
    # according to the given +format+:
    #
    #   Date.strptime('2001-02-03', '%Y-%m-%d')  # => #<Date: 2001-02-03>
    #   Date.strptime('03-02-2001', '%d-%m-%Y')  # => #<Date: 2001-02-03>
    #   Date.strptime('2001-034', '%Y-%j')       # => #<Date: 2001-02-03>
    #   Date.strptime('2001-W05-6', '%G-W%V-%u') # => #<Date: 2001-02-03>
    #   Date.strptime('2001 04 6', '%Y %U %w')   # => #<Date: 2001-02-03>
    #   Date.strptime('2001 05 6', '%Y %W %u')   # => #<Date: 2001-02-03>
    #   Date.strptime('sat3feb01', '%a%d%b%y')   # => #<Date: 2001-02-03>
    #
    # For other formats, see
    # {Formats for Dates and Times}[rdoc-ref:language/strftime_formatting.rdoc].
    # (Unlike Date.strftime, does not support flags and width.)
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    #
    # See also {strptime(3)}[https://man7.org/linux/man-pages/man3/strptime.3.html].
    #
    # Related: Date._strptime (returns a hash).
    def strptime(string = JULIAN_EPOCH_DATE, format = '%F', start = DEFAULT_SG)
      str = String === string ? string : string.to_str
      if format == '%F' || format == '%Y-%m-%d'
        result = _strptime_ymd_to_date(str, start)
        return result if result
        raise Error, 'invalid date'
      end
      if format == '%a %b %d %Y'
        result = _strptime_abdy_to_date(str, start)
        return result if result
        raise Error, 'invalid date'
      end
      hash = _strptime(string, format)
      raise Error, 'invalid date' if hash.nil?
      if !hash.key?(:seconds) && !hash.key?(:leftover) &&
         !hash.key?(:_cent) && !hash.key?(:_merid) &&
         (year = hash[:year]) && (mon = hash[:mon]) && (mday = hash[:mday])
        jd = internal_valid_civil?(year, mon, mday, start)
        raise Error, 'invalid date' if jd.nil?
        return new_from_jd(jd, start)
      end
      _new_by_frags(hash, start)
    end


    private

    # Returns true if the format at position fi starts a numeric conversion spec.
    # All byte-level comparison, no String allocation.
    def _sp_num_p_b?(fmt, fi, flen)
      return false if fi >= flen
      c = fmt.getbyte(fi)
      return true if c >= 48 && c <= 57 # '0'..'9'
      if c == 37 # '%'
        i = fi + 1
        return false if i >= flen
        c2 = fmt.getbyte(i)
        if c2 == 69 || c2 == 79 # 'E' or 'O'
          i += 1
          return false if i >= flen
          c2 = fmt.getbyte(i)
        end
        return STRPTIME_NUMERIC_SPEC_SET[c2]
      end
      false
    end

    # Read up to max_w decimal digits from str starting at si.
    # Returns [value, chars_consumed] or [nil, 0] if no digit found.
    def _sp_digits(str, si, slen, max_w)
      l = 0
      v = 0
      while si + l < slen
        c = str.getbyte(si + l)
        break unless c && c >= 48 && c <= 57 # '0'..'9'
        break if l >= max_w
        v = v * 10 + (c - 48)
        l += 1
      end
      return nil, 0 if l == 0
      return v, l
    end

    # Whitespace byte check (space, tab, newline, carriage return, vertical tab, form feed)
    def _sp_ws?(b)
      b == 32 || b == 9 || b == 10 || b == 13 || b == 11 || b == 12
    end

    # Core scanner: walks format string and string simultaneously.
    # All comparisons use getbyte for zero-allocation byte-level operation.
    # Returns new string index si on success.
    # Sets hash[:_fail]=true and returns -1 on failure.
    def _sp_run(str, si, fmt, hash) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      fi   = 0
      flen = fmt.bytesize
      slen = str.bytesize

      while fi < flen
        ch = fmt.getbyte(fi)

        # Whitespace in format: skip any whitespace in both format and string
        if _sp_ws?(ch)
          while si < slen && _sp_ws?(str.getbyte(si))
            si += 1
          end
          fi += 1
          while fi < flen && _sp_ws?(fmt.getbyte(fi))
            fi += 1
          end
          next
        end

        if ch != 37 # '%'
          if si >= slen
            hash[:_fail] = true
            return -1
          end
          if str.getbyte(si) != ch
            hash[:_fail] = true
            return -1
          end
          si += 1
          fi += 1
          next
        end

        fi += 1 # skip '%'

        # Handle colon modifiers: %:z, %::z, %:::z
        colons = 0
        while fi < flen && fmt.getbyte(fi) == 58 # ':'
          colons += 1
          fi += 1
        end
        if colons > 0
          unless fi < flen && fmt.getbyte(fi) == 122 # 'z'
            hash[:_fail] = true
            return -1
          end
          fi += 1
          new_si = _sp_zone(str, si, slen, hash)
          if new_si < 0
            hash[:_fail] = true
            return -1
          end
          si = new_si
          next
        end

        # Handle E/O locale modifiers
        fb = fi < flen ? fmt.getbyte(fi) : nil
        if fb == 69 || fb == 79 # 'E' or 'O'
          valid_set = fb == 69 ? STRPTIME_E_VALID_SET : STRPTIME_O_VALID_SET
          fb2 = fi + 1 < flen ? fmt.getbyte(fi + 1) : nil
          if fb2 && valid_set[fb2]
            fi += 1 # skip E/O, fall through to handle spec
          else
            # Invalid combo: match '%' literally in string
            if si >= slen || str.getbyte(si) != 37 # '%'
              hash[:_fail] = true
              return -1
            end
            si += 1
            next
          end
        end

        spec = fi < flen ? fmt.getbyte(fi) : nil
        fi += 1

        case spec
        when 65, 97 # 'A', 'a'
          # Weekday name: 3-byte key O(1) lookup
          if si + 2 >= slen
            hash[:_fail] = true
            return -1
          end
          key = ((str.getbyte(si) | 0x20) << 16) | ((str.getbyte(si + 1) | 0x20) << 8) | (str.getbyte(si + 2) | 0x20)
          entry = ABBR_DAY_3KEY[key]
          unless entry
            hash[:_fail] = true
            return -1
          end
          wday_i = entry[0]
          day_full_len = entry[1]
          if si + day_full_len <= slen && _sp_head_match?(str, si, slen, DAY_LOWER_BYTES[wday_i], day_full_len)
            si += day_full_len
          else
            si += 3
          end
          hash[:wday] = wday_i

        when 66, 98, 104 # 'B', 'b', 'h'
          # Month name: 3-byte key O(1) lookup
          if si + 2 >= slen
            hash[:_fail] = true
            return -1
          end
          key = ((str.getbyte(si) | 0x20) << 16) | ((str.getbyte(si + 1) | 0x20) << 8) | (str.getbyte(si + 2) | 0x20)
          entry = ABBR_MONTH_3KEY[key]
          unless entry
            hash[:_fail] = true
            return -1
          end
          mon_i = entry[0]
          mon_full_len = entry[1]
          if si + mon_full_len <= slen && _sp_head_match?(str, si, slen, MONTH_LOWER_BYTES[mon_i], mon_full_len)
            si += mon_full_len
          else
            si += 3
          end
          hash[:mon] = mon_i

        when 67 # 'C'
          # Century: greedy unless next spec is numeric
          w = _sp_num_p_b?(fmt, fi, flen) ? 2 : 10000
          sb = si < slen ? str.getbyte(si) : nil
          if sb == 43 || sb == 45 # '+' or '-'
            sign = sb == 45 ? -1 : 1
            si += 1
          else
            sign = 1
          end
          n, l = _sp_digits(str, si, slen, w)
          if l == 0
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:_cent] = sign * n

        when 99 # 'c'
          new_si = _sp_run(str, si, '%a %b %e %H:%M:%S %Y', hash)
          return new_si if new_si < 0
          si = new_si

        when 68 # 'D'
          new_si = _sp_run(str, si, '%m/%d/%y', hash)
          return new_si if new_si < 0
          si = new_si

        when 100, 101 # 'd', 'e'
          # Day of month (leading space allowed for single-digit) - inlined
          if si < slen && str.getbyte(si) == 32 # ' '
            si += 1
            b = si < slen ? str.getbyte(si) : nil
            unless b && b >= 48 && b <= 57
              hash[:_fail] = true
              return -1
            end
            n = b - 48
            si += 1
          else
            b = si < slen ? str.getbyte(si) : nil
            unless b && b >= 48 && b <= 57
              hash[:_fail] = true
              return -1
            end
            n = b - 48
            si += 1
            b = si < slen ? str.getbyte(si) : nil
            if b && b >= 48 && b <= 57
              n = n * 10 + (b - 48)
              si += 1
            end
          end
          if n < 1 || n > 31
            hash[:_fail] = true
            return -1
          end
          hash[:mday] = n

        when 70 # 'F'
          new_si = _sp_run(str, si, '%Y-%m-%d', hash)
          return new_si if new_si < 0
          si = new_si

        when 71 # 'G'
          # ISO week-based year: greedy unless next spec is numeric
          sb = si < slen ? str.getbyte(si) : nil
          if sb == 43 || sb == 45 # '+' or '-'
            sign = sb == 45 ? -1 : 1
            si += 1
          else
            sign = 1
          end
          w = _sp_num_p_b?(fmt, fi, flen) ? 4 : 10000
          n, l = _sp_digits(str, si, slen, w)
          if l == 0
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:cwyear] = sign * n

        when 103 # 'g'
          # 2-digit ISO week year
          n, l = _sp_digits(str, si, slen, 2)
          if l == 0 || n > 99
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:cwyear] = n
          hash[:_cent] ||= n >= 69 ? 19 : 20

        when 72, 107 # 'H', 'k'
          # 24-hour clock (leading space allowed) - inlined
          if si < slen && str.getbyte(si) == 32 # ' '
            si += 1
            b = si < slen ? str.getbyte(si) : nil
            unless b && b >= 48 && b <= 57
              hash[:_fail] = true
              return -1
            end
            n = b - 48
            si += 1
          else
            b = si < slen ? str.getbyte(si) : nil
            unless b && b >= 48 && b <= 57
              hash[:_fail] = true
              return -1
            end
            n = b - 48
            si += 1
            b = si < slen ? str.getbyte(si) : nil
            if b && b >= 48 && b <= 57
              n = n * 10 + (b - 48)
              si += 1
            end
          end
          if n > 24
            hash[:_fail] = true
            return -1
          end
          hash[:hour] = n

        when 73, 108 # 'I', 'l'
          # 12-hour clock (leading space allowed) - inlined
          if si < slen && str.getbyte(si) == 32 # ' '
            si += 1
            b = si < slen ? str.getbyte(si) : nil
            unless b && b >= 48 && b <= 57
              hash[:_fail] = true
              return -1
            end
            n = b - 48
            si += 1
          else
            b = si < slen ? str.getbyte(si) : nil
            unless b && b >= 48 && b <= 57
              hash[:_fail] = true
              return -1
            end
            n = b - 48
            si += 1
            b = si < slen ? str.getbyte(si) : nil
            if b && b >= 48 && b <= 57
              n = n * 10 + (b - 48)
              si += 1
            end
          end
          if n < 1 || n > 12
            hash[:_fail] = true
            return -1
          end
          hash[:hour] = n

        when 106 # 'j'
          # Day of year (3-digit)
          n, l = _sp_digits(str, si, slen, 3)
          if l == 0 || n < 1 || n > 366
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:yday] = n

        when 76 # 'L'
          # Milliseconds: greedy unless next spec is numeric
          sb = si < slen ? str.getbyte(si) : nil
          if sb == 43 || sb == 45 # '+' or '-'
            sign = sb == 45 ? -1 : 1
            si += 1
          else
            sign = 1
          end
          osi = si
          w = _sp_num_p_b?(fmt, fi, flen) ? 3 : 10000
          n, l = _sp_digits(str, si, slen, w)
          if l == 0
            hash[:_fail] = true
            return -1
          end
          si += l
          n = -n if sign == -1
          hash[:sec_fraction] = Rational(n, 10**(si - osi))

        when 77 # 'M'
          # Minute - inlined
          b = si < slen ? str.getbyte(si) : nil
          unless b && b >= 48 && b <= 57
            hash[:_fail] = true
            return -1
          end
          n = b - 48
          si += 1
          b = si < slen ? str.getbyte(si) : nil
          if b && b >= 48 && b <= 57
            n = n * 10 + (b - 48)
            si += 1
          end
          if n > 59
            hash[:_fail] = true
            return -1
          end
          hash[:min] = n

        when 109 # 'm'
          # Month - inlined
          b = si < slen ? str.getbyte(si) : nil
          unless b && b >= 48 && b <= 57
            hash[:_fail] = true
            return -1
          end
          n = b - 48
          si += 1
          b = si < slen ? str.getbyte(si) : nil
          if b && b >= 48 && b <= 57
            n = n * 10 + (b - 48)
            si += 1
          end
          if n < 1 || n > 12
            hash[:_fail] = true
            return -1
          end
          hash[:mon] = n

        when 78 # 'N'
          # Nanoseconds (or sub-second fraction): greedy unless next spec is numeric
          sb = si < slen ? str.getbyte(si) : nil
          if sb == 43 || sb == 45 # '+' or '-'
            sign = sb == 45 ? -1 : 1
            si += 1
          else
            sign = 1
          end
          osi = si
          w = _sp_num_p_b?(fmt, fi, flen) ? 9 : 10000
          n, l = _sp_digits(str, si, slen, w)
          if l == 0
            hash[:_fail] = true
            return -1
          end
          si += l
          n = -n if sign == -1
          hash[:sec_fraction] = Rational(n, 10**(si - osi))

        when 110, 116 # 'n', 't'
          # Match any whitespace
          new_si = _sp_run(str, si, ' ', hash)
          return new_si if new_si < 0
          si = new_si

        when 80, 112 # 'P', 'p'
          # AM/PM with optional dot notation (A.M./P.M.)
          if si >= slen
            hash[:_fail] = true
            return -1
          end
          c0 = str.getbyte(si)
          if c0 == 80 || c0 == 112 # 'P' or 'p'
            merid = 12
          elsif c0 == 65 || c0 == 97 # 'A' or 'a'
            merid = 0
          else
            hash[:_fail] = true
            return -1
          end
          if si + 1 < slen && str.getbyte(si + 1) == 46 # '.'
            # Dot notation: X.M.
            if si + 3 >= slen || str.getbyte(si + 3) != 46 # '.'
              hash[:_fail] = true
              return -1
            end
            c_m = str.getbyte(si + 2)
            unless c_m == 77 || c_m == 109 # 'M' or 'm'
              hash[:_fail] = true
              return -1
            end
            si += 4
          else
            if si + 1 >= slen
              hash[:_fail] = true
              return -1
            end
            c_m = str.getbyte(si + 1)
            unless c_m == 77 || c_m == 109 # 'M' or 'm'
              hash[:_fail] = true
              return -1
            end
            si += 2
          end
          hash[:_merid] = merid

        when 81 # 'Q'
          # Milliseconds since Unix epoch
          sign = 1
          if si < slen && str.getbyte(si) == 45 # '-'
            sign = -1
            si += 1
          end
          n, l = _sp_digits(str, si, slen, 10000)
          if l == 0
            hash[:_fail] = true
            return -1
          end
          si += l
          n = -n if sign == -1
          hash[:seconds] = Rational(n, 1000)

        when 82 # 'R'
          new_si = _sp_run(str, si, '%H:%M', hash)
          return new_si if new_si < 0
          si = new_si

        when 114 # 'r'
          new_si = _sp_run(str, si, '%I:%M:%S %p', hash)
          return new_si if new_si < 0
          si = new_si

        when 83 # 'S'
          # Second (0-60 to allow leap second) - inlined
          b = si < slen ? str.getbyte(si) : nil
          unless b && b >= 48 && b <= 57
            hash[:_fail] = true
            return -1
          end
          n = b - 48
          si += 1
          b = si < slen ? str.getbyte(si) : nil
          if b && b >= 48 && b <= 57
            n = n * 10 + (b - 48)
            si += 1
          end
          if n > 60
            hash[:_fail] = true
            return -1
          end
          hash[:sec] = n

        when 115 # 's'
          # Seconds since Unix epoch
          sign = 1
          if si < slen && str.getbyte(si) == 45 # '-'
            sign = -1
            si += 1
          end
          n, l = _sp_digits(str, si, slen, 10000)
          if l == 0
            hash[:_fail] = true
            return -1
          end
          si += l
          n = -n if sign == -1
          hash[:seconds] = n

        when 84 # 'T'
          new_si = _sp_run(str, si, '%H:%M:%S', hash)
          return new_si if new_si < 0
          si = new_si

        when 85 # 'U'
          # Week number (Sunday-based)
          n, l = _sp_digits(str, si, slen, 2)
          if l == 0 || n > 53
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:wnum0] = n

        when 117 # 'u'
          # ISO weekday (1=Mon..7=Sun)
          n, l = _sp_digits(str, si, slen, 1)
          if l == 0 || n < 1 || n > 7
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:cwday] = n

        when 86 # 'V'
          # ISO week number
          n, l = _sp_digits(str, si, slen, 2)
          if l == 0 || n < 1 || n > 53
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:cweek] = n

        when 118 # 'v'
          new_si = _sp_run(str, si, '%e-%b-%Y', hash)
          return new_si if new_si < 0
          si = new_si

        when 87 # 'W'
          # Week number (Monday-based)
          n, l = _sp_digits(str, si, slen, 2)
          if l == 0 || n > 53
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:wnum1] = n

        when 119 # 'w'
          # Weekday (0=Sun..6=Sat)
          n, l = _sp_digits(str, si, slen, 1)
          if l == 0 || n > 6
            hash[:_fail] = true
            return -1
          end
          si += l
          hash[:wday] = n

        when 88 # 'X'
          new_si = _sp_run(str, si, '%H:%M:%S', hash)
          return new_si if new_si < 0
          si = new_si

        when 120 # 'x'
          new_si = _sp_run(str, si, '%m/%d/%y', hash)
          return new_si if new_si < 0
          si = new_si

        when 89 # 'Y'
          # Full year: greedy unless next spec is numeric - inlined
          sb = si < slen ? str.getbyte(si) : nil
          if sb == 43 || sb == 45 # '+' or '-'
            sign = sb == 45 ? -1 : 1
            si += 1
          else
            sign = 1
          end
          w = _sp_num_p_b?(fmt, fi, flen) ? 4 : 10000
          b = si < slen ? str.getbyte(si) : nil
          unless b && b >= 48 && b <= 57
            hash[:_fail] = true
            return -1
          end
          n = b - 48
          si += 1
          l = 1
          while l < w && si < slen
            b = str.getbyte(si)
            break unless b && b >= 48 && b <= 57
            n = n * 10 + (b - 48)
            si += 1
            l += 1
          end
          hash[:year] = sign * n

        when 121 # 'y'
          # 2-digit year - inlined
          b = si < slen ? str.getbyte(si) : nil
          unless b && b >= 48 && b <= 57
            hash[:_fail] = true
            return -1
          end
          n = b - 48
          si += 1
          b = si < slen ? str.getbyte(si) : nil
          if b && b >= 48 && b <= 57
            n = n * 10 + (b - 48)
            si += 1
          end
          if n > 99
            hash[:_fail] = true
            return -1
          end
          hash[:year] = n
          hash[:_cent] ||= n >= 69 ? 19 : 20

        when 90, 122 # 'Z', 'z'
          new_si = _sp_zone(str, si, slen, hash)
          if new_si < 0
            hash[:_fail] = true
            return -1
          end
          si = new_si

        when 37 # '%'
          if si >= slen || str.getbyte(si) != 37
            hash[:_fail] = true
            return -1
          end
          si += 1

        when 43 # '+'
          new_si = _sp_run(str, si, '%a %b %e %H:%M:%S %Z %Y', hash)
          return new_si if new_si < 0
          si = new_si

        else
          # Unknown spec: match '%' then spec literally
          if si >= slen || str.getbyte(si) != 37 # '%'
            hash[:_fail] = true
            return -1
          end
          si += 1
          if spec
            if si >= slen || str.getbyte(si) != spec
              hash[:_fail] = true
              return -1
            end
            si += 1
          end
        end
      end

      si
    end

    # Case-insensitive byte-level head match.
    # Compares str[si..si+len-1] against pre-computed lowercase byte array.
    # Uses | 0x20 for ASCII alpha downcase (works for A-Z only).
    def _sp_head_match?(str, si, slen, lower_bytes, len)
      return false if si + len > slen
      i = 0
      while i < len
        return false if (str.getbyte(si + i) | 0x20) != lower_bytes[i]
        i += 1
      end
      true
    end

    # Fast path for %Y-%m-%d / %F format.
    # For common "YYYY-MM-DD" format, uses byteslice+to_i (fewer method calls).
    # Falls back to getbyte loop for non-standard lengths or signed years.
    def _strptime_ymd(str) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      slen = str.bytesize

      # Fast path for "YYYY-MM-DD" (exactly 10 chars) or "YYYY-MM-DD..."
      if slen >= 10 && str.getbyte(4) == 45 && str.getbyte(7) == 45
        b0 = str.getbyte(0)
        if b0 >= 48 && b0 <= 57 # first char is digit (positive 4-digit year)
          year = str.byteslice(0, 4).to_i
          mon  = str.byteslice(5, 2).to_i
          mday = str.byteslice(8, 2).to_i
          return nil if mon < 1 || mon > 12 || mday < 1 || mday > 31
          hash = { year: year, mon: mon, mday: mday }
          hash[:leftover] = str.byteslice(10, slen - 10) if slen > 10
          return hash
        end
      end

      # General path for signed years, short years, etc.
      si = 0
      sign = 1
      b = str.getbyte(si)
      if b == 43 # '+'
        si += 1
        b = str.getbyte(si)
      elsif b == 45 # '-'
        sign = -1
        si += 1
        b = str.getbyte(si)
      end
      return nil unless b && b >= 48 && b <= 57
      year = b - 48
      si += 1
      while si < slen
        b = str.getbyte(si)
        break unless b && b >= 48 && b <= 57
        year = year * 10 + (b - 48)
        si += 1
      end
      year = -year if sign == -1

      return nil unless si < slen && str.getbyte(si) == 45
      si += 1
      b = str.getbyte(si)
      return nil unless b && b >= 48 && b <= 57
      mon = b - 48
      si += 1
      b = str.getbyte(si)
      if b && b >= 48 && b <= 57
        mon = mon * 10 + (b - 48)
        si += 1
      end
      return nil if mon < 1 || mon > 12

      return nil unless si < slen && str.getbyte(si) == 45
      si += 1
      b = str.getbyte(si)
      return nil unless b && b >= 48 && b <= 57
      mday = b - 48
      si += 1
      b = str.getbyte(si)
      if b && b >= 48 && b <= 57
        mday = mday * 10 + (b - 48)
        si += 1
      end
      return nil if mday < 1 || mday > 31

      hash = { year: year, mon: mon, mday: mday }
      hash[:leftover] = str.byteslice(si, slen - si) if si < slen
      hash
    end

    # Ultra-fast path: parse %Y-%m-%d and directly create Date object.
    # Skips Hash creation, _sp_complete_frags, and _sp_valid_date_frags_p entirely.
    # Returns Date object on success, nil on failure.
    def _strptime_ymd_to_date(str, sg) # rubocop:disable Metrics/MethodLength
      slen = str.bytesize

      # Ultra-fast path for exactly "YYYY-MM-DD" (10 chars, positive 4-digit year)
      if slen == 10 && str.getbyte(4) == 45 && str.getbyte(7) == 45
        b0 = str.getbyte(0)
        if b0 >= 48 && b0 <= 57
          year = str.byteslice(0, 4).to_i
          mon  = str.byteslice(5, 2).to_i
          mday = str.byteslice(8, 2).to_i
          if mon >= 1 && mon <= 12 && mday >= 1 && mday <= 31
            # Inline civil validation + JD
            if sg != Float::INFINITY
              dim = DAYS_IN_MONTH_GREGORIAN[mon]
              if mon == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)
                dim = 29
              end
              return nil if mday > dim
              gy = mon <= 2 ? year - 1 : year
              gjd_base = (1461 * (gy + 4716)) / 4 + GJD_MONTH_OFFSET[mon] + mday
              a = gy / 100
              gjd = gjd_base - 1524 + 2 - a + a / 4
              jd = gjd >= sg ? gjd : gjd_base - 1524
              return new_from_jd(jd, sg)
            else
              jd = internal_valid_civil?(year, mon, mday, sg)
              return jd ? new_from_jd(jd, sg) : nil
            end
          end
          return nil
        end
      end

      # General path for signed years, non-standard lengths
      si = 0
      sign = 1
      b = str.getbyte(si)
      if b == 43 # '+'
        si += 1
        b = str.getbyte(si)
      elsif b == 45 # '-'
        sign = -1
        si += 1
        b = str.getbyte(si)
      end
      return nil unless b && b >= 48 && b <= 57
      year = b - 48
      si += 1
      while si < slen
        b = str.getbyte(si)
        break unless b && b >= 48 && b <= 57
        year = year * 10 + (b - 48)
        si += 1
      end
      year = -year if sign == -1
      return nil unless si < slen && str.getbyte(si) == 45
      si += 1
      b = str.getbyte(si)
      return nil unless b && b >= 48 && b <= 57
      mon = b - 48
      si += 1
      b = str.getbyte(si)
      if b && b >= 48 && b <= 57
        mon = mon * 10 + (b - 48)
        si += 1
      end
      return nil if mon < 1 || mon > 12
      return nil unless si < slen && str.getbyte(si) == 45
      si += 1
      b = str.getbyte(si)
      return nil unless b && b >= 48 && b <= 57
      mday = b - 48
      si += 1
      b = str.getbyte(si)
      if b && b >= 48 && b <= 57
        mday = mday * 10 + (b - 48)
        si += 1
      end
      return nil if mday < 1 || mday > 31
      return nil if si < slen

      # Inline civil validation + JD computation
      # For common Gregorian dates with valid day-of-month, compute JD directly
      if sg != Float::INFINITY # Gregorian path (most common)
        dim = DAYS_IN_MONTH_GREGORIAN[mon]
        if mon == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)
          dim = 29
        end
        return nil if mday > dim
        # Inline civil_to_jd for Gregorian
        gy = mon <= 2 ? year - 1 : year
        offset = GJD_MONTH_OFFSET[mon]
        gjd_base = (1461 * (gy + 4716)) / 4 + offset + mday
        a = gy / 100
        gjd = gjd_base - 1524 + 2 - a + a / 4
        jd = gjd >= sg ? gjd : gjd_base - 1524
      else
        jd = internal_valid_civil?(year, mon, mday, sg)
        return nil unless jd
      end
      new_from_jd(jd, sg)
    end

    # Fast path for "%a %b %d %Y" format (complex benchmark).
    # Byte-level name matching + digit parsing. Zero String allocation.
    def _strptime_abdy(str) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      slen = str.bytesize
      si = 0

      # Match weekday name using 3-byte key lookup
      return nil if si + 2 >= slen
      key = ((str.getbyte(si) | 0x20) << 16) | ((str.getbyte(si + 1) | 0x20) << 8) | (str.getbyte(si + 2) | 0x20)
      entry = ABBR_DAY_3KEY[key]
      return nil unless entry
      wday = entry[0]
      full_len = entry[1]
      if si + full_len <= slen && _sp_head_match?(str, si, slen, DAY_LOWER_BYTES[wday], full_len)
        si += full_len
      else
        si += 3
      end

      # Expect space(s)
      return nil if si >= slen || str.getbyte(si) != 32
      si += 1
      si += 1 while si < slen && str.getbyte(si) == 32

      # Match month name using 3-byte key lookup
      return nil if si + 2 >= slen
      key = ((str.getbyte(si) | 0x20) << 16) | ((str.getbyte(si + 1) | 0x20) << 8) | (str.getbyte(si + 2) | 0x20)
      entry = ABBR_MONTH_3KEY[key]
      return nil unless entry
      mon = entry[0]
      full_len = entry[1]
      if si + full_len <= slen && _sp_head_match?(str, si, slen, MONTH_LOWER_BYTES[mon], full_len)
        si += full_len
      else
        si += 3
      end

      # Expect space(s)
      return nil if si >= slen || str.getbyte(si) != 32
      si += 1
      si += 1 while si < slen && str.getbyte(si) == 32

      # Parse day (1-2 digits)
      b = str.getbyte(si)
      return nil unless b && b >= 48 && b <= 57
      mday = b - 48
      si += 1
      b = str.getbyte(si)
      if b && b >= 48 && b <= 57
        mday = mday * 10 + (b - 48)
        si += 1
      end
      return nil if mday < 1 || mday > 31

      # Expect space(s)
      return nil if si >= slen || str.getbyte(si) != 32
      si += 1
      si += 1 while si < slen && str.getbyte(si) == 32

      # Parse year: optional sign + greedy digits
      sign = 1
      b = str.getbyte(si)
      if b == 43 # '+'
        si += 1
        b = str.getbyte(si)
      elsif b == 45 # '-'
        sign = -1
        si += 1
        b = str.getbyte(si)
      end

      return nil unless b && b >= 48 && b <= 57
      year = b - 48
      si += 1
      while si < slen
        b = str.getbyte(si)
        break unless b && b >= 48 && b <= 57
        year = year * 10 + (b - 48)
        si += 1
      end
      year = -year if sign == -1

      hash = { year: year, mon: mon, mday: mday, wday: wday }
      hash[:leftover] = str.byteslice(si, slen - si) if si < slen
      hash
    end

    # Ultra-fast path: parse "%a %b %d %Y" and directly create Date object.
    # Combines parsing + civil validation + JD computation without Hash.
    def _strptime_abdy_to_date(str, sg) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      slen = str.bytesize
      si = 0

      # Match weekday name using 3-byte key lookup
      return nil if si + 2 >= slen
      key = ((str.getbyte(si) | 0x20) << 16) | ((str.getbyte(si + 1) | 0x20) << 8) | (str.getbyte(si + 2) | 0x20)
      entry = ABBR_DAY_3KEY[key]
      return nil unless entry
      full_len = entry[1]
      # Try full name first, then abbreviation
      if si + full_len <= slen && _sp_head_match?(str, si, slen, DAY_LOWER_BYTES[entry[0]], full_len)
        si += full_len
      else
        si += 3
      end

      # Expect space(s)
      return nil if si >= slen || str.getbyte(si) != 32
      si += 1
      si += 1 while si < slen && str.getbyte(si) == 32

      # Match month name using 3-byte key lookup
      return nil if si + 2 >= slen
      key = ((str.getbyte(si) | 0x20) << 16) | ((str.getbyte(si + 1) | 0x20) << 8) | (str.getbyte(si + 2) | 0x20)
      entry = ABBR_MONTH_3KEY[key]
      return nil unless entry
      mon = entry[0]
      full_len = entry[1]
      if si + full_len <= slen && _sp_head_match?(str, si, slen, MONTH_LOWER_BYTES[mon], full_len)
        si += full_len
      else
        si += 3
      end

      # Expect space(s)
      return nil if si >= slen || str.getbyte(si) != 32
      si += 1
      si += 1 while si < slen && str.getbyte(si) == 32

      # Parse day (1-2 digits)
      b = str.getbyte(si)
      return nil unless b && b >= 48 && b <= 57
      mday = b - 48
      si += 1
      b = str.getbyte(si)
      if b && b >= 48 && b <= 57
        mday = mday * 10 + (b - 48)
        si += 1
      end
      return nil if mday < 1 || mday > 31

      # Expect space(s)
      return nil if si >= slen || str.getbyte(si) != 32
      si += 1
      si += 1 while si < slen && str.getbyte(si) == 32

      # Parse year: optional sign + greedy digits
      sign = 1
      b = str.getbyte(si)
      if b == 43 # '+'
        si += 1
        b = str.getbyte(si)
      elsif b == 45 # '-'
        sign = -1
        si += 1
        b = str.getbyte(si)
      end
      return nil unless b && b >= 48 && b <= 57
      year = b - 48
      si += 1
      while si < slen
        b = str.getbyte(si)
        break unless b && b >= 48 && b <= 57
        year = year * 10 + (b - 48)
        si += 1
      end
      year = -year if sign == -1

      # Must consume entire string
      return nil if si < slen

      # Inline civil validation + JD computation
      if sg != Float::INFINITY
        dim = DAYS_IN_MONTH_GREGORIAN[mon]
        if mon == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)
          dim = 29
        end
        return nil if mday > dim
        gy = mon <= 2 ? year - 1 : year
        offset = GJD_MONTH_OFFSET[mon]
        gjd_base = (1461 * (gy + 4716)) / 4 + offset + mday
        a = gy / 100
        gjd = gjd_base - 1524 + 2 - a + a / 4
        jd = gjd >= sg ? gjd : gjd_base - 1524
      else
        jd = internal_valid_civil?(year, mon, mday, sg)
        return nil unless jd
      end
      new_from_jd(jd, sg)
    end

    # Parse zone from string at position si; update hash[:zone] and hash[:offset].
    # Returns new si on success, -1 on failure.
    def _sp_zone(str, si, slen, hash)
      m = STRPTIME_ZONE_PAT.match(str[si..])
      return -1 unless m
      zone_str = m[1]
      hash[:zone]   = zone_str
      hash[:offset] = _sp_zone_to_diff(zone_str)
      si + m[0].length
    end

    # Convert a zone string to seconds offset from UTC.
    # Returns Integer (seconds) or Rational, or nil if unparseable.
    # Mirrors date_zone_to_diff() in ext/date/date_parse.c.
    def _sp_zone_to_diff(zone_str) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      # Fast path for common numeric zones
      len = zone_str.length
      b0 = zone_str.getbyte(0)
      if b0 == 43 || b0 == 45 # '+' or '-'
        sign = b0 == 45 ? -1 : 1
        if len == 6 && zone_str.getbyte(3) == 58 # +HH:MM
          b1 = zone_str.getbyte(1)
          b2 = zone_str.getbyte(2)
          b4 = zone_str.getbyte(4)
          b5 = zone_str.getbyte(5)
          if b1 >= 48 && b1 <= 57 && b2 >= 48 && b2 <= 57 && b4 >= 48 && b4 <= 57 && b5 >= 48 && b5 <= 57
            h = (b1 - 48) * 10 + (b2 - 48)
            m = (b4 - 48) * 10 + (b5 - 48)
            return nil if h > 23 || m > 59
            return sign * (h * 3600 + m * 60)
          end
        elsif len == 5 # +HHMM
          b1 = zone_str.getbyte(1)
          b2 = zone_str.getbyte(2)
          b3 = zone_str.getbyte(3)
          b4 = zone_str.getbyte(4)
          if b1 >= 48 && b1 <= 57 && b2 >= 48 && b2 <= 57 && b3 >= 48 && b3 <= 57 && b4 >= 48 && b4 <= 57
            return sign * ((b1 - 48) * 36000 + (b2 - 48) * 3600 + (b3 - 48) * 600 + (b4 - 48) * 60)
          end
        end
      elsif len == 1 && (b0 == 90 || b0 == 122) # Z/z
        return 0
      elsif len <= 3
        off = ZONE_TABLE[zone_str.downcase]
        return off if off
      end

      s   = zone_str.dup
      dst = false

      # Strip trailing " time" (optionally preceded by "standard" or "daylight")
      strip_word = lambda do |str, len, word|
        n = word.length
        return nil unless len > n
        return nil unless str[len - n - 1] =~ /[[:space:]]/
        return nil unless str[len - n, n].casecmp(word) == 0
        n += 1
        n += 1 while len > n && str[len - n - 1] =~ /[[:space:]]/
        n
      end

      l = s.length
      if (w = strip_word.call(s, l, 'time'))
        l -= w
        if (w2 = strip_word.call(s, l, 'standard'))
          l -= w2
        elsif (w2 = strip_word.call(s, l, 'daylight'))
          l -= w2
          dst = true
        else
          l += w # revert
        end
      elsif (w = strip_word.call(s, l, 'dst'))
        l -= w
        dst = true
      end

      shrunk = s[0, l].gsub(/[[:space:]]+/, ' ').strip
      if (offset = ZONE_TABLE[shrunk.downcase])
        return dst ? offset + 3600 : offset
      end

      # Numeric parsing
      t = s[0, l].strip
      t = t[3..] if t =~ /\Agmt/i
      t = t[$&.length..] if t =~ /\Autc?/i
      return nil unless t && t.length > 0 && (t[0] == '+' || t[0] == '-')

      sign = t[0] == '-' ? -1 : 1
      t    = t[1..]

      if (m = t.match(/\A(\d+):(\d+)(?::(\d+))?\z/))
        h  = m[1].to_i
        mn = m[2].to_i
        sc = m[3] ? m[3].to_i : 0
        return nil if h > 23 || mn > 59 || sc > 59
        sign * (h * 3600 + mn * 60 + sc)
      elsif (m = t.match(/\A(\d+)[,.](\d*)/))
        h = m[1].to_i
        return nil if h > 23
        frac_s = m[2]
        n      = [frac_s.length, 7].min
        digits = frac_s[0, n].to_i
        digits += 1 if frac_s.length > n && frac_s[n].to_i >= 5
        sec = digits * 36
        os  = if n == 0
                h * 3600
              elsif n == 1
                sec * 10 + h * 3600
              elsif n == 2
                sec + h * 3600
              else
                denom = 10**(n - 2)
                r     = Rational(sec, denom) + h * 3600
                r.denominator == 1 ? r.numerator : r
              end
        sign == -1 ? -os : os
      elsif t =~ /\A(\d+)\z/
        digits = $1
        dlen   = digits.length
        h      = digits[0, 2 - dlen % 2].to_i
        mn     = dlen >= 3 ? digits[2 - dlen % 2, 2].to_i : 0
        sc     = dlen >= 5 ? digits[4 - dlen % 2, 2].to_i : 0
        sign * (h * 3600 + mn * 60 + sc)
      else
        nil
      end
    end

    # Rewrite :seconds (from %s/%Q) into jd + time components.
    # Offset is applied first (converts UTC epoch to local time).
    def _sp_rewrite_frags(hash)
      seconds = hash.delete(:seconds)
      return hash unless seconds

      offset  = hash[:offset] || 0
      seconds = seconds + offset if offset != 0

      d,  fr = seconds.divmod(86400)
      h,  fr = fr.divmod(3600)
      m,  fr = fr.divmod(60)
      s,  fr = fr.divmod(1)

      hash[:jd]           = 2440588 + d
      hash[:hour]         = h
      hash[:min]          = m
      hash[:sec]          = s
      hash[:sec_fraction] = fr
      hash
    end

    # Complete partial date fragments by filling defaults from today's date.
    # Mirrors rt_complete_frags() in C.
    def _sp_complete_frags(klass, hash) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      # Fast path: detect :civil case (most common) without iterating all entries
      k = nil
      a = nil
      if hash.key?(:year) || hash.key?(:mon) || hash.key?(:mday)
        civil_n = 0
        civil_n += 1 if hash.key?(:year)
        civil_n += 1 if hash.key?(:mon)
        civil_n += 1 if hash.key?(:mday)
        civil_n += 1 if hash.key?(:hour)
        civil_n += 1 if hash.key?(:min)
        civil_n += 1 if hash.key?(:sec)
        # Check if any other pattern matches better
        best_n = civil_n
        skip_civil = false
        if hash.key?(:jd) # jd entry has 1 element
          skip_civil = true if 1 > best_n
        end
        if hash.key?(:yday) # ordinal [:year, :yday, :hour, :min, :sec]
          ord_n = (hash.key?(:year) ? 1 : 0) + 1 + (hash.key?(:hour) ? 1 : 0) + (hash.key?(:min) ? 1 : 0) + (hash.key?(:sec) ? 1 : 0)
          skip_civil = true if ord_n > best_n
        end
        if hash.key?(:cwyear) || hash.key?(:cweek) || hash.key?(:cwday)
          com_n = (hash.key?(:cwyear) ? 1 : 0) + (hash.key?(:cweek) ? 1 : 0) + (hash.key?(:cwday) ? 1 : 0) + (hash.key?(:hour) ? 1 : 0) + (hash.key?(:min) ? 1 : 0) + (hash.key?(:sec) ? 1 : 0)
          skip_civil = true if com_n > best_n
        end
        if hash.key?(:wnum0)
          wn0_n = (hash.key?(:year) ? 1 : 0) + 1 + (hash.key?(:wday) ? 1 : 0) + (hash.key?(:hour) ? 1 : 0) + (hash.key?(:min) ? 1 : 0) + (hash.key?(:sec) ? 1 : 0)
          skip_civil = true if wn0_n > best_n
        end
        if hash.key?(:wnum1)
          wn1_n = (hash.key?(:year) ? 1 : 0) + 1 + (hash.key?(:wday) ? 1 : 0) + (hash.key?(:hour) ? 1 : 0) + (hash.key?(:min) ? 1 : 0) + (hash.key?(:sec) ? 1 : 0)
          skip_civil = true if wn1_n > best_n
        end
        unless skip_civil
          k = :civil
          a = [:year, :mon, :mday, :hour, :min, :sec]
        end
      end

      unless k
        best_k = nil
        best_a = nil
        best_n = 0
        COMPLETE_FRAGS_TAB.each do |ek, ea|
          n = ea.count { |sym| hash.key?(sym) }
          if n > best_n
            best_k = ek
            best_a = ea
            best_n = n
          end
        end
        k = best_k
        a = best_a
      end

      if k && best_n < a.length
        today = nil
        case k
        when :ordinal
          hash[:year] ||= (today ||= Date.today).year
          hash[:yday] ||= 1
        when :civil
          a.each do |sym|
            break unless hash[sym].nil?
            hash[sym] = (today ||= Date.today).__send__(sym)
          end
          hash[:mon]  ||= 1
          hash[:mday] ||= 1
        when :commercial
          a.each do |sym|
            break unless hash[sym].nil?
            hash[sym] = (today ||= Date.today).__send__(sym)
          end
          hash[:cweek] ||= 1
          hash[:cwday] ||= 1
        when :wday
          today ||= Date.today
          hash[:jd] = (today - today.wday + hash[:wday]).jd
        when :wnum0
          a.each do |sym|
            break unless hash[sym].nil?
            hash[sym] = (today ||= Date.today).year
          end
          hash[:wnum0] ||= 0
          hash[:wday]  ||= 0
        when :wnum1
          a.each do |sym|
            break unless hash[sym].nil?
            hash[sym] = (today ||= Date.today).year
          end
          hash[:wnum1] ||= 0
          hash[:wday]  ||= 1
        end
      end

      if k == :time && klass <= DateTime
        hash[:jd] ||= Date.today.jd
      end

      hash[:hour] ||= 0
      hash[:min]  ||= 0
      hash[:sec]  = if hash[:sec].nil?
                      0
                    elsif hash[:sec] > 59
                      59
                    else
                      hash[:sec]
                    end
      hash
    end

    # Convert year/week/wday to Julian Day number.
    # f=0: Sunday-based (%U), d=0=Sun..6=Sat
    # f=1: Monday-based (%W), d=0=Mon..6=Sun (Mon-based)
    # Mirrors c_weeknum_to_jd() in ext/date/date_core.c:
    #   rjd2 = JD(Jan 1) + 6  (= JD of Jan 7)
    #   return (rjd2 - MOD((rjd2 - f + 1), 7) - 7) + 7*w + d
    def _sp_weeknum_to_jd(y, w, d, f, sg)
      jd_jan7 = civil_to_jd(y, 1, 1, sg) + 6
      (jd_jan7 - (jd_jan7 - f + 1) % 7 - 7) + 7 * w + d
    end

    # Find the Julian Day number from the fragment hash.
    # Tries jd, ordinal, civil, commercial, wnum0, wnum1 in order.
    # Returns jd integer or nil.
    def _sp_valid_date_frags_p(hash, sg) # rubocop:disable Metrics/CyclomaticComplexity
      return hash[:jd] if hash[:jd]

      if (yday = hash[:yday]) && (year = hash[:year])
        jd = internal_valid_ordinal?(year, yday, sg)
        return jd if jd
      end

      if (mday = hash[:mday]) && (mon = hash[:mon]) && (year = hash[:year])
        jd = internal_valid_civil?(year, mon, mday, sg)
        return jd if jd
      end

      # Commercial (ISO week): prefer cwday, else wday (treating 0 as 7)
      wday = hash[:cwday]
      if wday.nil?
        wday = hash[:wday]
        wday = 7 if !wday.nil? && wday == 0
      end
      if wday && (week = hash[:cweek]) && (year = hash[:cwyear])
        jd = internal_valid_commercial?(year, week, wday, sg)
        return jd if jd
      end

      # wnum0 (Sunday-start): prefer wday (0=Sun), else cwday (converting 7→0)
      wday = hash[:wday]
      if wday.nil?
        wday = hash[:cwday]
        wday = 0 if !wday.nil? && wday == 7
      end
      if wday && (week = hash[:wnum0]) && (year = hash[:year])
        jd = _sp_weeknum_to_jd(year, week, wday, 0, sg)
        return jd if jd
      end

      # wnum1 (Monday-start): convert to Mon-based 0=Mon using (wday-1)%7
      # Uses original wday (0=Sun) or cwday (1=Mon..7=Sun) — no 7→0 conversion here
      wday = hash[:wday]
      wday = hash[:cwday] if wday.nil?
      wday = (wday - 1) % 7 if wday
      if wday && (week = hash[:wnum1]) && (year = hash[:year])
        jd = _sp_weeknum_to_jd(year, week, wday, 1, sg)
        return jd if jd
      end

      nil
    end

    # Create a Date object from parsed fragment hash.
    def _new_by_frags(hash, sg)
      raise Error, 'invalid date' if hash.nil?
      hash = _sp_rewrite_frags(hash)
      hash = _sp_complete_frags(Date, hash)
      jd   = _sp_valid_date_frags_p(hash, sg)
      raise Error, 'invalid date' if jd.nil?
      new_from_jd(jd, sg)
    end
  end
end
