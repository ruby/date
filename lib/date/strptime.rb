# frozen_string_literal: true
require 'strscan'

# Implementation of ruby/date/ext/date/date_strptime.c
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
      # Fast paths for the most common format strings.
      case format
      when '%F', '%Y-%m-%d'
        m = /\A([+-]?\d+)-(\d{1,2})-(\d{1,2})/.match(string)
        return nil unless m
        mon  = m[2].to_i
        mday = m[3].to_i
        return nil if mon < 1 || mon > 12 || mday < 1 || mday > 31
        h = { year: m[1].to_i, mon: mon, mday: mday }
        rest = m.post_match
        h[:leftover] = rest unless rest.empty?
        return h

      when '%Y-%m-%d %H:%M:%S'
        m = /\A([+-]?\d+)-(\d{1,2})-(\d{1,2}) (\d{1,2}):(\d{1,2}):(\d{1,2})/.match(string)
        return nil unless m
        mon  = m[2].to_i
        mday = m[3].to_i
        hour = m[4].to_i
        min  = m[5].to_i
        sec  = m[6].to_i
        return nil if mon < 1 || mon > 12 || mday < 1 || mday > 31
        return nil if hour > 24 || min > 59 || sec > 60
        h = { year: m[1].to_i, mon: mon, mday: mday, hour: hour, min: min, sec: sec }
        rest = m.post_match
        h[:leftover] = rest unless rest.empty?
        return h

      when '%Y-%m-%dT%H:%M:%S'
        m = /\A([+-]?\d+)-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2}):(\d{1,2})/.match(string)
        return nil unless m
        mon  = m[2].to_i
        mday = m[3].to_i
        hour = m[4].to_i
        min  = m[5].to_i
        sec  = m[6].to_i
        return nil if mon < 1 || mon > 12 || mday < 1 || mday > 31
        return nil if hour > 24 || min > 59 || sec > 60
        h = { year: m[1].to_i, mon: mon, mday: mday, hour: hour, min: min, sec: sec }
        rest = m.post_match
        h[:leftover] = rest unless rest.empty?
        return h
      end

      ss = StringScanner.new(string)
      hash = {}

      i = 0
      fmt_len = format.length
      while i < fmt_len
        fb = format.getbyte(i)
        if fb == 37 && i + 1 < fmt_len  # '%'
          i += 1

          # Parse modifier (E, O)
          modifier = nil
          fb2 = format.getbyte(i)
          if i < fmt_len && (fb2 == 69 || fb2 == 79)  # 'E' == 69, 'O' == 79
            modifier = fb2 == 69 ? 'E' : 'O'
            i += 1
          end

          # Parse colons for %:z, %::z, %:::z
          colons = 0
          while i < fmt_len && format.getbyte(i) == 58  # ':'
            colons += 1
            i += 1
          end

          # Parse width as integer (avoids String allocation and regex digit check)
          field_width = nil
          while i < fmt_len
            db = format.getbyte(i)
            break if db < 48 || db > 57  # '0'..'9'
            field_width = (field_width || 0) * 10 + db - 48
            i += 1
          end

          break if i >= fmt_len

          spec = format[i]
          i += 1

          # Handle E/O modifier validity
          if modifier
            valid = case modifier
                    when 'E'
                      %w[c C x X y Y].include?(spec)
                    when 'O'
                      %w[d e H I m M S u U V w W y].include?(spec)
                    else
                      false
                    end
            unless valid
              literal = "%#{modifier}#{':' * colons}#{field_width}#{spec}"
              if ss.string[ss.pos, literal.length] == literal
                ss.pos += literal.length
              else
                return nil
              end
              next
            end
          end

          # Handle colon+z
          if colons > 0 && spec == 'z'
            result = _strptime_zone_colon(ss.string, ss.pos, colons)
            return nil unless result
            ss.pos = result[:pos]
            hash[:zone] = result[:zone]
            hash[:offset] = result[:offset]
            next
          elsif colons > 0
            # Invalid colon usage
            return nil
          end

          # C: NUM_PATTERN_P() - check if next format element is a digit-consuming pattern.
          next_is_num = num_pattern_p(format, i)

          return nil unless _strptime_spec(ss, spec, field_width, hash, next_is_num)
        elsif fb == 37 && i + 1 == fmt_len  # Trailing % - match literal
          if ss.string.getbyte(ss.pos) == 37  # '%'
            ss.pos += 1
          else
            return nil
          end
          i += 1
        elsif fb == 32 || fb == 9 || fb == 10 || fb == 13 || fb == 11 || fb == 12  # whitespace
          # Whitespace in format matches zero or more whitespace in input
          i += 1
          skip_ws(ss)
        else
          # Literal match
          if ss.string.getbyte(ss.pos) == fb
            ss.pos += 1
          else
            return nil
          end
          i += 1
        end
      end

      # Store leftover if any
      hash[:leftover] = ss.rest unless ss.eos?

      # --- Post-processing (C: date__strptime, date_strptime.c:524-546) ---

      # C: cent = del_hash("_cent");
      hash.delete(:_century)
      hash.delete(:_century_set)

      # C: merid = del_hash("_merid");
      merid = hash.delete(:_merid)
      if merid
        hour = hash[:hour]
        if hour
          hash[:hour] = (hour % 12) + merid
        end
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
      hash = _strptime(string, format)
      raise Error, "invalid strptime format - `#{format}'" unless hash

      # Apply comp for 2-digit year
      if hash[:year] && !hash[:_century_set]
        # If year came from %y (2-digit), comp_year69 was already applied
      end

      new_by_frags(hash, start)
    end

    private

    # Advances StringScanner past zero or more ASCII whitespace bytes
    # (space=32, tab=9, LF=10, CR=13, VT=11, FF=12).
    # Avoids regex overhead compared to ss.skip(/[ \t\n\r\v\f]*/).
    def skip_ws(ss)
      str = ss.string
      p   = ss.pos
      len = str.length
      while p < len
        b = str.getbyte(p)
        break unless b == 32 || b == 9 || b == 10 || b == 13 || b == 11 || b == 12
        p += 1
      end
      ss.pos = p
    end

    # Scans unsigned decimal integer from +str+ at +pos+, up to +max+ digits.
    # Returns [value, new_pos] or nil if no digit found.
    def scan_uint(str, pos, max)
      val   = 0
      count = 0
      len   = str.length
      while count < max && pos + count < len
        b = str.getbyte(pos + count)
        break unless b >= 48 && b <= 57  # '0'..'9'
        val = val * 10 + b - 48
        count += 1
      end
      count > 0 ? [val, pos + count] : nil
    end

    # Scans signed decimal integer (optional leading +/-) from +str+ at +pos+.
    # Returns [value, new_pos] or nil if no digit found.
    def scan_sint(str, pos, max)
      b = str.getbyte(pos)
      if b == 43       # '+'
        result = scan_uint(str, pos + 1, max)
        result
      elsif b == 45    # '-'
        result = scan_uint(str, pos + 1, max)
        result ? [-result[0], result[1]] : nil
      else
        scan_uint(str, pos, max)
      end
    end

    # C: num_pattern_p (date_strptime.c:48)
    # Returns true if the format string at position `i` starts with a
    # digit-consuming pattern (a literal digit or a %-specifier that reads digits).
    # Uses byte-level operations to avoid String allocations.
    def num_pattern_p(format, i)
      return false if i >= format.length
      b = format.getbyte(i)
      return true if b >= 48 && b <= 57  # '0'..'9'
      if b == 37  # '%'
        i += 1
        return false if i >= format.length
        b2 = format.getbyte(i)
        # Skip E/O modifier (E=69, O=79)
        if b2 == 69 || b2 == 79
          i += 1
          return false if i >= format.length
          b2 = format.getbyte(i)
        end
        return true if (b2 >= 48 && b2 <= 57) || NUM_PATTERN_SPECS_TABLE[b2]
      end
      false
    end

    # Modifies +hash+ in-place with parsed values for +spec+.
    # Advances +ss+ position on success. Returns true on success, nil on failure.
    def _strptime_spec(ss, spec, width, hash, next_is_num = false)
      str = ss.string
      pos = ss.pos

      case spec
      when 'Y' # Full year (possibly negative)
        year, new_pos = scan_sint(str, pos, width || (next_is_num ? 4 : 40))
        return nil unless year
        hash[:year] = year
        ss.pos = new_pos
        true

      when 'C' # Century
        century, new_pos = scan_sint(str, pos, width || (next_is_num ? 2 : 40))
        return nil unless century
        hash[:_century] = century
        if hash[:year] && !hash[:_century_set]
          hash[:year] = century * 100 + (hash[:year] % 100)
          hash[:_century_set] = true
        end
        ss.pos = new_pos
        true

      when 'y' # 2-digit year
        y, new_pos = scan_uint(str, pos, width || 2)
        return nil unless y
        if hash[:_century]
          hash[:year] = hash[:_century] * 100 + y
          hash[:_century_set] = true
        else
          hash[:year] = y >= 69 ? y + 1900 : y + 2000
        end
        ss.pos = new_pos
        true

      when 'm' # Month (01-12)
        mon, new_pos = scan_uint(str, pos, width || 2)
        return nil unless mon
        return nil if mon < 1 || mon > 12
        hash[:mon] = mon
        ss.pos = new_pos
        true

      when 'd', 'e' # Day of month
        if str.getbyte(pos) == 32  # ' '
          day, new_pos = scan_uint(str, pos + 1, 1)
          return nil unless day
          return nil if day < 1 || day > 31
          hash[:mday] = day
          ss.pos = new_pos
        else
          day, new_pos = scan_uint(str, pos, width || 2)
          return nil unless day
          return nil if day < 1 || day > 31
          hash[:mday] = day
          ss.pos = new_pos
        end
        true

      when 'j' # Day of year (001-366)
        yday, new_pos = scan_uint(str, pos, width || 3)
        return nil unless yday
        return nil if yday < 1 || yday > 366
        hash[:yday] = yday
        ss.pos = new_pos
        true

      when 'H', 'k' # Hour (00-24)
        if str.getbyte(pos) == 32  # ' '
          hour, new_pos = scan_uint(str, pos + 1, 1)
          return nil unless hour
          return nil if hour > 24
          hash[:hour] = hour
          ss.pos = new_pos
        else
          hour, new_pos = scan_uint(str, pos, width || 2)
          return nil unless hour
          return nil if hour > 24
          hash[:hour] = hour
          ss.pos = new_pos
        end
        true

      when 'I', 'l' # Hour (01-12)
        if str.getbyte(pos) == 32  # ' '
          hour, new_pos = scan_uint(str, pos + 1, 1)
          return nil unless hour
          return nil if hour < 1 || hour > 12
          hash[:hour] = hour
          ss.pos = new_pos
        else
          hour, new_pos = scan_uint(str, pos, width || 2)
          return nil unless hour
          return nil if hour < 1 || hour > 12
          hash[:hour] = hour
          ss.pos = new_pos
        end
        true

      when 'M' # Minute (00-59)
        min, new_pos = scan_uint(str, pos, width || 2)
        return nil unless min
        return nil if min > 59
        hash[:min] = min
        ss.pos = new_pos
        true

      when 'S' # Second (00-60)
        sec, new_pos = scan_uint(str, pos, width || 2)
        return nil unless sec
        return nil if sec > 60
        hash[:sec] = sec
        ss.pos = new_pos
        true

      when 'L' # Milliseconds — normalize digit string to 3-digit precision
        w = width || (next_is_num ? 3 : 40)
        val, count = 0, 0
        str_len = str.length
        while count < w && pos + count < str_len
          b = str.getbyte(pos + count)
          break unless b >= 48 && b <= 57
          val = val * 10 + b - 48
          count += 1
        end
        return nil if count == 0
        val *= 10 ** (3 - count) if count < 3
        val /= 10 ** (count - 3) if count > 3
        hash[:sec_fraction] = Rational(val, 1000)
        ss.pos = pos + count
        true

      when 'N' # Nanoseconds — normalize digit string to 9-digit precision
        w = width || (next_is_num ? 9 : 40)
        val, count = 0, 0
        str_len = str.length
        while count < w && pos + count < str_len
          b = str.getbyte(pos + count)
          break unless b >= 48 && b <= 57
          val = val * 10 + b - 48
          count += 1
        end
        return nil if count == 0
        val *= 10 ** (9 - count) if count < 9
        val /= 10 ** (count - 9) if count > 9
        hash[:sec_fraction] = Rational(val, 1_000_000_000)
        ss.pos = pos + count
        true

      when 'p', 'P' # AM/PM
        m = ss.scan(/a\.?m\.?|p\.?m\.?/i)
        return nil unless m
        ampm = m.delete('.').upcase
        hash[:_merid] = (ampm == 'PM') ? 12 : 0
        true

      when 'A', 'a' # Day name (full or abbreviated)
        # Zero-alloc integer key from 3 bytes (lowercase via | 0x20).
        # Check byte 4 to skip full-name string comparison in the common case.
        b0 = str.getbyte(pos)
        b1 = str.getbyte(pos + 1)
        b2 = str.getbyte(pos + 2)
        if b0 && b1 && b2
          k0 = b0 | 0x20; k1 = b1 | 0x20; k2 = b2 | 0x20
          if k0 >= 97 && k0 <= 122 && k1 >= 97 && k1 <= 122 && k2 >= 97 && k2 <= 122
            ikey = (k0 << 16) | (k1 << 8) | k2
            if (info = STRPTIME_DAYNAME_BY_INT_KEY[ikey])
              idx, full, full_len, abbr_len = info
              b3 = str.getbyte(pos + abbr_len)
              # If next byte is non-alpha, it's an abbreviated name.
              if b3.nil? || (t = b3 | 0x20) < 97 || t > 122
                hash[:wday] = idx
                ss.pos = pos + abbr_len
              elsif str[pos, full_len]&.downcase == full
                hash[:wday] = idx
                ss.pos = pos + full_len
              else
                hash[:wday] = idx
                ss.pos = pos + abbr_len
              end
              true
            end
          end
        end

      when 'B', 'b', 'h' # Month name (full or abbreviated)
        # Zero-alloc integer key from 3 bytes (lowercase via | 0x20).
        b0 = str.getbyte(pos)
        b1 = str.getbyte(pos + 1)
        b2 = str.getbyte(pos + 2)
        if b0 && b1 && b2
          k0 = b0 | 0x20; k1 = b1 | 0x20; k2 = b2 | 0x20
          if k0 >= 97 && k0 <= 122 && k1 >= 97 && k1 <= 122 && k2 >= 97 && k2 <= 122
            ikey = (k0 << 16) | (k1 << 8) | k2
            if (info = STRPTIME_MONNAME_BY_INT_KEY[ikey])
              idx, full, full_len, abbr_len = info
              b3 = str.getbyte(pos + abbr_len)
              if b3.nil? || (t = b3 | 0x20) < 97 || t > 122
                hash[:mon] = idx
                ss.pos = pos + abbr_len
              elsif str[pos, full_len]&.downcase == full
                hash[:mon] = idx
                ss.pos = pos + full_len
              else
                hash[:mon] = idx
                ss.pos = pos + abbr_len
              end
              true
            end
          end
        end

      when 'w' # Weekday number (0-6, Sunday=0)
        b = str.getbyte(pos)
        return nil unless b && b >= 48 && b <= 54  # '0'..'6'
        hash[:wday] = b - 48
        ss.pos = pos + 1
        true

      when 'u' # Weekday number (1-7, Monday=1)
        b = str.getbyte(pos)
        return nil unless b && b >= 49 && b <= 55  # '1'..'7'
        hash[:cwday] = b - 48
        ss.pos = pos + 1
        true

      when 'U' # Week number (Sunday start, 00-53)
        wnum, new_pos = scan_uint(str, pos, width || 2)
        return nil unless wnum
        return nil if wnum > 53
        hash[:wnum0] = wnum
        ss.pos = new_pos
        true

      when 'W' # Week number (Monday start, 00-53)
        wnum, new_pos = scan_uint(str, pos, width || 2)
        return nil unless wnum
        return nil if wnum > 53
        hash[:wnum1] = wnum
        ss.pos = new_pos
        true

      when 'V' # ISO week number (01-53)
        cweek, new_pos = scan_uint(str, pos, width || 2)
        return nil unless cweek
        return nil if cweek < 1 || cweek > 53
        hash[:cweek] = cweek
        ss.pos = new_pos
        true

      when 'G' # ISO week year
        cwyear, new_pos = scan_sint(str, pos, width || (next_is_num ? 4 : 40))
        return nil unless cwyear
        hash[:cwyear] = cwyear
        ss.pos = new_pos
        true

      when 'g' # ISO week year (2-digit)
        y, new_pos = scan_uint(str, pos, width || 2)
        return nil unless y
        if hash[:_century]
          hash[:cwyear] = hash[:_century] * 100 + y
          hash[:_century_set] = true
        else
          hash[:cwyear] = y >= 69 ? y + 1900 : y + 2000
        end
        ss.pos = new_pos
        true

      when 'Z', 'z' # Timezone
        result = _strptime_zone(str, pos)
        return nil unless result
        hash[:zone] = result[:zone]
        hash[:offset] = result[:offset] unless result[:offset].nil?
        ss.pos = result[:pos]
        true

      when 's' # Seconds since epoch
        secs, new_pos = scan_sint(str, pos, 40)
        return nil unless secs
        hash[:seconds] = secs
        ss.pos = new_pos
        true

      when 'Q' # Milliseconds since epoch
        msecs, new_pos = scan_sint(str, pos, 40)
        return nil unless msecs
        hash[:seconds] = Rational(msecs, 1000)
        ss.pos = new_pos
        true

      when 'n', 't' # Newline / Tab — match any whitespace
        skip_ws(ss)
        true

      when '%' # Literal %
        return nil unless str.getbyte(pos) == 37  # '%'
        ss.pos = pos + 1
        true

      when 'F' # %Y-%m-%d
        result = _strptime_composite(ss, '%Y-%m-%d', hash)
        return nil unless result
        hash.merge!(result)
        true

      when 'D', 'x' # %m/%d/%y
        result = _strptime_composite(ss, '%m/%d/%y', hash)
        return nil unless result
        hash.merge!(result)
        true

      when 'T', 'X' # %H:%M:%S
        result = _strptime_composite(ss, '%H:%M:%S', hash)
        return nil unless result
        hash.merge!(result)
        true

      when 'R' # %H:%M
        result = _strptime_composite(ss, '%H:%M', hash)
        return nil unless result
        hash.merge!(result)
        true

      when 'r' # %I:%M:%S %p
        result = _strptime_composite(ss, '%I:%M:%S %p', hash)
        return nil unless result
        hash.merge!(result)
        true

      when 'c' # %a %b %e %H:%M:%S %Y
        result = _strptime_composite(ss, '%a %b %e %H:%M:%S %Y', hash)
        return nil unless result
        hash.merge!(result)
        true

      when 'v' # %e-%b-%Y
        result = _strptime_composite(ss, '%e-%b-%Y', hash)
        return nil unless result
        hash.merge!(result)
        true

      when '+' # %a %b %e %H:%M:%S %Z %Y
        result = _strptime_composite(ss, '%a %b %e %H:%M:%S %Z %Y', hash)
        return nil unless result
        hash.merge!(result)
        true

      else
        # Unknown specifier - try to match literal
        literal = "%#{spec}"
        if str[pos, literal.length] == literal
          ss.pos = pos + literal.length
          true
        else
          nil
        end
      end
    end

    def _strptime_composite(ss, format, context_hash)
      merged_hash = context_hash.dup
      i = 0
      fmt_len = format.length
      while i < fmt_len
        fb = format.getbyte(i)
        if fb == 37 && i + 1 < fmt_len  # '%'
          i += 1
          spec = format[i]
          i += 1
          return nil unless _strptime_spec(ss, spec, nil, merged_hash)
        elsif fb == 32 || fb == 9 || fb == 10 || fb == 13 || fb == 11 || fb == 12  # whitespace
          i += 1
          skip_ws(ss)
        else
          if ss.string.getbyte(ss.pos) == fb
            ss.pos += 1
          else
            return nil
          end
          i += 1
        end
      end
      # Return only newly parsed or updated keys
      new_hash = {}
      merged_hash.each { |k, v| new_hash[k] = v unless context_hash.key?(k) && context_hash[k] == v }
      merged_hash.each { |k, v| new_hash[k] = v if context_hash[k] != v }
      new_hash
    end

    def _strptime_zone(str, pos)
      remaining = str[pos..]
      return nil if remaining.nil? || remaining.empty?

      # Try numeric timezone: +HH:MM, -HH:MM, +HH:MM:SS, -HH:MM:SS, +HHMM, -HHMM, +HH, -HH
      # Also: GMT+HH, GMT-HH:MM, etc. and decimal offsets
      # Colon-separated pattern (requires colon) tried first, then plain digits.
      m = remaining.match(/\A(
        (?:GMT|UTC)?
        [+-]
        (?:\d{1,2}:\d{2}(?::\d{2})?
          |
         \d+(?:[.,]\d+)?)
      )/xi)

      if m
        zone_str = m[1]
        offset = _parse_zone_offset(zone_str)
        return { pos: pos + zone_str.length, zone: zone_str, offset: offset }
      end

      # Try named timezone (multi-word: "E. Australia Standard Time", "Mountain Daylight Time")
      # Match alphabetic words with dots and spaces
      m = remaining.match(/\A([A-Za-z][A-Za-z.]*(?:\s+[A-Za-z][A-Za-z.]*)*)/i)
      if m
        zone_candidate = m[1]
        # Try progressively shorter matches (longest first)
        words = zone_candidate.split(/\s+/)
        (words.length).downto(1) do |n|
          try_zone = words[0, n].join(' ')
          offset = _zone_name_to_offset(try_zone)
          if offset
            # Compute actual consumed length preserving original spacing
            if n == words.length
              actual_zone = zone_candidate
            else
              # Find end of nth word in original string
              end_pos = 0
              n.times do |wi|
                end_pos = zone_candidate.index(words[wi], end_pos)
                end_pos += words[wi].length
              end
              actual_zone = zone_candidate[0, end_pos]
            end
            return { pos: pos + actual_zone.length, zone: actual_zone, offset: offset }
          end
        end
        # Unknown timezone - return full match with nil offset
        # (Military single-letter zones like 'z' are already in ZONE_TABLE
        #  and handled by the loop above)
        return { pos: pos + zone_candidate.length, zone: zone_candidate, offset: nil }
      end

      nil
    end

    def _strptime_zone_colon(str, pos, colons)
      remaining = str[pos..]
      return nil if remaining.nil? || remaining.empty?

      case colons
      when 1 # %:z -> +HH:MM
        m = remaining.match(/\A([+-])(\d{2}):(\d{2})/)
        return nil unless m
        sign = m[1] == '-' ? -1 : 1
        offset = sign * (m[2].to_i * 3600 + m[3].to_i * 60)
        zone = m[0]
        { pos: pos + zone.length, zone: zone, offset: offset }
      when 2 # %::z -> +HH:MM:SS
        m = remaining.match(/\A([+-])(\d{2}):(\d{2}):(\d{2})/)
        return nil unless m
        sign = m[1] == '-' ? -1 : 1
        offset = sign * (m[2].to_i * 3600 + m[3].to_i * 60 + m[4].to_i)
        zone = m[0]
        { pos: pos + zone.length, zone: zone, offset: offset }
      when 3 # %:::z -> +HH[:MM[:SS]]
        m = remaining.match(/\A([+-])(\d{2})(?::(\d{2})(?::(\d{2}))?)?/)
        return nil unless m
        sign = m[1] == '-' ? -1 : 1
        offset = sign * (m[2].to_i * 3600 + (m[3] ? m[3].to_i * 60 : 0) + (m[4] ? m[4].to_i : 0))
        zone = m[0]
        { pos: pos + zone.length, zone: zone, offset: offset }
      else
        nil
      end
    end

    def _parse_zone_offset(zone_str)
      # Strip GMT/UTC prefix
      s = zone_str.sub(/\A(?:GMT|UTC)/i, '')
      return 0 if s.empty?

      m = s.match(/\A([+-])(\d+(?:[.,]\d+)?)$/)
      if m
        sign = m[1] == '-' ? -1 : 1
        num = m[2].tr(',', '.')
        if num.include?('.')
          # Decimal hours
          hours = num.to_f
          return nil if hours.abs >= 24
          return sign * (hours * 3600).to_i
        else
          # Could be HH, HHMM, or HHMMSS
          digits = num
          case digits.length
          when 1, 2
            h = digits.to_i
            return nil if h >= 24
            return sign * h * 3600
          when 3, 4
            h = digits[0, 2].to_i
            min = digits[2, 2].to_i
            return nil if h >= 24 || min >= 60
            return sign * (h * 3600 + min * 60)
          when 5, 6
            h = digits[0, 2].to_i
            min = digits[2, 2].to_i
            sec = digits[4, 2].to_i
            return nil if h >= 24 || min >= 60 || sec >= 60
            return sign * (h * 3600 + min * 60 + sec)
          else
            return nil
          end
        end
      end

      # +HH:MM or +HH:MM:SS
      m = s.match(/\A([+-])(\d{1,2}):(\d{2})(?::(\d{2}))?$/)
      if m
        sign = m[1] == '-' ? -1 : 1
        h = m[2].to_i
        min = m[3].to_i
        sec = m[4] ? m[4].to_i : 0
        return nil if h >= 24 || min >= 60 || sec >= 60
        return sign * (h * 3600 + min * 60 + sec)
      end

      nil
    end

    def _zone_name_to_offset(name)
      ZONE_TABLE[name.downcase.gsub(/\s+/, ' ')]
    end
  end
end
