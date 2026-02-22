# frozen_string_literal: true

require_relative "patterns"
require_relative "zonetab"

# Implementation of ruby/date/ext/date/date_parse.c
class Date
  class << self
    # call-seq:
    #   Date.parse(string = '-4712-01-01', comp = true, start = Date::ITALY, limit: 128) -> date
    #
    # Returns a new \Date object with values parsed from +string+.
    #
    # If +comp+ is +true+ and the given year is in the range <tt>(0..99)</tt>,
    # the current century is supplied; otherwise, the year is taken as given.
    #
    # See argument {start}[rdoc-ref:language/calendars.rdoc@Argument+start].
    # See argument {limit}[rdoc-ref:Date@Argument+limit].
    #
    # Related: Date._parse (returns a hash).
    def parse(string = JULIAN_EPOCH_DATE, comp = true, start = DEFAULT_SG, limit: 128)
      hash = _parse(string, comp, limit: limit)
      new_by_frags(hash, start)
    end

    # call-seq:
    #   Date._parse(string, comp = true, limit: 128) -> hash
    #
    # Returns a hash of values parsed from +string+.
    #
    # If +comp+ is +true+ and the given year is in the range <tt>(0..99)</tt>,
    # the current century is supplied; otherwise, the year is taken as given.
    #
    # See argument {limit}[rdoc-ref:Date@Argument+limit].
    #
    # Related: Date.parse (returns a \Date object).
    def _parse(string, comp = true, limit: 128)
      string = string_value(string)
      str = string.strip

      # Check limit
      if limit && str.length > limit
        raise ArgumentError, "string length (#{str.length}) exceeds the limit #{limit}"
      end

      date__parse(str, comp)
    end

    # call-seq:
    #   Date._iso8601(string, limit: 128) -> hash
    #
    # Returns a hash of values parsed from +string+, which should contain
    # an {ISO 8601 formatted date}[rdoc-ref:language/strftime_formatting.rdoc@ISO+8601+Format+Specifications]:
    #
    #   d = Date.new(2001, 2, 3)
    #   s = d.iso8601    # => "2001-02-03"
    #   Date._iso8601(s) # => {:mday=>3, :year=>2001, :mon=>2}
    #
    # See argument {limit}[rdoc-ref:Date@Argument+limit].
    #
    # Related: Date.iso8601 (returns a \Date object).
    def _iso8601(string, limit: 128)
      return {} if string.nil?
      string = string_value(string)
      check_string_limit(string, limit)

      date__iso8601(string)
    end

    # date__rfc3339 in date_parse.c
    def _rfc3339(string, limit: 128)
      return {} if string.nil?
      string = string_value(string)
      check_string_limit(string, limit)

      date__rfc3339(string)
    end

    # date__xmlschema in date_parse.c
    def _xmlschema(string, limit: 128)
      return {} if string.nil?
      string = string_value(string)
      check_string_limit(string, limit)

      date__xmlschema(string)
    end

    # date__rfc2822 in date_parse.c
    def _rfc2822(string, limit: 128)
      return {} if string.nil?
      string = string_value(string)
      check_string_limit(string, limit)

      date__rfc2822(string)
    end
    alias _rfc822 _rfc2822

    # call-seq:
    #   Date._httpdate(string, limit: 128) -> hash
    #
    # Returns a hash of values parsed from +string+, which should be a valid
    # {HTTP date format}[rdoc-ref:language/strftime_formatting.rdoc@HTTP+Format]:
    #
    #   d = Date.new(2001, 2, 3)
    #   s = d.httpdate # => "Sat, 03 Feb 2001 00:00:00 GMT"
    #   Date._httpdate(s)
    #   # => {:wday=>6, :mday=>3, :mon=>2, :year=>2001, :hour=>0, :min=>0, :sec=>0, :zone=>"GMT", :offset=>0}
    #
    # Related: Date.httpdate (returns a \Date object).
    def _httpdate(string, limit: 128)
      return {} if string.nil?
      string = string_value(string)
      check_string_limit(string, limit)

      date__httpdate(string)
    end

    # call-seq:
    #   Date._jisx0301(string, limit: 128) -> hash
    #
    # Returns a hash of values parsed from +string+, which should be a valid
    # {JIS X 0301 date format}[rdoc-ref:language/strftime_formatting.rdoc@JIS+X+0301+Format]:
    #
    #   d = Date.new(2001, 2, 3)
    #   s = d.jisx0301    # => "H13.02.03"
    #   Date._jisx0301(s) # => {:year=>2001, :mon=>2, :mday=>3}
    #
    # See argument {limit}[rdoc-ref:Date@Argument+limit].
    #
    # Related: Date.jisx0301 (returns a \Date object).
    def _jisx0301(string, limit: 128)
      return {} if string.nil?
      string = string_value(string)
      check_string_limit(string, limit)

      date__jisx0301(string)
    end

    # --- Constructor methods ---

    def iso8601(string = JULIAN_EPOCH_DATE, start = DEFAULT_SG, limit: 128)
      hash = _iso8601(string, limit: limit)

      new_by_frags(hash, start)
    end

    def rfc3339(string = JULIAN_EPOCH_DATETIME, start = DEFAULT_SG, limit: 128)
      hash = _rfc3339(string, limit: limit)

      new_by_frags(hash, start)
    end

    def xmlschema(string = JULIAN_EPOCH_DATE, start = DEFAULT_SG, limit: 128)
      hash = _xmlschema(string, limit: limit)

      new_by_frags(hash, start)
    end

    def rfc2822(string = JULIAN_EPOCH_DATETIME_RFC2822, start = DEFAULT_SG, limit: 128)
      hash = _rfc2822(string, limit: limit)

      new_by_frags(hash, start)
    end
    alias rfc822 rfc2822

    def httpdate(string = JULIAN_EPOCH_DATETIME_HTTPDATE, start = DEFAULT_SG, limit: 128)
      hash = _httpdate(string, limit: limit)

      new_by_frags(hash, start)
    end

    def jisx0301(string = JULIAN_EPOCH_DATE, start = DEFAULT_SG, limit: 128)
      hash = _jisx0301(string, limit: limit)

      new_by_frags(hash, start)
    end

    private

    def date__parse(str, comp)
      hash = {}

      # Preprocessing: duplicate and replace non-allowed characters.
      # Non-TIGHT: Replace [^-+',./:@[:alnum:]\[\]]+ with a single space
      str = str.dup.gsub(%r{[^-+',./:@[:alnum:]\[\]]+}, ' ')

      hash[:_comp] = comp

      # Parser invocation (non-TIGHT order)
      # Note: C's HAVE_ELEM_P calls check_class(str) every time because
      # str is modified by subx after each successful parse.

      # parse_day and parse_time always run (no goto ok).
      if have_elem_p?(str, HAVE_ALPHA)
        parse_day(str, hash)
      end

      if have_elem_p?(str, HAVE_DIGIT)
        parse_time(str, hash)
      end

      # Date parsers: first success skips the rest (C's "goto ok").
      # In C, all paths converge at ok: for post-processing.
      catch(:date_parsed) do
        if have_elem_p?(str, HAVE_ALPHA | HAVE_DIGIT)
          throw :date_parsed if parse_eu(str, hash)
          throw :date_parsed if parse_us(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT | HAVE_DASH)
          throw :date_parsed if parse_iso(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT | HAVE_DOT)
          throw :date_parsed if parse_jis(str, hash)
        end

        if have_elem_p?(str, HAVE_ALPHA | HAVE_DIGIT | HAVE_DASH)
          throw :date_parsed if parse_vms(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT | HAVE_SLASH)
          throw :date_parsed if parse_sla(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT | HAVE_DOT)
          throw :date_parsed if parse_dot(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT)
          throw :date_parsed if parse_iso2(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT)
          throw :date_parsed if parse_year(str, hash)
        end

        if have_elem_p?(str, HAVE_ALPHA)
          throw :date_parsed if parse_mon(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT)
          throw :date_parsed if parse_mday(str, hash)
        end

        if have_elem_p?(str, HAVE_DIGIT)
          throw :date_parsed if parse_ddd(str, hash)
        end
      end

      # ok: (post-processing — always runs, matching C's ok: label)
      if have_elem_p?(str, HAVE_ALPHA)
        parse_bc(str, hash)
      end
      if have_elem_p?(str, HAVE_DIGIT)
        parse_frag(str, hash)
      end

      apply_comp(hash)
      hash
    end

    # asctime format with timezone: Sat Aug 28 02:29:34 JST 1999
    def parse_asctime_with_zone(str, hash)
      return false unless str =~ /\b(sun|mon|tue|wed|thu|fri|sat)[[:space:]]+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[[:space:]]+(\d{1,2})[[:space:]]+(\d{2}):(\d{2}):(\d{2})[[:space:]]+(.*?)[[:space:]]+(-?\d+)[[:space:]]*$/i

      wday_str = $1
      mon_str = $2
      mday_str = $3
      hour_str = $4
      min_str = $5
      sec_str = $6
      zone_part = $7
      year_str = $8

      hash[:wday] = day_num(wday_str)
      hash[:mon] = mon_num(mon_str)
      hash[:mday] = mday_str.to_i
      hash[:hour] = hour_str.to_i
      hash[:min] = min_str.to_i
      hash[:sec] = sec_str.to_i

      zone_part = zone_part.strip
      unless zone_part.empty?
        zone = zone_part.gsub(/\s+/, ' ')
        hash[:zone] = zone
        hash[:offset] = parse_zone_offset(zone)
      end

      hash[:_year_str] = year_str
      hash[:year] = year_str.to_i
      apply_comp(hash)

      true
    end

    # asctime format without timezone: Sat Aug 28 02:55:50 1999
    def parse_asctime(str, hash)
      return false unless str =~ /\b(sun|mon|tue|wed|thu|fri|sat)\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(-?\d+)\s*$/i

      wday_str = $1
      mon_str = $2
      mday_str = $3
      hour_str = $4
      min_str = $5
      sec_str = $6
      year_str = $7

      hash[:wday] = day_num(wday_str)
      hash[:mon] = mon_num(mon_str)
      hash[:mday] = mday_str.to_i
      hash[:hour] = hour_str.to_i
      hash[:min] = min_str.to_i
      hash[:sec] = sec_str.to_i
      hash[:_year_str] = year_str
      hash[:year] = year_str.to_i
      apply_comp(hash)

      true
    end

    # HTTP date type 1: "Sat, 03 Feb 2001 00:00:00 GMT"
    def httpdate_type1(str, hash)
      pattern = /\A\s*(#{ABBR_DAYS_PATTERN})\s*,\s+
                (\d{2})\s+
                (#{ABBR_MONTHS_PATTERN})\s+
                (-?\d{4})\s+
                (\d{2}):(\d{2}):(\d{2})\s+
                (gmt)\s*\z/ix

      match = pattern.match(str)
      return false unless match

      hash[:wday] = day_num(match[1])
      hash[:mday] = match[2].to_i
      hash[:mon] = mon_num(match[3])
      hash[:year] = match[4].to_i
      hash[:hour] = match[5].to_i
      hash[:min] = match[6].to_i
      hash[:sec] = match[7].to_i
      hash[:zone] = match[8]
      hash[:offset] = 0

      true
    end

    # HTTP date type 2: "Saturday, 03-Feb-01 00:00:00 GMT"
    def httpdate_type2(str, hash)
      pattern = /\A\s*(#{DAYS_PATTERN})\s*,\s+
                (\d{2})\s*-\s*
                (#{ABBR_MONTHS_PATTERN})\s*-\s*
                (\d{2})\s+
                (\d{2}):(\d{2}):(\d{2})\s+
                (gmt)\s*\z/ix

      match = pattern.match(str)
      return false unless match

      hash[:wday] = day_num(match[1])
      hash[:mday] = match[2].to_i
      hash[:mon] = mon_num(match[3])

      # Year completion for 2-digit year
      year = match[4].to_i
      year = comp_year69(year) if year >= 0 && year <= 99
      hash[:year] = year

      hash[:hour] = match[5].to_i
      hash[:min] = match[6].to_i
      hash[:sec] = match[7].to_i
      hash[:zone] = match[8]
      hash[:offset] = 0

      true
    end

    # HTTP date type 3: "Sat Feb  3 00:00:00 2001"
    def httpdate_type3(str, hash)
      pattern = /\A\s*(#{ABBR_DAYS_PATTERN})\s+
                (#{ABBR_MONTHS_PATTERN})\s+
                (\d{1,2})\s+
                (\d{2}):(\d{2}):(\d{2})\s+
                (\d{4})\s*\z/ix

      match = pattern.match(str)
      return false unless match

      hash[:wday] = day_num(match[1])
      hash[:mon] = mon_num(match[2])
      hash[:mday] = match[3].to_i
      hash[:hour] = match[4].to_i
      hash[:min] = match[5].to_i
      hash[:sec] = match[6].to_i
      hash[:year] = match[7].to_i

      true
    end

    # parse_day in date_parse.c.
    # Non-TIGHT pattern: \b(sun|mon|tue|wed|thu|fri|sat)[^-/\d\s]*
    # The [^-/\d\s]* part consumes trailing characters (e.g., "urday"
    # in "Saturday") so they get replaced by subx, but only the
    # abbreviation in $1 is used.
    def parse_day(str, hash)
      m = subx(str, PARSE_DAY_PAT)
      return false unless m

      hash[:wday] = day_num(m[1])

      true
    end

    # parse_time in date_parse.c.
    # Uses subx to replace the matched time portion with " " so
    # subsequent parsers (parse_us, etc.) won't re-match it.
    def parse_time(str, hash)
      m = subx(str, TIME_PAT)
      return false unless m

      time_str = m[1]
      zone_str = m[2]

      parse_time_detail(time_str, hash)

      if zone_str && !zone_str.empty?
        hash[:zone]   = zone_str
        hash[:offset] = date_zone_to_diff(zone_str)
      end

      true
    end

    # parse_ddd in date_parse.c.
    def parse_ddd(str, hash)
      m = subx(str, PARSE_DDD_PAT)
      return false unless m

      sign        = m[1]
      digits      = m[2]
      time_digits = m[3]
      fraction    = m[4]
      zone        = m[5]

      l = digits.length

      # Branches based on the length of the main number string.
      case l
      when 2
        if time_digits.nil? && !fraction.nil?
          hash[:sec] = digits[-2, 2].to_i
        else
          hash[:mday] = digits[0, 2].to_i
        end
      when 4
        if time_digits.nil? && !fraction.nil?
          hash[:sec] = digits[-2, 2].to_i
          hash[:min] = digits[-4, 2].to_i
        else
          hash[:mon]  = digits[0, 2].to_i
          hash[:mday] = digits[2, 2].to_i
        end
      when 6
        if time_digits.nil? && !fraction.nil?
          hash[:sec]  = digits[-2, 2].to_i
          hash[:min]  = digits[-4, 2].to_i
          hash[:hour] = digits[-6, 2].to_i
        else
          y = digits[0, 2].to_i
          y = -y if sign == '-'
          hash[:year] = y
          hash[:mon]  = digits[2, 2].to_i
          hash[:mday] = digits[4, 2].to_i
          hash[:_year_str] = digits[0, 2]  # year completion
        end
      when 8, 10, 12, 14
        if time_digits.nil? && !fraction.nil?
          # Interpreted as time
          hash[:sec]  = digits[-2, 2].to_i
          hash[:min]  = digits[-4, 2].to_i
          hash[:hour] = digits[-6, 2].to_i
          hash[:mday] = digits[-8, 2].to_i
          hash[:mon]  = digits[-10, 2].to_i if l >= 10
          if l == 12
            y = digits[-12, 2].to_i
            y = -y if sign == '-'
            hash[:year] = y
            hash[:_year_str] = digits[-12, 2]
          elsif l == 14
            y = digits[-14, 4].to_i
            y = -y if sign == '-'
            hash[:year] = y
            hash[:_comp] = false
          end
        else
          # Interpret as date
          y = digits[0, 4].to_i
          y = -y if sign == '-'
          hash[:year] = y
          hash[:mon]  = digits[4, 2].to_i
          hash[:mday] = digits[6, 2].to_i
          hash[:hour] = digits[8, 2].to_i if l >= 10
          hash[:min]  = digits[10, 2].to_i if l >= 12
          hash[:sec]  = digits[12, 2].to_i if l >= 14
          hash[:_comp] = false
        end
      when 3
        if time_digits.nil? && !fraction.nil?
          hash[:sec] = digits[-2, 2].to_i
          hash[:min] = digits[-3, 1].to_i
        else
          hash[:yday] = digits[0, 3].to_i
        end
      when 5
        if time_digits.nil? && !fraction.nil?
          hash[:sec]  = digits[-2, 2].to_i
          hash[:min]  = digits[-4, 2].to_i
          hash[:hour] = digits[-5, 1].to_i
        else
          y = digits[0, 2].to_i
          y = -y if sign == '-'
          hash[:year] = y
          hash[:yday] = digits[2, 3].to_i
          hash[:_year_str] = digits[0, 2]
        end
      when 7
        if time_digits.nil? && !fraction.nil?
          hash[:sec]  = digits[-2, 2].to_i
          hash[:min]  = digits[-4, 2].to_i
          hash[:hour] = digits[-6, 2].to_i
          hash[:mday] = digits[-7, 1].to_i
        else
          y = digits[0, 4].to_i
          y = -y if sign == '-'
          hash[:year] = y
          hash[:yday] = digits[4, 3].to_i
          # No need to complete because it is a 4-digit year
        end
      end

      # Processing time portion
      if time_digits && !time_digits.empty?
        tl = time_digits.length
        if !fraction.nil?
          # Interpreted as time
          case tl
          when 2, 4, 6
            hash[:sec]  = time_digits[-2, 2].to_i
            hash[:min]  = time_digits[-4, 2].to_i if tl >= 4
            hash[:hour] = time_digits[-6, 2].to_i if tl >= 6
          end
        else
          # Interpreted as time
          case tl
          when 2, 4, 6
            hash[:hour] = time_digits[0, 2].to_i
            hash[:min]  = time_digits[2, 2].to_i if tl >= 4
            hash[:sec]  = time_digits[4, 2].to_i if tl >= 6
          end
        end
      end

      # Handling fractional seconds
      if fraction && !fraction.empty?
        hash[:sec_fraction] = Rational(fraction.to_i, 10 ** fraction.length)
      end

      # Handling time zone
      if zone && !zone.empty?
        if zone[0] == '['
          # Bracket-enclosed zone: C's parse_ddd_cb special handling.
          # Strip '[' and ']', then check for ':' separator.
          inner = zone[1..-2]  # content between [ and ]
          colon_pos = inner.index(':')
          if colon_pos
            # e.g., "[-5:EST]" → zone_name="EST", offset_str="-5:"
            # C: zone = part after ':', s5 = part from start to after ':'
            zone_name  = inner[(colon_pos + 1)..]
            offset_str = inner[0, colon_pos + 1]  # includes ':'
          else
            # e.g., "[-9]" → zone_name="-9", offset_str="-9"
            # e.g., "[9]"  → zone_name="9",  offset_str="+9" (digit→prepend '+')
            zone_name = inner
            if inner[0] && inner[0] =~ /\d/
              offset_str = "+" + zone_name
            else
              offset_str = zone_name
            end
          end
          hash[:zone]   = zone_name
          hash[:offset] = date_zone_to_diff(offset_str)
        else
          # Non-bracket zone: just set zone.
          # Offset will be resolved in apply_comp if not already set.
          hash[:zone]   = zone
          hash[:offset] = date_zone_to_diff(zone)
        end
      end

      true
    end

    # Parse $1 (time string) further and set hash to hour/min/sec/sec_fraction.
    #
    # Internal pattern:
    #   $1 hour
    #   $2 min (colon format)
    #   $3 sec (colon format)
    #   $4 frac ([,.]\d*)
    #   $5 min (h format)
    #   $6 sec (h format)
    #   $7 am/pm (a or p)
    def parse_time_detail(time_str, hash)
      return unless time_str =~ TIME_DETAIL_PAT

      hour      = $1.to_i
      min_colon = $2
      sec_colon = $3
      frac      = $4   # "[,.] number string" or nil
      min_h     = $5
      sec_h     = $6
      ampm      = $7

      if min_colon
        # Branch A: HH:MM[:SS[.frac]]
        hash[:hour] = hour
        hash[:min]  = min_colon.to_i
        if sec_colon
          hash[:sec] = sec_colon.to_i
          if frac && frac.length > 1
            # Since frac is a "[,.] number string", the first character (delimiter) is omitted.
            frac_digits = frac[1..]
            hash[:sec_fraction] = Rational(frac_digits.to_i, 10 ** frac_digits.length)
          end
        end
      elsif min_h
        # Branch B: HHh[MMm[SSs]](with min)
        hash[:hour] = hour
        hash[:min]  = min_h.to_i
        hash[:sec]  = sec_h.to_i if sec_h
      elsif time_str.match?(/h/i)
        # Branch B: Only HHh (no min/sec)
        hash[:hour] = hour
      elsif ampm
        # Branch C: Only AM/PM => Set only hour (converted to AM/PM below)
        hash[:hour] = hour
      end

      # AM/PM conversion
      if ampm
        h = hash[:hour] || hour
        if ampm.downcase == 'p' && h != 12
          hash[:hour] = h + 12
        elsif ampm.downcase == 'a' && h == 12
          hash[:hour] = 0
        end
      end
    end

    # parse_era in date_parse.c.
    def parse_era(str, hash)
      if str =~ ERA1_PAT
        hash[:bc] = false
        return true
      end

      if str =~ ERA2_PAT
        hash[:bc] = $1.downcase.delete('.') != 'ce'
        return true
      end

      false
    end

    # parse_eu in date_parse.c.
    def parse_eu(str, hash)
      m = subx(str, PARSE_EU_PAT)
      return false unless m

      mday_str = m[1]
      mon_str  = m[2]
      era_str  = m[3]
      year_str = m[4]

      # Determine bc flag from era.
      # AD/A.D./CE/C.E. => false, BC/B.C./BCE/B.C.E. => true
      bc = if era_str
             era_str.downcase.delete('.') !~ /\A(ad|ce)\z/
           else
             false
           end

      # Normalize y/m/d and set to hash in s3e.
      # 'mon' is converted to an Integer using 'mon_num' and then passed.
      s3e(hash, year_str, mon_num(mon_str), mday_str, bc)

      true
    end

    # parse_us in date_parse.c.
    def parse_us(str, hash)
      m = subx(str, PARSE_US_PAT)
      return false unless m

      mon_str  = m[1]
      mday_str = m[2]
      era_str  = m[3]
      year_str = m[4]

      # Determine bc flag from era (same logic as parse_eu).
      bc = if era_str
             era_str.downcase.delete('.') !~ /\A(ad|ce)\z/
           else
             false
           end

      # Normalize y/m/d and set to hash using s3e.
      # Difference from parse_eu: mon=$1, mday=$2 (only the $ numbers are swapped).
      s3e(hash, year_str, mon_num(mon_str), mday_str, bc)

      true
    end

    # parse_iso in date_parse.c
    def parse_iso(str, hash)
      m = subx(str, PARSE_ISO_PAT)
      return false unless m

      # Normalize y/m/d and set to hash in s3e.
      # bc is always false (there is no era symbol in ISO format).
      s3e(hash, m[1], m[2], m[3], false)

      true
    end

    # parse_iso2 in date_parse.c
    def parse_iso2(str, hash)
      return true if parse_iso21(str, hash)
      return true if parse_iso22(str, hash)
      return true if parse_iso23(str, hash)
      return true if parse_iso24(str, hash)
      return true if parse_iso25(str, hash)
      return true if parse_iso26(str, hash)

      false
    end

    def parse_iso21(str, hash)
      m = subx(str, PARSE_ISO21_PAT)
      return false unless m

      hash[:cwyear] = m[1].to_i if m[1]
      hash[:cweek]  = m[2].to_i
      hash[:cwday]  = m[3].to_i if m[3]

      true
    end

    def parse_iso22(str, hash)
      m = subx(str, PARSE_ISO22_PAT)
      return false unless m

      hash[:cwday] = m[1].to_i

      true
    end

    def parse_iso23(str, hash)
      m = subx(str, PARSE_ISO23_PAT)
      return false unless m

      hash[:mon]  = m[1].to_i if m[1]
      hash[:mday] = m[2].to_i

      true
    end

    def parse_iso24(str, hash)
      m = subx(str, PARSE_ISO24_PAT)
      return false unless m

      hash[:mon]  = m[1].to_i
      hash[:mday] = m[2].to_i if m[2]

      true
    end

    def parse_iso25(str, hash)
      # Skip if exclude pattern matches (uses match, not subx).
      return false if str =~ PARSE_ISO25_PAT0

      m = subx(str, PARSE_ISO25_PAT)
      return false unless m

      hash[:year] = m[1].to_i
      hash[:yday] = m[2].to_i

      true
    end

    def parse_iso26(str, hash)
      # Skip if exclude pattern matches (uses match, not subx).
      return false if str =~ PARSE_ISO26_PAT0

      m = subx(str, PARSE_ISO26_PAT)
      return false unless m

      hash[:yday] = m[1].to_i

      true
    end

    # parse_jis in date_parse.c
    def parse_jis(str, hash)
      m = subx(str, PARSE_JIS_PAT)
      return false unless m

      era  = m[1].upcase
      year = m[2].to_i
      mon  = m[3].to_i
      mday = m[4].to_i

      # Convert the era symbol and year number to Gregorian calendar
      # and set it to hash.
      hash[:year] = gengo(era) + year
      hash[:mon]  = mon
      hash[:mday] = mday

      true
    end

    # parse_vms in date_parse.c
    def parse_vms(str, hash)
      return true if parse_vms11(str, hash)
      return true if parse_vms12(str, hash)

      false
    end

    def parse_vms11(str, hash)
      m = subx(str, PARSE_VMS11_PAT)
      return false unless m

      mday_str = m[1]
      mon_str  = m[2]
      year_str = m[3]

      # Normalize y/m/d and set to hash in s3e.
      s3e(hash, year_str, mon_num(mon_str), mday_str, false)

      true
    end

    def parse_vms12(str, hash)
      m = subx(str, PARSE_VMS12_PAT)
      return false unless m

      mon_str  = m[1]
      mday_str = m[2]
      year_str = m[3]

      # Normalize y/m/d and set to hash in s3e.
      s3e(hash, year_str, mon_num(mon_str), mday_str, false)

      true
    end

    # parse_sla in date_parse.c
    def parse_sla(str, hash)
      m = subx(str, PARSE_SLA_PAT)
      return false unless m

      # Normalize y/m/d and set to hash in s3e.
      # bc is always false.
      s3e(hash, m[1], m[2], m[3], false)

      true
    end

    # parse_dot in date_parse.c
    def parse_dot(str, hash)
      m = subx(str, PARSE_DOT_PAT)
      return false unless m

      # Normalize y/m/d and set to hash in s3e.
      # bc is always false.
      s3e(hash, m[1], m[2], m[3], false)

      true
    end

    # parse_year in date_parse.c
    def parse_year(str, hash)
      m = subx(str, PARSE_YEAR_PAT)
      return false unless m

      hash[:year] = m[1].to_i

      true
    end

    # parse_mon in date_parse.c
    def parse_mon(str, hash)
      m = subx(str, PARSE_MON_PAT)
      return false unless m

      hash[:mon] = mon_num(m[1])

      true
    end

    # parse_mday in date_parse.c
    def parse_mday(str, hash)
      m = subx(str, PARSE_MDAY_PAT)
      return false unless m

      hash[:mday] = m[1].to_i

      true
    end

    # parse_bc in date_parse.c (non-TIGHT post-processing).
    # Matches standalone BC/BCE/B.C./B.C.E. and sets _bc flag.
    def parse_bc(str, hash)
      m = subx(str, PARSE_BC_PAT)
      return false unless m

      hash[:_bc] = true

      true
    end

    # parse_frag in date_parse.c (non-TIGHT post-processing).
    # If the remaining string (after all other parsers have consumed
    # their portions) is a standalone 1-2 digit number:
    #   - If we have hour but no mday, and the number is 1-31, set mday
    #   - If we have mday but no hour, and the number is 0-24, set hour
    def parse_frag(str, hash)
      m = subx(str, PARSE_FRAG_PAT)
      return false unless m

      n = m[1].to_i

      if hash.key?(:hour) && !hash.key?(:mday)
        hash[:mday] = n if n >= 1 && n <= 31
      end
      if hash.key?(:mday) && !hash.key?(:hour)
        hash[:hour] = n if n >= 0 && n <= 24
      end

      true
    end

    # Helper: Convert day name to number (0=Sunday, 6=Saturday)
    def day_num(day_name)
      abbr_days = %w[sun mon tue wed thu fri sat]
      abbr_days.index(day_name[0, 3].downcase) || 0
    end

    # Helper: Convert month name to number (1=January, 12=December)
    def mon_num(month_name)
      abbr_months = %w[jan feb mar apr may jun jul aug sep oct nov dec]
      (abbr_months.index(month_name[0, 3].downcase) || 0) + 1
    end

    # ISO 8601 extended datetime: 2001-02-03T04:05:06+09:00
    def iso8601_ext_datetime(str, hash)
      pattern = /\A\s*
        (?:
          ([-+]?\d{2,}|-)-(\d{2})?(?:-(\d{2}))?|      # YYYY-MM-DD or --MM-DD
          ([-+]?\d{2,})?-(\d{3})|                     # YYYY-DDD
          (\d{4}|\d{2})?-w(\d{2})-(\d)|               # YYYY-Www-D
          -w-(\d)                                     # -W-D
        )
        (?:t
          (\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?  # HH:MM:SS.fraction
          (z|[-+]\d{2}(?::?\d{2})?)?                  # timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      return false unless match

      # Calendar date (YYYY-MM-DD)
      if match[1]
        unless match[1] == '-'
          year = match[1].to_i
          # Complete 2-digit year
          year = comp_year69(year) if match[1].length < 4
          hash[:year] = year
        end
        hash[:mon] = match[2].to_i if match[2]
        hash[:mday] = match[3].to_i if match[3]
      # Ordinal date (YYYY-DDD)
      elsif match[5]
        if match[4]
          year = match[4].to_i
          year = comp_year69(year) if match[4].length < 4
          hash[:year] = year
        end
        hash[:yday] = match[5].to_i
      # Week date (YYYY-Www-D)
      elsif match[8]
        if match[6]
          year = match[6].to_i
          year = comp_year69(year) if match[6].length < 4
          hash[:cwyear] = year
        end
        hash[:cweek] = match[7].to_i
        hash[:cwday] = match[8].to_i
      # Week day only (-W-D)
      elsif match[9]
        hash[:cwday] = match[9].to_i
      end

      # Time
      if match[10]
        hash[:hour] = match[10].to_i
        hash[:min] = match[11].to_i
        hash[:sec] = match[12].to_i if match[12]
        hash[:sec_fraction] = parse_fraction(match[13]) if match[13]
      end

      # Timezone
      if match[14]
        hash[:zone] = match[14]
        hash[:offset] = parse_zone_offset(match[14])
      end

      true
    end

    # ISO 8601 basic datetime: 20010203T040506
    def iso8601_bas_datetime(str, hash)
      # Try full basic datetime: YYYYMMDD or YYMMDD
      pattern = /\A\s*
        ([-+]?(?:\d{4}|\d{2})|--)  # Year (YYYY, YY, --, or signed)
        (\d{2}|-)                  # Month (MM or -)
        (\d{2})                    # Day (DD)
        (?:t?
          (\d{2})(\d{2})           # Hour and minute (HHMM)
          (?:(\d{2})               # Second (SS)
            (?:[,.](\d+))?         # Fraction
          )?
          (z|[-+]\d{2}(?:\d{2})?)? # Timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      if match
        # Calendar date
        unless match[1] == '--'
          year = match[1].to_i
          year = comp_year69(year) if match[1].length == 2 && match[1] !~ /^[-+]/
          hash[:year] = year
        end
        hash[:mon] = match[2].to_i unless match[2] == '-'
        hash[:mday] = match[3].to_i

        # Time
        if match[4]
          hash[:hour] = match[4].to_i
          hash[:min] = match[5].to_i
          hash[:sec] = match[6].to_i if match[6]
          hash[:sec_fraction] = parse_fraction(match[7]) if match[7]
        end

        # Timezone
        if match[8]
          hash[:zone] = match[8]
          hash[:offset] = parse_zone_offset(match[8])
        end

        return true
      end

      # Try ordinal date: YYYYDDD or YYDDD
      pattern = /\A\s*
        ([-+]?(?:\d{4}|\d{2}))      # Year
        (\d{3})                     # Day of year
        (?:t?
          (\d{2})(\d{2})            # Hour and minute
          (?:(\d{2})                # Second
            (?:[,.](\d+))?          # Fraction
          )?
          (z|[-+]\d{2}(?:\d{2})?)?  # Timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      if match
        year = match[1].to_i
        year = comp_year69(year) if match[1].length == 2 && match[1] !~ /^[-+]/
        hash[:year] = year
        hash[:yday] = match[2].to_i

        # Time
        if match[3]
          hash[:hour] = match[3].to_i
          hash[:min] = match[4].to_i
          hash[:sec] = match[5].to_i if match[5]
          hash[:sec_fraction] = parse_fraction(match[6]) if match[6]
        end

        # Timezone
        if match[7]
          hash[:zone] = match[7]
          hash[:offset] = parse_zone_offset(match[7])
        end

        return true
      end

      # Try -DDD (ordinal without year)
      pattern = /\A\s*
        -(\d{3})                 # Day of year
        (?:t?
          (\d{2})(\d{2})         # Hour and minute
          (?:(\d{2})             # Second
            (?:[,.](\d+))?       # Fraction
          )?
          (z|[-+]\d{2}(?:\d{2})?)?  # Timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      if match
        hash[:yday] = match[1].to_i

        # Time
        if match[2]
          hash[:hour] = match[2].to_i
          hash[:min] = match[3].to_i
          hash[:sec] = match[4].to_i if match[4]
          hash[:sec_fraction] = parse_fraction(match[5]) if match[5]
        end

        # Timezone
        if match[6]
          hash[:zone] = match[6]
          hash[:offset] = parse_zone_offset(match[6])
        end

        return true
      end

      # Try week date: YYYYWwwD or YYWwwD
      pattern = /\A\s*
        (\d{4}|\d{2})            # Year
        w(\d{2})                 # Week
        (\d)                     # Day of week
        (?:t?
          (\d{2})(\d{2})         # Hour and minute
          (?:(\d{2})             # Second
            (?:[,.](\d+))?       # Fraction
          )?
          (z|[-+]\d{2}(?:\d{2})?)?  # Timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      if match
        year = match[1].to_i
        year = comp_year69(year) if match[1].length == 2
        hash[:cwyear] = year
        hash[:cweek] = match[2].to_i
        hash[:cwday] = match[3].to_i

        # Time
        if match[4]
          hash[:hour] = match[4].to_i
          hash[:min] = match[5].to_i
          hash[:sec] = match[6].to_i if match[6]
          hash[:sec_fraction] = parse_fraction(match[7]) if match[7]
        end

        # Timezone
        if match[8]
          hash[:zone] = match[8]
          hash[:offset] = parse_zone_offset(match[8])
        end

        return true
      end

      # Try -WwwD (week date without year)
      pattern = /\A\s*
        -w(\d{2})                # Week
        (\d)                     # Day of week
        (?:t?
          (\d{2})(\d{2})         # Hour and minute
          (?:(\d{2})             # Second
            (?:[,.](\d+))?       # Fraction
          )?
          (z|[-+]\d{2}(?:\d{2})?)?  # Timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      if match
        hash[:cweek] = match[1].to_i
        hash[:cwday] = match[2].to_i

        # Time
        if match[3]
          hash[:hour] = match[3].to_i
          hash[:min] = match[4].to_i
          hash[:sec] = match[5].to_i if match[5]
          hash[:sec_fraction] = parse_fraction(match[6]) if match[6]
        end

        # Timezone
        if match[7]
          hash[:zone] = match[7]
          hash[:offset] = parse_zone_offset(match[7])
        end

        return true
      end

      # Try -W-D (day of week only)
      pattern = /\A\s*
        -w-(\d)                  # Day of week
        (?:t?
          (\d{2})(\d{2})         # Hour and minute
          (?:(\d{2})             # Second
            (?:[,.](\d+))?       # Fraction
          )?
          (z|[-+]\d{2}(?:\d{2})?)?  # Timezone
        )?
      \s*\z/ix

      match = pattern.match(str)
      if match
        hash[:cwday] = match[1].to_i

        # Time
        if match[2]
          hash[:hour] = match[2].to_i
          hash[:min] = match[3].to_i
          hash[:sec] = match[4].to_i if match[4]
          hash[:sec_fraction] = parse_fraction(match[5]) if match[5]
        end

        # Timezone
        if match[6]
          hash[:zone] = match[6]
          hash[:offset] = parse_zone_offset(match[6])
        end

        return true
      end

      false
    end

    # ISO 8601 extended time: 04:05:06+09:00
    def iso8601_ext_time(str, hash)
      # Pattern: HH:MM:SS.fraction or HH:MM:SS,fraction
      pattern = /\A\s*(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?(z|[-+]\d{2}(?::?\d{2})?)?\s*\z/ix

      match = pattern.match(str)
      return false unless match

      hash[:hour] = match[1].to_i
      hash[:min] = match[2].to_i
      hash[:sec] = match[3].to_i if match[3]
      hash[:sec_fraction] = parse_fraction(match[4]) if match[4]

      if match[5]
        hash[:zone] = match[5]
        hash[:offset] = parse_zone_offset(match[5])
      end

      true
    end

    # ISO 8601 basic time: 040506
    def iso8601_bas_time(str, hash)
      # Pattern: HHMMSS.fraction or HHMMSS,fraction
      pattern = /\A\s*(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?)?(z|[-+]\d{2}(?:\d{2})?)?\s*\z/ix

      match = pattern.match(str)
      return false unless match

      hash[:hour] = match[1].to_i
      hash[:min] = match[2].to_i
      hash[:sec] = match[3].to_i if match[3]
      hash[:sec_fraction] = parse_fraction(match[4]) if match[4]

      if match[5]
        hash[:zone] = match[5]
        hash[:offset] = parse_zone_offset(match[5])
      end

      true
    end

    # Parse fractional seconds
    def parse_fraction(frac_str)
      return nil unless frac_str
      Rational(frac_str.to_i, 10 ** frac_str.length)
    end

    # Parse timezone offset (Z, +09:00, -0500, etc.)
    def parse_zone_offset(zone_str)
      return nil if zone_str.nil? || zone_str.empty?

      zone = zone_str.strip

      # Handle [+9] or [-9] or [9 ] format (brackets around offset)
      if zone =~ /^\[(.*)\]$/
        zone = $1.strip
      end

      # Handle Z (UTC)
      return 0 if zone.upcase == 'Z'

      # Handle unsigned numeric offset: 9, 09 (assume positive)
      if zone =~ /^(\d{1,2})$/
        hours = $1.to_i
        return hours * HOUR_IN_SECONDS
      end

      # Handle simple numeric offsets with sign: +9, -9, +09, -05, etc.
      if zone =~ /^([-+])(\d{1,2})$/
        sign = $1 == '-' ? -1 : 1
        hours = $2.to_i
        return sign * (hours * HOUR_IN_SECONDS)
      end

      # Handle +09:00, -05:30 format (with colon)
      if zone =~ /^([-+])(\d{2}):(\d{2})$/
        sign = $1 == '-' ? -1 : 1
        hours = $2.to_i
        minutes = $3.to_i
        return sign * (hours * HOUR_IN_SECONDS + minutes * MINUTE_IN_SECONDS)
      end

      # Handle +0900, -0500 format (4 digits, no colon)
      if zone =~ /^([-+])(\d{4})$/
        sign = $1 == '-' ? -1 : 1
        hours = $2[0, 2].to_i
        minutes = $2[2, 2].to_i
        return sign * (hours * HOUR_IN_SECONDS + minutes * MINUTE_IN_SECONDS)
      end

      # Handle +0900 format (4 digits without colon)
      if zone =~ /^([-+])(\d{4})$/
        sign = $1 == '-' ? -1 : 1
        hours = $2[0, 2].to_i
        minutes = $2[2, 2].to_i
        return sign * (hours * HOUR_IN_SECONDS + minutes * MINUTE_IN_SECONDS)
      end

      # Handle fractional hours: +9.5, -5.5
      if zone =~ /^([-+])(\d+)[.,](\d+)$/
        sign = $1 == '-' ? -1 : 1
        hours = $2.to_i
        fraction = "0.#{$3}".to_f
        return sign * ((hours + fraction) * HOUR_IN_SECONDS).to_i
      end

      # Handle GMT+9, GMT-5, etc.
      if zone =~ /^(?:gmt|utc)?([-+])(\d{1,2})(?::?(\d{2}))?(?::?(\d{2}))?$/i
        sign = $1 == '-' ? -1 : 1
        hours = $2.to_i
        minutes = $3 ? $3.to_i : 0
        seconds = $4 ? $4.to_i : 0
        return sign * (hours * HOUR_IN_SECONDS + minutes * MINUTE_IN_SECONDS + seconds)
      end

      # Known timezone abbreviations
      zone_offsets = {
        'JST' => 9 * HOUR_IN_SECONDS,
        'GMT' => 0,
        'UTC' => 0,
        'UT' => 0,
        'EST' => -5 * HOUR_IN_SECONDS,
        'EDT' => -4 * HOUR_IN_SECONDS,
        'CST' => -6 * HOUR_IN_SECONDS,
        'CDT' => -5 * HOUR_IN_SECONDS,
        'MST' => -7 * HOUR_IN_SECONDS,
        'MDT' => -6 * HOUR_IN_SECONDS,
        'PST' => -8 * HOUR_IN_SECONDS,
        'PDT' => -7 * HOUR_IN_SECONDS,
        'AEST' => 10 * HOUR_IN_SECONDS,
        'MET DST' => 2 * HOUR_IN_SECONDS,
        'GMT STANDARD TIME' => 0,
        'MOUNTAIN STANDARD TIME' => -7 * HOUR_IN_SECONDS,
        'MOUNTAIN DAYLIGHT TIME' => -6 * HOUR_IN_SECONDS,
        'MEXICO STANDARD TIME' => -6 * HOUR_IN_SECONDS,
        'E. AUSTRALIA STANDARD TIME' => 10 * HOUR_IN_SECONDS,
        'W. CENTRAL AFRICA STANDARD TIME' => 1 * HOUR_IN_SECONDS,
      }

      # Handle military timezones (single letters A-Z except J)
      if zone =~ /^([A-Z])$/i
        letter = zone.upcase
        return 0 if letter == 'Z'
        return nil if letter == 'J'  # J is not used

        if letter <= 'I'
          # A-I: +1 to +9
          offset = letter.ord - 'A'.ord + 1
        elsif letter >= 'K' && letter <= 'M'
          # K-M: +10 to +12 (skip J)
          offset = letter.ord - 'A'.ord  # K is 10th letter (ord-'A'=10)
        elsif letter >= 'N' && letter <= 'Y'
          # N-Y: -1 to -12
          offset = -(letter.ord - 'N'.ord + 1)
        else
          return nil
        end

        return offset * HOUR_IN_SECONDS
      end

      # Normalize zone string for lookup
      zone_upper = zone.gsub(/\s+/, ' ').upcase
      zone_offsets[zone_upper]
    end

    # JIS X 0301 format: H13.02.03 or H13.02.03T04:05:06
    def parse_jisx0301_fmt(str, hash)
      # Pattern: [Era]YY.MM.DD[T]HH:MM:SS[.fraction][timezone]
      # Era initials: M, T, S, H, R (or none for ISO 8601 fallback)
      pattern = /\A\s*
        ([#{JISX0301_ERA_INITIALS}])?  # Era (optional)
        (\d{2})\.(\d{2})\.(\d{2})      # YY.MM.DD
        (?:t                            # Time separator (optional)
          (?:
            (\d{2}):(\d{2})             # HH:MM
            (?::(\d{2})                 # :SS (optional)
              (?:[,.](\d*))?            # .fraction (optional)
            )?
            (z|[-+]\d{2}(?::?\d{2})?)?  # timezone (optional)
          )?
        )?
      \s*\z/ix

      match = pattern.match(str)
      return false unless match

      # Parse era and year
      era_char = match[1] ? match[1].upcase : JISX0301_DEFAULT_ERA
      era_year = match[2].to_i

      # Convert era year to gregorian year
      era_start = gengo(era_char)
      hash[:year] = era_start + era_year

      # Parse month and day
      hash[:mon] = match[3].to_i
      hash[:mday] = match[4].to_i

      # Parse time (if present)
      if match[5]
        hash[:hour] = match[5].to_i
        hash[:min] = match[6].to_i if match[6]
        hash[:sec] = match[7].to_i if match[7]
        hash[:sec_fraction] = parse_fraction(match[8]) if match[8]
      end

      # Parse timezone (if present)
      if match[9]
        hash[:zone] = match[9]
        hash[:offset] = parse_zone_offset(match[9])
      end

      true
    end

    # Convert era character to year offset
    def gengo(era_char)
      case era_char.upcase
      when 'M' then 1867  # Meiji
      when 'T' then 1911  # Taisho
      when 'S' then 1925  # Showa
      when 'H' then 1988  # Heisei
      when 'R' then 2018  # Reiwa
      else 0
      end
    end

    # Post-processing: matches C's date__parse post-processing after ok: label.
    #
    # 1. _bc handling: negate year and cwyear (year = 1 - year)
    # 2. _comp handling: complete 2-digit year/cwyear to 4-digit (69-99 → 1900s, 0-68 → 2000s)
    # 3. zone → offset conversion
    # 4. Clean up internal keys
    def apply_comp(hash)
      # _bc: del_hash("_bc") — read and delete
      bc = hash.delete(:_bc)
      if bc
        if hash.key?(:cwyear)
          hash[:cwyear] = 1 - hash[:cwyear]
        end
        if hash.key?(:year)
          hash[:year] = 1 - hash[:year]
        end
      end

      # _comp: del_hash("_comp") — read and delete
      comp = hash.delete(:_comp)
      if comp
        if hash.key?(:cwyear)
          y = hash[:cwyear]
          if y >= 0 && y <= 99
            hash[:cwyear] = y >= 69 ? y + 1900 : y + 2000
          end
        end
        if hash.key?(:year)
          y = hash[:year]
          if y >= 0 && y <= 99
            hash[:year] = y >= 69 ? y + 1900 : y + 2000
          end
        end
      end

      # zone → offset conversion
      if hash.key?(:zone) && !hash.key?(:offset)
        hash[:offset] = date_zone_to_diff(hash[:zone])
      end

      # Clean up internal keys
      hash.delete(:_year_str)
    end

    # s3e in date_parse.c.
    # y, m, and d are Strings or nil. m can also be an Integer (convert with to_s).
    # bc is a Boolean.
    #
    # This method normalizes the year, mon, and mday from the combination of y, m, and
    # d and writes them to a hash.
    # The sorting logic operates in the following order of priority:
    #
    #   Phase 1: Argument rotation and promotion
    #     - y and m are available, but d is nil => Rotate because it is a pair (mon, mday)
    #     - y is nil and d is long (>2 digits) or starts with an apostrophe => Promote d to y
    #     - If y has a leading character other than a digit, extract only the numeric portion, and if there is a remainder, add it to d
    #
    #   Phase 2: Sort m and d
    #     - m starts with an apostrophe or its length is >2 => US->BE sort (y,m,d)=(m,d,y)
    #     - d starts with an apostrophe or its length is >2 => Swap (y,d)
    #
    #   Phase 3: Write to hash
    #     - Extract the sign and digits from y and set them to year
    #       If signed or the number of digits is >2, write _comp = false
    #     - Extract the number from m and set it to mon
    #     - Extract the number from d and set it to mday
    #     - If bc is true, write _bc = true
    def s3e(hash, y, m, d, bc)
      # Candidates for _comp. If nil, do not write.
      c = nil

      # If m is not a string, use to_s (parse_eu/parse_us passes the Integer returned by mon_num)
      m = m.to_s unless m.nil? || m.is_a?(String)

      # ----------------------------------------------------------
      # Phase 1: Argument reordering
      # ----------------------------------------------------------

      # If we have y and m, but d is nil, it's actually a (mon, mday) pair, so we rotate it.
      #   (y, m, d) = (nil, y, m)
      if !y.nil? && !m.nil? && d.nil?
        y, m, d = nil, y, m
      end

      # If y is nil and d exists, if d is long or begins with an apostrophe, it is promoted to y
      if y.nil?
        if !d.nil? && d.length > 2
          y = d
          d = nil
        end
        if !d.nil? && d.length > 0 && d[0] == "'"
          y = d
          d = nil
        end
      end

      # If y has a leading character other than a sign or a number, skip it and
      # extract only the numeric part. If there are any characters remaining after
      # the extracted numeric string, swap y and d, and set the numeric part to d.
      unless y.nil?
        pos = 0
        pos += 1 while pos < y.length && !issign?(y[pos]) && !y[pos].match?(/\d/)

        unless pos >= y.length  # no_date
          bp = pos
          pos += 1 if pos < y.length && issign?(y[pos])
          span = digit_span(y[pos..])
          ep = pos + span

          if ep < y.length
            # There is a letter after the number string => exchange (y, d)
            y, d = d, y[bp...ep]
          end
        end
      end

      # ----------------------------------------------------------
      # Phase 2: Rearrange m and d
      # ----------------------------------------------------------

      # m starts with an apostrophe or length > 2 => US => BE sort
      #   (y, m, d) = (m, d, y)
      if !m.nil? && (m[0] == "'" || m.length > 2)
        y, m, d = m, d, y
      end

      # d begins with an apostrophe or length > 2 => exchange (y, d)
      if !d.nil? && (d[0] == "'" || d.length > 2)
        y, d = d, y
      end

      # ----------------------------------------------------------
      # Phase 3: Write to hash
      # ----------------------------------------------------------

      # year: Extract the sign and digit from y and set
      unless y.nil?
        pos = 0
        pos += 1 while pos < y.length && !issign?(y[pos]) && !y[pos].match?(/\d/)

        unless pos >= y.length  # no_year
          bp = pos
          sign = false
          if pos < y.length && issign?(y[pos])
            sign = true
            pos += 1
          end

          c = false if sign                       # Signed => _comp = false
          span = digit_span(y[pos..])
          c = false if span > 2                   # Number of digits > 2 => _comp = false

          num_str = y[bp, (pos - bp) + span]      # sign + number part
          hash[:year] = num_str.to_i
        end
      end

      hash[:_bc] = true if bc

      # mon: Extract and set a number from m
      unless m.nil?
        pos = 0
        pos += 1 while pos < m.length && !m[pos].match?(/\d/)

        unless pos >= m.length  # no_month
          span = digit_span(m[pos..])
          hash[:mon] = m[pos, span].to_i
        end
      end

      # mday: Extract and set numbers from d
      unless d.nil?
        pos = 0
        pos += 1 while pos < d.length && !d[pos].match?(/\d/)

        unless pos >= d.length  # no_mday
          span = digit_span(d[pos..])
          hash[:mday] = d[pos, span].to_i
        end
      end

      # _comp is written only if it is explicitly false
      hash[:_comp] = false unless c.nil?
    end

    # issign macro in date_parse.c.
    def issign?(c)
      c == '-' || c == '+'
    end

    # digit_span in date_parse.c.
    # Returns the length of the first consecutive digit in the string 's'.
    def digit_span(s)
      i = 0
      i += 1 while i < s.length && s[i].match?(/\d/)

      i
    end

    # date_zone_to_diff in date_parse.c.
    # Returns the number of seconds since UTC from a time zone name or offset string.
    # Returns nil if no match occurs.
    #
    # Supported input types:
    #   1. Zone names: "EST", "JST", "Eastern", "Central Pacific", ...
    #   2. Suffixes: "Eastern standard time", "EST dst", ...
    #        "standard time" => As is
    #        "daylight time" / "dst" => Set offset to +3600
    #   3. Numeric offset: "+09:00", "-0530", "+9", "GMT+09:00", ...
    #   4. Fractional time offset: "+9.5" (=+09:30), "+5.50" (=+05:30), ...
    def date_zone_to_diff(str)
      return nil if str.nil? || str.empty?

      s = str.dup
      dst = false

      # Suffix removal: "time", "standard", "daylight", "dst"
      w = str_end_with_word(s, "time")
      if w > 0
        s = s[0, s.length - w]

        w2 = str_end_with_word(s, "standard")
        if w2 > 0
          s = s[0, s.length - w2]
        else
          w2 = str_end_with_word(s, "daylight")
          if w2 > 0
            s = s[0, s.length - w2]
            dst = true
          else
            # "time" alone is not enough, so return
            s = str.dup
          end
        end
      else
        w = str_end_with_word(s, "dst")
        if w > 0
          s = s[0, s.length - w]
          dst = true
        end
      end

      # --- zonetab search ---
      # Normalize consecutive spaces into a single space before searching
      zn = shrink_space(s)
      z_offset = ZONE_TABLE[zn.downcase]

      if z_offset
        z_offset += 3600 if dst
        return z_offset
      end

      # --- Parse numeric offsets ---
      # Remove "GMT" and "UTC" prefixes
      if zn.length > 3 && zn[0, 3].downcase =~ /\A(gmt|utc)\z/
        zn = zn[3..]
      end

      # If there is no sign, it is not treated as a numeric offset
      return nil if zn.empty? || (zn[0] != '+' && zn[0] != '-')

      sign  = zn[0] == '-' ? -1 : 1
      zn    = zn[1..]
      return nil if zn.empty?

      # ':' separator: HH:MM or HH:MM:SS
      if zn.include?(':')
        return parse_colon_offset(zn, sign)
      end

      # '.' or ',' separator: HH.fraction
      if zn.include?('.') || zn.include?(',')
        return parse_fractional_offset(zn, sign)
      end

      # Others: HH or HHMM or HHMMSS
      parse_compact_offset(zn, sign)
    end

    # str_end_with_word in date_parse.c.
    # If the string 's' ends with "<word>" (a word plus a space),
    # Returns the length of that "<word>" (including leading spaces).
    # Otherwise, returns 0.
    def str_end_with_word(s, word)
      n = word.length
      return 0 if s.length <= n

      # The last n characters match word (ignoring case)
      return 0 unless s[-n..].casecmp?(word)

      # Is there a space just before it?
      return 0 unless s[-(n + 1)].match?(/\s/)

      # Include consecutive spaces
      count = n + 1
      count += 1 while count < s.length && s[-(count + 1)].match?(/\s/)

      count
    end

    # shrink_space in date_parse.c.
    # Combines consecutive spaces into a single space.
    # If the length is the same as the original (normalization unnecessary),
    # return it as is.
    def shrink_space(s)
      result = []
      prev_space = false
      s.each_char do |ch|
        if ch.match?(/\s/)
          result << ' ' unless prev_space
          prev_space = true
        else
          result << ch
          prev_space = false
        end
      end
      result.join
    end

    # parse_colon_offset
    # Parse "+HH:MM" or "+HH:MM:SS" and return the number of seconds.
    # Range checking: hour 0-23, min 0-59, sec 0-59
    def parse_colon_offset(zn, sign)
      parts = zn.split(':')
      hour = parts[0].to_i
      return nil if hour < 0 || hour > 23

      min = parts.length > 1 ? parts[1].to_i : 0
      return nil if min < 0 || min > 59

      sec = parts.length > 2 ? parts[2].to_i : 0
      return nil if sec < 0 || sec > 59

      sign * (sec + min * 60 + hour * 3600)
    end

    # Parse "+HH.fraction" or "+HH,fraction" and return the number of seconds.
    #
    # C logic:
    #   Read the fraction string up to 7 digits.
    #   sec = (read value) * 36
    #   If n <= 2:
    #     If n == 1, sec *= 10 (treat HH.n as HH.n0)
    #     Return value = sec + hour * 3600 (Integer)
    #   If n > 2:
    #     Return value = Rational(sec, 10**(n-2)) + hour * 3600
    #     Convert to an Integer if the denominator is 1.
    #
    # Reason for the 36 factor:
    #   1 hour = 3600 seconds. Each decimal point is 1/10. Time = 360 seconds.
    #   However, since the implementation handles it in two-digit units, multiply
    #   by 36 before dividing by 10^2.
    #   (3600 / 100 = 36)
    def parse_fractional_offset(zn, sign)
      sep = zn.include?('.') ? '.' : ','
      hh_str, frac_str = zn.split(sep, 2)
      hour = hh_str.to_i
      return nil if hour < 0 || hour > 23

      # Up to 7 digits (C: "no over precision for offset")
      max_digits = 7
      frac_str = frac_str[0, max_digits]
      n = frac_str.length
      return sign * (hour * 3600) if n == 0

      sec = frac_str.to_i * 36  # Convert to seconds by factor 36

      if sign == -1
        hour = -hour
        sec  = -sec
      end

      if n <= 2
        sec *= 10 if n == 1   # HH.n => HH.n0
        sec + hour * 3600
      else
        # Rational for precise calculations
        denom  = 10 ** (n - 2)
        offset = Rational(sec, denom) + (hour * 3600)
        offset.denominator == 1 ? offset.to_i : offset
      end
    end

    # parse_compact_offset
    # Parse consecutive numeric offsets without colons.
    #   HH     (2 digits or less)
    #   HHM    (3 digits: 1 digit for hour, 2 digits for min)
    #   HHMM   (4 digits)
    #   HHMMM  (5 digits: 2 digits for hour, 2 digits for min, 1 digit for sec) ... Rare in practical use
    #   HHMMSS (6 digits)
    #
    # C adjusts the leading padding width with "2 - l % 2".
    # Ruby does the same calculation with length.
    def parse_compact_offset(zn, sign)
      l = zn.length

      # Only HH
      return sign * zn.to_i * 3600 if l <= 2

      # C: hour = scan_digits(&s[0], 2 - l % 2)
      #    min  = scan_digits(&s[2 - l % 2], 2)
      #    sec  = scan_digits(&s[4 - l % 2], 2)
      #
      #   l=3 => hw=1 => hour=zn[0,1], min=zn[1,2]
      #   l=4 => hw=2 => hour=zn[0,2], min=zn[2,2]
      #   l=5 => hw=1 => hour=zn[0,1], min=zn[1,2], sec=zn[3,2]
      #   l=6 => hw=2 => hour=zn[0,2], min=zn[2,2], sec=zn[4,2]
      hw   = 2 - l % 2   # hour width: 2 for even, 1 for odd
      hour = zn[0, hw].to_i
      min  = l >= 3 ? zn[hw, 2].to_i : 0
      sec  = l >= 5 ? zn[hw + 2, 2].to_i : 0

      sign * (sec + min * 60 + hour * 3600)
    end

    # subx in date_parse.c.
    # Matches pat against str. If it matches, replaces the matched
    # portion of str (in-place) with rep (default: " ") and returns
    # the MatchData. Returns nil on no match.
    #
    # This is the core mechanism C uses (via the SUBS macro) to
    # prevent later parsers from re-matching already-consumed text.
    def subx(str, pat, rep = " ")
      m = pat.match(str)
      return nil unless m

      str[m.begin(0), m.end(0) - m.begin(0)] = rep
      m
    end

    def check_class(str)
      flags = 0
      str.each_char do |c|
        flags |= HAVE_ALPHA if c =~ /[a-zA-Z]/
        flags |= HAVE_DIGIT if c =~ /\d/
        flags |= HAVE_DASH  if c == '-'
        flags |= HAVE_DOT   if c == '.'
        flags |= HAVE_SLASH if c == '/'
      end

      flags
    end

    # C macro HAVE_ELEM_P(x) in date_parse.c.
    # Note: C calls check_class(str) every time because str is
    # modified by subx. We do the same here.
    def have_elem_p?(str, required)
      (check_class(str) & required) == required
    end

    # --- String type conversion (C's StringValue macro) ---
    def string_value(str)
      return str if str.is_a?(String)
      if str.respond_to?(:to_str)
        s = str.to_str
        raise TypeError, "can't convert #{str.class} to String (#{str.class}#to_str gives #{s.class})" unless s.is_a?(String)
        return s
      end
      raise TypeError, "no implicit conversion of #{str.class} into String"
    end

    def check_string_limit(str, limit)
      if limit && str.length > limit
        raise ArgumentError, "string length (#{str.length}) exceeds the limit #{limit}"
      end
    end

    # C: d_new_by_frags
    # Date-only fragment-based constructor.
    # Time fields in hash are ignored — use dt_new_by_frags (in datetime.rb) for DateTime.
    def new_by_frags(hash, sg)
      raise Error, "invalid date" if hash.nil? || hash.empty?

      y = hash[:year]
      m = hash[:mon]
      d = hash[:mday]

      # Fast path: year+mon+mday present, no jd/yday
      if !hash.key?(:jd) && !hash.key?(:yday) && y && m && d
        raise Error, "invalid date" unless valid_civil?(y, m, d, sg)
        obj = new(y, m, d, sg)
        # Store parsed offset for deconstruct_keys([:zone]) without
        # affecting JD calculations (don't use @of which triggers UTC conversion)
        of = hash[:offset]
        obj.instance_variable_set(:@parsed_offset, of) if of && of != 0
        return obj
      end

      # Slow path — uses self (Date), so time-only patterns
      # (e.g. '23:55') correctly fail: rt_complete_frags with Date class
      # does not set :jd for :time pattern → rt__valid_date_frags_p returns nil.
      hash = rt_rewrite_frags(hash)
      hash = rt_complete_frags(self, hash)
      jd = rt__valid_date_frags_p(hash, sg)

      raise Error, "invalid date" unless jd

      self.jd(jd, sg)
    end

    # C: rt_rewrite_frags
    # Converts :seconds (from %s/%Q) into jd/hour/min/sec/sec_fraction fields.
    #
    # C implementation (date_core.c:4033):
    #   seconds = del_hash("seconds");
    #   if (!NIL_P(seconds)) {
    #       if (!NIL_P(offset)) seconds = f_add(seconds, offset);
    #       d  = f_idiv(seconds, DAY_IN_SECONDS);
    #       fr = f_mod(seconds, DAY_IN_SECONDS);
    #       h  = f_idiv(fr, HOUR_IN_SECONDS);   fr = f_mod(fr, HOUR_IN_SECONDS);
    #       min= f_idiv(fr, MINUTE_IN_SECONDS);  fr = f_mod(fr, MINUTE_IN_SECONDS);
    #       s  = f_idiv(fr, 1);                   fr = f_mod(fr, 1);
    #       set jd = UNIX_EPOCH_IN_CJD + d, hour, min, sec, sec_fraction
    #   }
    #
    # Ruby's .div() and % match C's f_idiv (rb_intern("div")) and f_mod ('%').
    # Both use floor semantics, correctly handling negative and Rational values.
    def rt_rewrite_frags(hash)
      seconds = hash.delete(:seconds)
      return hash unless seconds

      offset = hash[:offset]
      seconds = seconds + offset if offset

      # Day count from Unix epoch
      # C: d = f_idiv(seconds, DAY_IN_SECONDS)
      d  = seconds.div(DAY_IN_SECONDS)
      fr = seconds % DAY_IN_SECONDS

      # Decompose remainder into h:min:s.frac
      h   = fr.div(HOUR_IN_SECONDS)
      fr  = fr % HOUR_IN_SECONDS

      min = fr.div(MINUTE_IN_SECONDS)
      fr  = fr % MINUTE_IN_SECONDS

      s   = fr.div(1)
      fr  = fr % 1

      # C: UNIX_EPOCH_IN_CJD = 2440588 (1970-01-01 in Chronological JD)
      hash[:jd]           = 2440588 + d
      hash[:hour]         = h
      hash[:min]          = min
      hash[:sec]          = s
      hash[:sec_fraction] = fr
      hash
    end

    # C: rt_complete_frags (date_core.c:4071)
    #
    # Algorithm:
    # 1. Score each of 11 field-set patterns against hash, pick highest match count.
    # 2. For the winning named pattern, fill leading missing date fields from Date.today
    #    and set defaults for trailing date fields.
    # 3. Special case: "time" pattern + DateTime class → set :jd from today.
    # 4. Default :hour/:min/:sec to 0; clamp :sec to 59.
    #
    # Pattern table (C's static tab):
    #   [name,        [fields...]]
    #   ──────────────────────────
    #   [:time,       [:hour, :min, :sec]]
    #   [nil,         [:jd]]
    #   [:ordinal,    [:year, :yday, :hour, :min, :sec]]
    #   [:civil,      [:year, :mon, :mday, :hour, :min, :sec]]
    #   [:commercial, [:cwyear, :cweek, :cwday, :hour, :min, :sec]]
    #   [:wday,       [:wday, :hour, :min, :sec]]
    #   [:wnum0,      [:year, :wnum0, :wday, :hour, :min, :sec]]
    #   [:wnum1,      [:year, :wnum1, :wday, :hour, :min, :sec]]
    #   [nil,         [:cwyear, :cweek, :wday, :hour, :min, :sec]]
    #   [nil,         [:year, :wnum0, :cwday, :hour, :min, :sec]]
    #   [nil,         [:year, :wnum1, :cwday, :hour, :min, :sec]]
    #
    def rt_complete_frags(klass, hash)
      # Step 1: Find best matching pattern
      # C: for each tab entry, count how many fields exist in hash; pick max.
      #    First match wins on tie (strict >).
      best_key    = nil
      best_fields = nil
      best_count  = 0

      COMPLETE_FRAGS_TABLE.each do |key, fields|
        count = fields.count { |f| hash.key?(f) }
        if count > best_count
          best_count  = count
          best_key    = key
          best_fields = fields
        end
      end

      # Step 2: Complete missing fields for named patterns
      # C: if (!NIL_P(k) && (RARRAY_LEN(a) > e))
      d = nil  # lazy Date.today

      if best_key && best_fields && best_fields.length > best_count
        case best_key

        when :ordinal
          # C: fill year from today if missing, default yday=1
          unless hash.key?(:year)
            d ||= today
            hash[:year] = d.year
          end
          hash[:yday] ||= 1

        when :civil
          # C: fill leading missing fields from today, stop at first present field.
          #    Then default mon=1, mday=1.
          #
          #    The loop iterates [:year, :mon, :mday, :hour, :min, :sec].
          #    For each field, if it's already in hash → break.
          #    Otherwise fill from today via d.send(field).
          #    In practice, the loop only reaches date fields (:year/:mon/:mday)
          #    because at least one date field must be present for civil to win.
          best_fields.each do |f|
            break if hash.key?(f)
            d ||= today
            hash[f] = d.send(f)
          end
          hash[:mon]  ||= 1
          hash[:mday] ||= 1

        when :commercial
          # C: same leading-fill pattern, then default cweek=1, cwday=1
          best_fields.each do |f|
            break if hash.key?(f)
            d ||= today
            hash[f] = d.send(f)
          end
          hash[:cweek] ||= 1
          hash[:cwday] ||= 1

        when :wday
          # C: set_hash("jd", d_lite_jd(f_add(f_sub(d, d_lite_wday(d)), ref_hash("wday"))))
          #    → jd of (today - today.wday + parsed_wday)
          d ||= today
          hash[:jd] = (d - d.wday + hash[:wday]).jd

        when :wnum0
          # C: leading-fill from today, then default wnum0=0, wday=0
          best_fields.each do |f|
            break if hash.key?(f)
            d ||= today
            # :year is the only field that can be missing before :wnum0 in practice
            hash[f] = d.send(f) if d.respond_to?(f)
          end
          hash[:wnum0] ||= 0
          hash[:wday]  ||= 0

        when :wnum1
          # C: leading-fill from today, then default wnum1=0, wday=1
          best_fields.each do |f|
            break if hash.key?(f)
            d ||= today
            hash[f] = d.send(f) if d.respond_to?(f)
          end
          hash[:wnum1] ||= 0
          hash[:wday]  ||= 1
        end
      end

      # Step 3: "time" pattern special case
      # C: if (k == sym("time")) { if (f_le_p(klass, cDateTime)) { ... } }
      # For DateTime (or subclass), time-only input gets :jd from today.
      # For Date, time-only input will fail validation (no date fields).
      if best_key == :time
        if defined?(DateTime) && klass <= DateTime
          d ||= today
          hash[:jd] ||= d.jd
        end
      end

      # Step 4: Default time fields, clamp sec
      # C: if (NIL_P(ref_hash("hour"))) set_hash("hour", 0);
      #    if (NIL_P(ref_hash("min")))  set_hash("min",  0);
      #    if (NIL_P(ref_hash("sec")))  set_hash("sec",  0);
      #    else if (ref_hash("sec") > 59) set_hash("sec", 59);
      hash[:hour] ||= 0
      hash[:min]  ||= 0
      if !hash.key?(:sec)
        hash[:sec] = 0
      elsif hash[:sec] > 59
        hash[:sec] = 59
      end

      hash
    end

    # C: rt__valid_date_frags_p (date_core.c:4379)
    # Tries 6 strategies to produce a valid JD from hash fragments:
    #   jd → ordinal → civil → commercial → wnum0 → wnum1
    def rt__valid_date_frags_p(hash, sg)
      # 1. Try jd (C: rt__valid_jd_p just returns jd)
      if hash[:jd]
        return hash[:jd]
      end

      # 2. Try ordinal: year + yday
      if hash[:yday] && hash[:year]
        y  = hash[:year]
        yd = hash[:yday]
        if valid_ordinal?(y, yd, sg)
          return ordinal(y, yd, sg).jd
        end
      end

      # 3. Try civil: year + mon + mday
      if hash[:mday] && hash[:mon] && hash[:year]
        y = hash[:year]
        m = hash[:mon]
        d = hash[:mday]
        if valid_civil?(y, m, d, sg)
          return new(y, m, d, sg).jd
        end
      end

      # 4. Try commercial: cwyear + cweek + cwday/wday
      # C: wday = ref_hash("cwday");
      #    if (NIL_P(wday)) { wday = ref_hash("wday"); if wday==0 → wday=7; }
      begin
        wday = hash[:cwday]
        if wday.nil?
          wday = hash[:wday]
          wday = 7 if wday && wday == 0  # Sunday: wday 0 → cwday 7
        end

        if wday && hash[:cweek] && hash[:cwyear]
          jd = rt__valid_commercial_p(hash[:cwyear], hash[:cweek], wday, sg)
          return jd if jd
        end
      end

      # 5. Try wnum0: year + wnum0 + wday (Sunday-first week, %U)
      # C: wday = ref_hash("wday");
      #    if (NIL_P(wday)) { wday = ref_hash("cwday"); if cwday==7 → wday=0; }
      begin
        wday = hash[:wday]
        if wday.nil?
          wday = hash[:cwday]
          wday = 0 if wday && wday == 7  # Sunday: cwday 7 → wday 0
        end

        if wday && hash[:wnum0] && hash[:year]
          jd = rt__valid_weeknum_p(hash[:year], hash[:wnum0], wday, 0, sg)
          return jd if jd
        end
      end

      # 6. Try wnum1: year + wnum1 + wday (Monday-first week, %W)
      # C: wday = ref_hash("wday"); if NIL → wday = ref_hash("cwday");
      #    if wday → wday = (wday - 1) % 7
      begin
        wday = hash[:wday]
        wday = hash[:cwday] if wday.nil?
        if wday
          wday = (wday - 1) % 7  # Convert: 0(Sun)→6, 1(Mon)→0, ..., 7(Sun)→6
        end

        if wday && hash[:wnum1] && hash[:year]
          jd = rt__valid_weeknum_p(hash[:year], hash[:wnum1], wday, 1, sg)
          return jd if jd
        end
      end

      nil
    end

    # C: rt__valid_commercial_p (date_core.c:4347)
    # Validates commercial date and returns JD, or nil.
    def rt__valid_commercial_p(y, w, d, sg)
      if valid_commercial?(y, w, d, sg)
        return commercial(y, w, d, sg).jd
      end
      nil
    end

    # C: rt__valid_weeknum_p → valid_weeknum_p → c_valid_weeknum_p (date_core.c:1009)
    # Validates weeknum-based date and returns JD, or nil.
    # f=0 for Sunday-first (%U), f=1 for Monday-first (%W).
    def rt__valid_weeknum_p(y, w, d, f, sg)
      # C: if (d < 0) d += 7;
      d += 7 if d < 0
      # C: if (w < 0) { ... normalize via next year ... }
      if w < 0
        rjd2 = c_weeknum_to_jd(y + 1, 1, f, f, sg)
        ry2, rw2, _ = c_jd_to_weeknum(rjd2 + w * 7, f, sg)
        return nil if ry2 != y
        w = rw2
      end
      jd = c_weeknum_to_jd(y, w, d, f, sg)
      ry, rw, rd = c_jd_to_weeknum(jd, f, sg)
      return nil if y != ry || w != rw || d != rd
      jd
    end

    # C: c_weeknum_to_jd (date_core.c:663)
    # Converts (year, week_number, day_in_week, first_day_flag, sg) → JD.
    #
    # C formula:
    #   c_find_fdoy(y, sg, &rjd2, &ns2);
    #   rjd2 += 6;
    #   *rjd = (rjd2 - MOD(((rjd2 - f) + 1), 7) - 7) + 7 * w + d;
    def c_weeknum_to_jd(y, w, d, f, sg)
      fdoy_jd, _ = c_find_fdoy(y, sg)
      fdoy_jd += 6
      (fdoy_jd - ((fdoy_jd - f + 1) % 7) - 7) + 7 * w + d
    end

    # C: c_jd_to_weeknum (date_core.c:674)
    # Converts JD → [year, week_number, day_in_week].
    # Class-method version (the instance method in core.rb calls self.class.send).
    #
    # C formula:
    #   c_jd_to_civil(jd, sg, &ry, ...);
    #   c_find_fdoy(ry, sg, &rjd, ...);
    #   rjd += 6;
    #   j = jd - (rjd - MOD((rjd - f) + 1, 7)) + 7;
    #   rw = DIV(j, 7);
    #   rd = MOD(j, 7);
    def c_jd_to_weeknum(jd, f, sg)
      ry, _, _ = c_jd_to_civil(jd, sg)
      fdoy_jd, _ = c_find_fdoy(ry, sg)
      fdoy_jd += 6

      j = jd - (fdoy_jd - ((fdoy_jd - f + 1) % 7)) + 7
      rw = j.div(7)
      rd = j % 7

      [ry, rw, rd]
    end

    # --- comp_year helpers (C's comp_year69, comp_year50) ---
    def comp_year69(y)
      y >= 69 ? y + 1900 : y + 2000
    end

    def comp_year50(y)
      y >= 50 ? y + 1900 : y + 2000
    end

    # --- sec_fraction helper ---
    def sec_fraction(frac_str)
      Rational(frac_str.to_i, 10 ** frac_str.length)
    end

    # ================================================================
    # Format-specific parsers (date_parse.c)
    # ================================================================

    # --- ISO 8601 ---

    def date__iso8601(str)
      hash = {}
      return hash if str.nil? || str.empty?

      if (m = ISO8601_EXT_DATETIME_PAT.match(str))
        iso8601_ext_datetime_cb(m, hash)
      elsif (m = ISO8601_BAS_DATETIME_PAT.match(str))
        iso8601_bas_datetime_cb(m, hash)
      elsif (m = ISO8601_EXT_TIME_PAT.match(str))
        iso8601_time_cb(m, hash)
      elsif (m = ISO8601_BAS_TIME_PAT.match(str))
        iso8601_time_cb(m, hash)
      end
      hash
    end

    def iso8601_ext_datetime_cb(m, hash)
      if m[1]
        hash[:mday] = m[3].to_i if m[3]
        if m[1] != '-'
          y = m[1].to_i
          y = comp_year69(y) if m[1].length < 4
          hash[:year] = y
        end
        if m[2].nil?
          return false if m[1] != '-'
        else
          hash[:mon] = m[2].to_i
        end
      elsif m[5]
        hash[:yday] = m[5].to_i
        if m[4]
          y = m[4].to_i
          y = comp_year69(y) if m[4].length < 4
          hash[:year] = y
        end
      elsif m[8]
        hash[:cweek] = m[7].to_i
        hash[:cwday] = m[8].to_i
        if m[6]
          y = m[6].to_i
          y = comp_year69(y) if m[6].length < 4
          hash[:cwyear] = y
        end
      elsif m[9]
        hash[:cwday] = m[9].to_i
      end

      if m[10]
        hash[:hour] = m[10].to_i
        hash[:min]  = m[11].to_i
        hash[:sec]  = m[12].to_i if m[12]
      end
      hash[:sec_fraction] = sec_fraction(m[13]) if m[13]
      if m[14]
        hash[:zone]   = m[14]
        hash[:offset] = date_zone_to_diff(m[14])
      end
      true
    end

    def iso8601_bas_datetime_cb(m, hash)
      if m[3]
        hash[:mday] = m[3].to_i
        if m[1] != '--'
          y = m[1].to_i
          y = comp_year69(y) if m[1].length < 4
          hash[:year] = y
        end
        if m[2][0] == '-'
          return false if m[1] != '--'
        else
          hash[:mon] = m[2].to_i
        end
      elsif m[5]
        hash[:yday] = m[5].to_i
        y = m[4].to_i
        y = comp_year69(y) if m[4].length < 4
        hash[:year] = y
      elsif m[6]
        hash[:yday] = m[6].to_i
      elsif m[9]
        hash[:cweek] = m[8].to_i
        hash[:cwday] = m[9].to_i
        y = m[7].to_i
        y = comp_year69(y) if m[7].length < 4
        hash[:cwyear] = y
      elsif m[11]
        hash[:cweek] = m[10].to_i
        hash[:cwday] = m[11].to_i
      elsif m[12]
        hash[:cwday] = m[12].to_i
      end

      if m[13]
        hash[:hour] = m[13].to_i
        hash[:min]  = m[14].to_i
        hash[:sec]  = m[15].to_i if m[15]
      end
      hash[:sec_fraction] = sec_fraction(m[16]) if m[16]
      if m[17]
        hash[:zone]   = m[17]
        hash[:offset] = date_zone_to_diff(m[17])
      end
      true
    end

    def iso8601_time_cb(m, hash)
      hash[:hour] = m[1].to_i
      hash[:min]  = m[2].to_i
      hash[:sec]  = m[3].to_i if m[3]
      hash[:sec_fraction] = sec_fraction(m[4]) if m[4]
      if m[5]
        hash[:zone]   = m[5]
        hash[:offset] = date_zone_to_diff(m[5])
      end
      true
    end

    # --- RFC 3339 ---

    def date__rfc3339(str)
      hash = {}
      return hash if str.nil? || str.empty?

      m = RFC3339_PAT.match(str)
      return hash unless m

      hash[:year]   = m[1].to_i
      hash[:mon]    = m[2].to_i
      hash[:mday]   = m[3].to_i
      hash[:hour]   = m[4].to_i
      hash[:min]    = m[5].to_i
      hash[:sec]    = m[6].to_i
      hash[:zone]   = m[8]
      hash[:offset] = date_zone_to_diff(m[8])
      hash[:sec_fraction] = sec_fraction(m[7]) if m[7]
      hash
    end

    # --- XML Schema ---

    def date__xmlschema(str)
      hash = {}
      return hash if str.nil? || str.empty?

      if (m = XMLSCHEMA_DATETIME_PAT.match(str))
        hash[:year] = m[1].to_i
        hash[:mon]  = m[2].to_i if m[2]
        hash[:mday] = m[3].to_i if m[3]
        hash[:hour] = m[4].to_i if m[4]
        hash[:min]  = m[5].to_i if m[5]
        hash[:sec]  = m[6].to_i if m[6]
        hash[:sec_fraction] = sec_fraction(m[7]) if m[7]
        if m[8]
          hash[:zone]   = m[8]
          hash[:offset] = date_zone_to_diff(m[8])
        end
      elsif (m = XMLSCHEMA_TIME_PAT.match(str))
        hash[:hour] = m[1].to_i
        hash[:min]  = m[2].to_i
        hash[:sec]  = m[3].to_i if m[3]
        hash[:sec_fraction] = sec_fraction(m[4]) if m[4]
        if m[5]
          hash[:zone]   = m[5]
          hash[:offset] = date_zone_to_diff(m[5])
        end
      elsif (m = XMLSCHEMA_TRUNC_PAT.match(str))
        hash[:mon]  = m[1].to_i if m[1]
        hash[:mday] = m[2].to_i if m[2]
        hash[:mday] = m[3].to_i if m[3]
        if m[4]
          hash[:zone]   = m[4]
          hash[:offset] = date_zone_to_diff(m[4])
        end
      end
      hash
    end

    # --- RFC 2822 ---

    def date__rfc2822(str)
      hash = {}
      return hash if str.nil? || str.empty?

      m = PARSE_RFC2822_PAT.match(str)
      return hash unless m

      hash[:wday] = day_num(m[1]) if m[1]
      hash[:mday] = m[2].to_i
      hash[:mon]  = mon_num(m[3])
      y = m[4].to_i
      y = comp_year50(y) if m[4].length < 4
      hash[:year] = y
      hash[:hour] = m[5].to_i
      hash[:min]  = m[6].to_i
      hash[:sec]  = m[7].to_i if m[7]
      hash[:zone]   = m[8]
      hash[:offset] = date_zone_to_diff(m[8])
      hash
    end

    # --- HTTP date ---

    def date__httpdate(str)
      hash = {}
      return hash if str.nil? || str.empty?

      if (m = PARSE_HTTPDATE_TYPE1_PAT.match(str))
        hash[:wday]   = day_num(m[1])
        hash[:mday]   = m[2].to_i
        hash[:mon]    = mon_num(m[3])
        hash[:year]   = m[4].to_i
        hash[:hour]   = m[5].to_i
        hash[:min]    = m[6].to_i
        hash[:sec]    = m[7].to_i
        hash[:zone]   = m[8]
        hash[:offset] = 0
      elsif (m = PARSE_HTTPDATE_TYPE2_PAT.match(str))
        hash[:wday]   = day_num(m[1])
        hash[:mday]   = m[2].to_i
        hash[:mon]    = mon_num(m[3])
        y = m[4].to_i
        y = comp_year69(y) if y >= 0 && y <= 99
        hash[:year]   = y
        hash[:hour]   = m[5].to_i
        hash[:min]    = m[6].to_i
        hash[:sec]    = m[7].to_i
        hash[:zone]   = m[8]
        hash[:offset] = 0
      elsif (m = PARSE_HTTPDATE_TYPE3_PAT.match(str))
        hash[:wday] = day_num(m[1])
        hash[:mon]  = mon_num(m[2])
        hash[:mday] = m[3].to_i
        hash[:hour] = m[4].to_i
        hash[:min]  = m[5].to_i
        hash[:sec]  = m[6].to_i
        hash[:year] = m[7].to_i
      end
      hash
    end

    # --- JIS X 0301 ---

    def date__jisx0301(str)
      hash = {}
      return hash if str.nil? || str.empty?

      m = PARSE_JISX0301_PAT.match(str)
      if m
        era = m[1] || JISX0301_DEFAULT_ERA
        ep = gengo(era)
        hash[:year] = ep + m[2].to_i
        hash[:mon]  = m[3].to_i
        hash[:mday] = m[4].to_i
        if m[5]
          hash[:hour] = m[5].to_i
          hash[:min]  = m[6].to_i if m[6]
          hash[:sec]  = m[7].to_i if m[7]
        end
        hash[:sec_fraction] = sec_fraction(m[8]) if m[8] && !m[8].empty?
        if m[9]
          hash[:zone]   = m[9]
          hash[:offset] = date_zone_to_diff(m[9])
        end
      else
        # Fallback to iso8601
        hash = date__iso8601(str)
      end
      hash
    end
  end
end
