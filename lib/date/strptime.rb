# frozen_string_literal: true

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
      str = string.dup
      pos = 0
      hash = {}

      i = 0
      while i < format.length
        if format[i] == '%' && i + 1 < format.length
          i += 1

          # Parse modifier (E, O)
          modifier = nil
          if i < format.length && (format[i] == 'E' || format[i] == 'O')
            modifier = format[i]
            i += 1
          end

          # Parse colons for %:z, %::z, %:::z
          colons = 0
          while i < format.length && format[i] == ':'
            colons += 1
            i += 1
          end

          # Parse width
          width_str = String.new
          while i < format.length && format[i] =~ /[0-9]/
            width_str << format[i]
            i += 1
          end

          break if i >= format.length

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
              # Invalid modifier - try to match literal
              literal = "%#{modifier}#{':' * colons}#{width_str}#{spec}"
              if str[pos, literal.length] == literal
                pos += literal.length
              else
                return nil
              end
              next
            end
          end

          # Handle colon+z
          if colons > 0 && spec == 'z'
            result = _strptime_zone_colon(str, pos, colons)
            return nil unless result
            pos = result[:pos]
            hash[:zone] = result[:zone]
            hash[:offset] = result[:offset]
            next
          elsif colons > 0
            # Invalid colon usage
            return nil
          end

          # Determine field width
          field_width = width_str.empty? ? nil : width_str.to_i

          # C: NUM_PATTERN_P() - check if next format element is a digit-consuming pattern.
          # Used by %C, %G, %L, %N, %Y to limit digit consumption when adjacent.
          next_is_num = num_pattern_p(format, i)

          result = _strptime_spec(str, pos, spec, field_width, hash, next_is_num)
          return nil unless result
          pos = result[:pos]
          hash.merge!(result[:hash]) if result[:hash]
        elsif format[i] == '%' && i + 1 == format.length
          # Trailing % - match literal
          if pos < str.length && str[pos] == '%'
            pos += 1
          else
            return nil
          end
          i += 1
        elsif format[i] =~ /\s/
          # Whitespace in format matches zero or more whitespace in input
          i += 1
          pos += 1 while pos < str.length && str[pos] =~ /\s/
        else
          # Literal match
          if pos < str.length && str[pos] == format[i]
            pos += 1
          else
            return nil
          end
          i += 1
        end
      end

      # Store leftover if any
      if pos < str.length
        hash[:leftover] = str[pos..]
      end

      # --- Post-processing (C: date__strptime, date_strptime.c:524-546) ---

      # C: cent = del_hash("_cent");
      # Apply _cent to both cwyear and year.
      # Note: The inline _century approach in %C/%y/%g handlers covers most
      # cases, but this post-processing ensures correctness for all orderings
      # and applies century to both year and cwyear simultaneously.
      # We delete _century and _century_set here to keep the hash clean,
      # matching C's del_hash("_cent") behavior.
      hash.delete(:_century)
      hash.delete(:_century_set)

      # C: merid = del_hash("_merid");
      # Apply _merid to hour: hour = (hour % 12) + merid
      # This handles both %I (12-hour) and %H (24-hour) correctly:
      #   %I=12 + AM(0)  → (12 % 12) + 0  = 0
      #   %I=12 + PM(12) → (12 % 12) + 12 = 12
      #   %I=4  + PM(12) → (4 % 12)  + 12 = 16
      #   %I=4  + AM(0)  → (4 % 12)  + 0  = 4
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

    # C: num_pattern_p (date_strptime.c:48)
    # Returns true if the format string at position `i` starts with a
    # digit-consuming pattern (a literal digit or a %-specifier that reads digits).
    def num_pattern_p(format, i)
      return false if i >= format.length
      c = format[i]
      return true if c =~ /\d/
      if c == '%'
        i += 1
        return false if i >= format.length
        # Skip E/O modifier
        if format[i] == 'E' || format[i] == 'O'
          i += 1
          return false if i >= format.length
        end
        s = format[i]
        return true if s =~ /\d/ || NUM_PATTERN_SPECS.include?(s)
      end
      false
    end

    def _strptime_spec(str, pos, spec, width, context_hash, next_is_num = false)
      h = {}

      case spec
      when 'Y' # Full year (possibly negative)
        # C: if (NUM_PATTERN_P()) READ_DIGITS(n, 4); else READ_DIGITS_MAX(n);
        if width
          w = width
        elsif next_is_num
          w = 4
        else
          w = 40  # effectively unlimited
        end
        m = str[pos..].match(/\A([+-]?\d{1,#{w}})/)
        return nil unless m
        h[:year] = m[1].to_i
        { pos: pos + m[0].length, hash: h }

      when 'C' # Century
        # C: if (NUM_PATTERN_P()) READ_DIGITS(n, 2); else READ_DIGITS_MAX(n);
        if width
          w = width
        elsif next_is_num
          w = 2
        else
          w = 40
        end
        m = str[pos..].match(/\A([+-]?\d{1,#{w}})/)
        return nil unless m
        century = m[1].to_i
        h[:_century] = century
        if context_hash[:year] && !context_hash[:_century_set]
          h[:year] = century * 100 + (context_hash[:year] % 100)
          h[:_century_set] = true
        end
        { pos: pos + m[0].length, hash: h }

      when 'y' # 2-digit year
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        y = m[1].to_i
        if context_hash[:_century]
          h[:year] = context_hash[:_century] * 100 + y
          h[:_century_set] = true
        else
          h[:year] = y >= 69 ? y + 1900 : y + 2000
        end
        { pos: pos + m[0].length, hash: h }

      when 'm' # Month (01-12)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        mon = m[1].to_i
        return nil if mon < 1 || mon > 12
        h[:mon] = mon
        { pos: pos + m[0].length, hash: h }

      when 'd', 'e' # Day of month
        # C: if (str[si] == ' ') { si++; READ_DIGITS(n, 1); } else { READ_DIGITS(n, 2); }
        if str[pos] == ' '
          m = str[pos + 1..].match(/\A(\d)/)
          return nil unless m
          day = m[1].to_i
          return nil if day < 1 || day > 31
          h[:mday] = day
          { pos: pos + 1 + m[0].length, hash: h }
        else
          w = width || 2
          m = str[pos..].match(/\A(\d{1,#{w}})/)
          return nil unless m
          day = m[1].to_i
          return nil if day < 1 || day > 31
          h[:mday] = day
          { pos: pos + m[0].length, hash: h }
        end

      when 'j' # Day of year (001-366)
        w = width || 3
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        yday = m[1].to_i
        return nil if yday < 1 || yday > 366
        h[:yday] = yday
        { pos: pos + m[0].length, hash: h }

      when 'H', 'k' # Hour (00-24)
        # C: if (str[si] == ' ') { si++; READ_DIGITS(n, 1); } else { READ_DIGITS(n, 2); }
        if str[pos] == ' '
          m = str[pos + 1..].match(/\A(\d)/)
          return nil unless m
          hour = m[1].to_i
          return nil if hour > 24
          h[:hour] = hour
          { pos: pos + 1 + m[0].length, hash: h }
        else
          w = width || 2
          m = str[pos..].match(/\A(\d{1,#{w}})/)
          return nil unless m
          hour = m[1].to_i
          return nil if hour > 24
          h[:hour] = hour
          { pos: pos + m[0].length, hash: h }
        end

      when 'I', 'l' # Hour (01-12)
        # C: if (str[si] == ' ') { si++; READ_DIGITS(n, 1); } else { READ_DIGITS(n, 2); }
        if str[pos] == ' '
          m = str[pos + 1..].match(/\A(\d)/)
          return nil unless m
          hour = m[1].to_i
          return nil if hour < 1 || hour > 12
          h[:hour] = hour
          { pos: pos + 1 + m[0].length, hash: h }
        else
          w = width || 2
          m = str[pos..].match(/\A(\d{1,#{w}})/)
          return nil unless m
          hour = m[1].to_i
          return nil if hour < 1 || hour > 12
          h[:hour] = hour  # C stores raw value; _merid post-processing applies % 12
          { pos: pos + m[0].length, hash: h }
        end

      when 'M' # Minute (00-59)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        min = m[1].to_i
        return nil if min > 59
        h[:min] = min
        { pos: pos + m[0].length, hash: h }

      when 'S' # Second (00-60)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        sec = m[1].to_i
        return nil if sec > 60
        h[:sec] = sec
        { pos: pos + m[0].length, hash: h }

      when 'L' # Milliseconds
        # C: if (NUM_PATTERN_P()) READ_DIGITS(n, 3); else READ_DIGITS_MAX(n);
        if width
          w = width
        elsif next_is_num
          w = 3
        else
          w = 40
        end
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        frac_str = m[1].ljust(3, '0')[0, 3]
        h[:sec_fraction] = Rational(frac_str.to_i, 1000)
        { pos: pos + m[0].length, hash: h }

      when 'N' # Nanoseconds
        # C: if (NUM_PATTERN_P()) READ_DIGITS(n, 9); else READ_DIGITS_MAX(n);
        if width
          w = width
        elsif next_is_num
          w = 9
        else
          w = 40
        end
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        frac_str = m[1].ljust(9, '0')[0, 9]
        h[:sec_fraction] = Rational(frac_str.to_i, 1_000_000_000)
        { pos: pos + m[0].length, hash: h }

      when 'p', 'P' # AM/PM
        # C: set_hash("_merid", INT2FIX(hour));
        # Store _merid value (0 for AM, 12 for PM) for post-processing.
        # This avoids order-dependency: %p can appear before or after %I/%H.
        m = str[pos..].match(/\A(a\.?m\.?|p\.?m\.?)/i)
        return nil unless m
        ampm = m[1].delete('.').upcase
        h[:_merid] = (ampm == 'PM') ? 12 : 0
        { pos: pos + m[0].length, hash: h }

      when 'A', 'a' # Day name (full or abbreviated)
        DAYNAMES.each_with_index do |name, idx|
          next unless name
          # Try full name first, then abbreviated
          [name, ABBR_DAYNAMES[idx]].each do |n|
            next unless n
            if str[pos, n.length]&.downcase == n.downcase
              h[:wday] = idx
              return { pos: pos + n.length, hash: h }
            end
          end
        end
        return nil

      when 'B', 'b', 'h' # Month name (full or abbreviated)
        MONTHNAMES.each_with_index do |name, idx|
          next unless name
          # Try full name first, then abbreviated
          [name, ABBR_MONTHNAMES[idx]].each do |n|
            next unless n
            if str[pos, n.length]&.downcase == n.downcase
              h[:mon] = idx
              return { pos: pos + n.length, hash: h }
            end
          end
        end
        return nil

      when 'w' # Weekday number (0-6, Sunday=0)
        m = str[pos..].match(/\A(\d)/)
        return nil unless m
        wday = m[1].to_i
        return nil if wday > 6
        h[:wday] = wday
        { pos: pos + m[0].length, hash: h }

      when 'u' # Weekday number (1-7, Monday=1)
        m = str[pos..].match(/\A(\d)/)
        return nil unless m
        cwday = m[1].to_i
        return nil if cwday < 1 || cwday > 7
        h[:cwday] = cwday
        { pos: pos + m[0].length, hash: h }

      when 'U' # Week number (Sunday start, 00-53)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        wnum = m[1].to_i
        return nil if wnum > 53
        h[:wnum0] = wnum
        { pos: pos + m[0].length, hash: h }

      when 'W' # Week number (Monday start, 00-53)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        wnum = m[1].to_i
        return nil if wnum > 53
        h[:wnum1] = wnum
        { pos: pos + m[0].length, hash: h }

      when 'V' # ISO week number (01-53)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        cweek = m[1].to_i
        return nil if cweek < 1 || cweek > 53
        h[:cweek] = cweek
        { pos: pos + m[0].length, hash: h }

      when 'G' # ISO week year
        # C: if (NUM_PATTERN_P()) READ_DIGITS(n, 4); else READ_DIGITS_MAX(n);
        if width
          w = width
        elsif next_is_num
          w = 4
        else
          w = 40
        end
        m = str[pos..].match(/\A([+-]?\d{1,#{w}})/)
        return nil unless m
        h[:cwyear] = m[1].to_i
        { pos: pos + m[0].length, hash: h }

      when 'g' # ISO week year (2-digit)
        w = width || 2
        m = str[pos..].match(/\A(\d{1,#{w}})/)
        return nil unless m
        y = m[1].to_i
        if context_hash[:_century]
          h[:cwyear] = context_hash[:_century] * 100 + y
          h[:_century_set] = true
        else
          h[:cwyear] = y >= 69 ? y + 1900 : y + 2000
        end
        { pos: pos + m[0].length, hash: h }

      when 'Z', 'z' # Timezone
        result = _strptime_zone(str, pos)
        return nil unless result
        h[:zone] = result[:zone]
        h[:offset] = result[:offset] unless result[:offset].nil?
        { pos: result[:pos], hash: h }

      when 's' # Seconds since epoch
        m = str[pos..].match(/\A([+-]?\d+)/)
        return nil unless m
        h[:seconds] = m[1].to_i
        { pos: pos + m[0].length, hash: h }

      when 'Q' # Milliseconds since epoch
        m = str[pos..].match(/\A([+-]?\d+)/)
        return nil unless m
        h[:seconds] = Rational(m[1].to_i, 1000)
        { pos: pos + m[0].length, hash: h }

      when 'n' # Newline
        m = str[pos..].match(/\A\s+/)
        if m
          { pos: pos + m[0].length, hash: h }
        else
          { pos: pos, hash: h }
        end

      when 't' # Tab
        m = str[pos..].match(/\A\s+/)
        if m
          { pos: pos + m[0].length, hash: h }
        else
          { pos: pos, hash: h }
        end

      when '%' # Literal %
        if pos < str.length && str[pos] == '%'
          { pos: pos + 1, hash: h }
        else
          return nil
        end

      when 'F' # %Y-%m-%d
        result = _strptime_composite(str, pos, '%Y-%m-%d', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when 'D', 'x' # %m/%d/%y
        result = _strptime_composite(str, pos, '%m/%d/%y', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when 'T', 'X' # %H:%M:%S
        result = _strptime_composite(str, pos, '%H:%M:%S', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when 'R' # %H:%M
        result = _strptime_composite(str, pos, '%H:%M', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when 'r' # %I:%M:%S %p
        result = _strptime_composite(str, pos, '%I:%M:%S %p', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when 'c' # %a %b %e %H:%M:%S %Y
        result = _strptime_composite(str, pos, '%a %b %e %H:%M:%S %Y', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when 'v' # %e-%b-%Y
        result = _strptime_composite(str, pos, '%e-%b-%Y', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      when '+' # %a %b %e %H:%M:%S %Z %Y
        result = _strptime_composite(str, pos, '%a %b %e %H:%M:%S %Z %Y', context_hash)
        return nil unless result
        { pos: result[:pos], hash: result[:hash] }

      else
        # Unknown specifier - try to match literal
        literal = "%#{spec}"
        if str[pos, literal.length] == literal
          { pos: pos + literal.length, hash: h }
        else
          return nil
        end
      end
    end

    def _strptime_composite(str, pos, format, context_hash)
      merged_hash = context_hash.dup
      i = 0
      while i < format.length
        if format[i] == '%' && i + 1 < format.length
          i += 1
          spec = format[i]
          i += 1
          result = _strptime_spec(str, pos, spec, nil, merged_hash)
          return nil unless result
          pos = result[:pos]
          merged_hash.merge!(result[:hash]) if result[:hash]
        elsif format[i] =~ /\s/
          i += 1
          pos += 1 while pos < str.length && str[pos] =~ /\s/
        else
          if pos < str.length && str[pos] == format[i]
            pos += 1
          else
            return nil
          end
          i += 1
        end
      end
      # Return only newly parsed keys
      new_hash = {}
      merged_hash.each { |k, v| new_hash[k] = v unless context_hash.key?(k) && context_hash[k] == v }
      # Ensure updated values are included
      merged_hash.each { |k, v| new_hash[k] = v if context_hash[k] != v }
      { pos: pos, hash: new_hash }
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
