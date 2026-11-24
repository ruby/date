# encoding: US-ASCII
# frozen_string_literal: true

# Constants
class Date
  # An array of strings of full month names in English.  The first
  # element is nil.
  MONTHNAMES = [nil, 'January', 'February', 'March', 'April', 'May', 'June',
                'July', 'August', 'September', 'October', 'November', 'December'].freeze
  # An array of strings of abbreviated month names in English.  The
  # first element is nil.
  ABBR_MONTHNAMES = [nil, 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].freeze
  # An array of strings of the full names of days of the week in English.
  # The first is "Sunday".
  DAYNAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  # An array of strings of abbreviated day names in English.  The
  # first is "Sun".
  ABBR_DAYNAMES = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  # The Julian day number of the day of calendar reform for Italy
  # and some catholic countries.
  ITALY     = 2299161 # 1582-10-15
  # The Julian day number of the day of calendar reform for England
  # and her colonies.
  ENGLAND   = 2361222 # 1752-09-14
  # The Julian day number of the day of calendar reform for the
  # proleptic Julian calendar.
  JULIAN    = Float::INFINITY
  # The Julian day number of the day of calendar reform for the
  # proleptic Gregorian calendar.
  GREGORIAN = -Float::INFINITY

  # Valid range for a finite start (calendar-reform cutover) value, matching the
  # C extension: the Julian day numbers of the earliest and latest supported
  # reform dates (ns 1582-01-01 .. os 1930-12-31), inclusive. A finite start
  # outside this range (or NaN) is ignored and falls back to ITALY; infinities
  # are always valid.
  VALID_START_MIN = 2298874 # ns 1582-01-01
  VALID_START_MAX = 2426355 # os 1930-12-31
  private_constant :VALID_START_MIN, :VALID_START_MAX

  # Case-insensitive abbreviated name lookup tables for O(1) name matching.
  # Key = downcased 3-letter abbreviation, Value = [index, full_name_length].
  # The length lets callers verify an optional full-name tail (e.g. the
  # "day" in "Sunday" following "Sun").
  ABBR_DAY_INFO = ABBR_DAYNAMES.each_with_index.to_h { |n, i|
    [n.downcase.freeze, [i, DAYNAMES[i].length].freeze]
  }.freeze
  ABBR_MONTH_INFO = ABBR_MONTHNAMES.each_with_index.each_with_object({}) { |(n, i), h|
    next if n.nil?
    h[n.downcase.freeze] = [i, MONTHNAMES[i].length].freeze
  }.freeze
  private_constant :ABBR_DAY_INFO, :ABBR_MONTH_INFO

  # Abbreviated-name -> index maps, derived from the *_INFO tables above: same
  # (downcased) keys, with the index alone as the value (no name length).
  ABBR_MONTH_NUM = ABBR_MONTH_INFO.transform_values { |v| v[0] }.freeze
  ABBR_DAY_NUM   = ABBR_DAY_INFO.transform_values { |v| v[0] }.freeze
  private_constant :ABBR_MONTH_NUM, :ABBR_DAY_NUM

  # Lowercase full name strings for StringScanner-based head matching
  DAY_LOWER_STRS = DAYNAMES.map { |n| n.downcase.freeze }.freeze
  MONTH_LOWER_STRS = MONTHNAMES.map { |n| n&.downcase&.freeze }.freeze
  private_constant :DAY_LOWER_STRS, :MONTH_LOWER_STRS

  # === Calendar computation (from core.rb) ===

  # Days in month for Gregorian calendar.
  DAYS_IN_MONTH_GREGORIAN = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
  private_constant :DAYS_IN_MONTH_GREGORIAN

  # Precomputed month offset for Julian Day computation:
  #   GJD_MONTH_OFFSET[m] == (306001 * (gm + 1)) / 10000
  # where gm = m + 12 for m <= 2, else gm = m.
  # Used to avoid an integer multiply in the hot path of civil_to_jd.
  GJD_MONTH_OFFSET = [nil, 428, 459, 122, 153, 183, 214, 244, 275, 306, 336, 367, 397].freeze
  private_constant :GJD_MONTH_OFFSET

  ERA_TABLE = [
    [2458605, 'R', 2018],  # Reiwa:   2019-05-01
    [2447535, 'H', 1988],  # Heisei:  1989-01-08
    [2424875, 'S', 1925],  # Showa:   1926-12-25
    [2419614, 'T', 1911],  # Taisho:  1912-07-30
    [2405160, 'M', 1867],  # Meiji:   1873-01-01
  ].freeze
  private_constant :ERA_TABLE

  # Pre-built "-MM-DD" suffixes for all valid month/day combinations.
  # Indexed by [month][day]. Avoids per-call format() for the month/day portion.
  MONTH_DAY_SUFFIX = Array.new(13) { |m|
    Array.new(32) { |d|
      next nil if m == 0 || d == 0
      format('-%02d-%02d', m, d).freeze
    }.freeze
  }.freeze
  private_constant :MONTH_DAY_SUFFIX

  # Pre-computed 2-digit zero-padded strings for 0..99
  PAD2 = (0..99).map { |n| format('%02d', n).freeze }.freeze
  private_constant :PAD2

  # Map composite spec characters to their expansion strings
  STRFTIME_COMPOSITE = {
    '+' => '%a %b %e %H:%M:%S %Z %Y',
    'c' => '%a %b %e %H:%M:%S %Y',
    'D' => '%m/%d/%y',
    'F' => '%Y-%m-%d',
    'n' => "\n",
    'r' => '%I:%M:%S %p',
    'R' => '%H:%M',
    't' => "\t",
    'T' => '%H:%M:%S',
    'v' => '%e-%^b-%Y',
    'X' => '%H:%M:%S',
    'x' => '%m/%d/%y',
  }.freeze
  private_constant :STRFTIME_COMPOSITE

  # Valid specs for the %E locale modifier
  STRFTIME_E_VALID_CHARS = %w[c C x X y Y].freeze
  # Valid specs for the %O locale modifier
  STRFTIME_O_VALID_CHARS = %w[d e H k I l m M S u U V w W y].freeze
  private_constant :STRFTIME_E_VALID_CHARS, :STRFTIME_O_VALID_CHARS

  # Maximum allowed format width to prevent unreasonable memory allocation
  STRFTIME_MAX_WIDTH = 65535
  private_constant :STRFTIME_MAX_WIDTH

  # === Parse regex patterns (from parse.rb) ===

  RFC3339_RE = /\A\s*(-?\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[-+]\d{2}:\d{2})\s*\z/i
  private_constant :RFC3339_RE

  HTTPDATE_TYPE1_RE = /\A\s*(sun|mon|tue|wed|thu|fri|sat)\s*,\s+(\d{2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(-?\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+(gmt)\s*\z/i
  HTTPDATE_TYPE2_RE = /\A\s*(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s*,\s+(\d{2})\s*-\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*-\s*(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+(gmt)\s*\z/i
  HTTPDATE_TYPE3_RE = /\A\s*(sun|mon|tue|wed|thu|fri|sat)\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})\s*\z/i
  private_constant :HTTPDATE_TYPE1_RE, :HTTPDATE_TYPE2_RE, :HTTPDATE_TYPE3_RE

  # Wday lookup from full day name (lowercase key). The abbreviated-name
  # lookup reuses ABBR_DAY_NUM, which is the identical table; both maps are
  # derived from the canonical name lists so they cannot drift out of sync.
  HTTPDATE_FULL_WDAY = DAYNAMES.each_with_index.to_h { |n, i| [n.downcase, i] }.freeze
  private_constant :HTTPDATE_FULL_WDAY

  RFC2822_RE = /\A\s*(?:(sun|mon|tue|wed|thu|fri|sat)\s*,\s+)?(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(-?\d{2,})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([-+]\d{4}|ut|gmt|e[sd]t|c[sd]t|m[sd]t|p[sd]t|[a-ik-z])\s*\z/i
  private_constant :RFC2822_RE

  XMLSCHEMA_DATETIME_RE = /\A\s*(-?\d{4,})(?:-(\d{2})(?:-(\d{2}))?)?(?:t(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?)?(z|[-+]\d{2}:\d{2})?\s*\z/i
  XMLSCHEMA_TIME_RE     = /\A\s*(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(z|[-+]\d{2}:\d{2})?\s*\z/i
  XMLSCHEMA_TRUNC_RE    = /\A\s*(?:--(\d{2})(?:-(\d{2}))?|---(\d{2}))(z|[-+]\d{2}:\d{2})?\s*\z/i
  private_constant :XMLSCHEMA_DATETIME_RE, :XMLSCHEMA_TIME_RE, :XMLSCHEMA_TRUNC_RE

  ISO8601_EXT_DATETIME_RE = %r{\A\s*
    (?:
      ([-+]?\d{2,}|-)-(\d{2})?(?:-(\d{2}))?   |  # year-mon-mday or --mon-mday or ---mday
      ([-+]?\d{2,})?-(\d{3})                    |  # year-yday
      (\d{4}|\d{2})?-w(\d{2})(?:-(\d))?         |  # cwyear-wNN-D
      -w-(\d)                                       # -w-D
    )
    (?:t
      (\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?
      (z|[-+]\d{2}(?::?\d{2})?)?
    )?
  \s*\z}xi

  ISO8601_BAS_DATETIME_RE = %r{\A\s*
    (?:
      ([-+]?(?:\d{4}|\d{2})|--)(\d{2}|-)(\d{2})  |  # yyyymmdd / --mmdd / ----dd
      ([-+]?(?:\d{4}|\d{2}))(\d{3})                 |  # yyyyddd
      -(\d{3})                                        |  # -ddd
      (\d{4}|\d{2})w(\d{2})(\d)                      |  # yyyywwwd
      -w(\d{2})(\d)                                   |  # -wNN-D
      -w-(\d)                                            # -w-D
    )
    (?:t?
      (\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?)?
      (z|[-+]\d{2}(\d{2})?)?
    )?
  \s*\z}xi

  ISO8601_EXT_TIME_RE = /\A\s*(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?(z|[-+]\d{2}(?::?\d{2})?)?)?\s*\z/i
  ISO8601_BAS_TIME_RE = /\A\s*(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?(z|[-+]\d{2}(\d{2})?)?)?\s*\z/i
  private_constant :ISO8601_EXT_DATETIME_RE, :ISO8601_BAS_DATETIME_RE,
                   :ISO8601_EXT_TIME_RE, :ISO8601_BAS_TIME_RE

  JISX0301_ERA = { 'm' => 1867, 't' => 1911, 's' => 1925, 'h' => 1988, 'r' => 2018 }.freeze
  JISX0301_RE = /\A\s*([mtshr])?(\d{2})\.(\d{2})\.(\d{2})(?:t(?:(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d*))?)?(z|[-+]\d{2}(?::?\d{2})?)?)?)?\s*\z/i
  private_constant :JISX0301_ERA, :JISX0301_RE

  PARSE_DAYS_RE = /\b(sun|mon|tue|wed|thu|fri|sat)[^-\/\d\s]*/i
  PARSE_MON_RE  = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\S*/i
  PARSE_MDAY_RE = /(?<!\d)(\d+)(st|nd|rd|th)\b/i
  PARSE_BC_RE   = /\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)/i
  PARSE_YEAR_RE = /'(\d+)\b/
  private_constant :PARSE_DAYS_RE, :PARSE_MON_RE, :PARSE_MDAY_RE,
                   :PARSE_BC_RE, :PARSE_YEAR_RE

  # time zone pattern: multi-word zones, gmt/utc offsets, single-letter military zones
  PARSE_TIME_ZONE_RE = /(?:
    (?:gmt|utc?)?[-+]\d+(?:[,.:]?\d+(?::\d+)?)?
  |
    (?-i:[[:alpha:].\s]+)(?:standard|daylight)\s+time\b
  |
    (?-i:[[:alpha:]]+)(?:\s+dst)?\b
  )/xi

  # The main time regex (captures the time + optional zone)
  PARSE_TIME_RE = /(
    (?<!\d)\d+\s*
    (?:
      (?:
        :\s*\d+
        (?:\s*:\s*\d+(?:[,.]\d*)?)?
      |
        h(?:\s*\d+m?(?:\s*\d+s?)?)?
      )
      (?:\s*[ap](?:m\b|\.m\.))?
    |
      [ap](?:m\b|\.m\.)
    )
  )
  (?:
    \s*
    (#{PARSE_TIME_ZONE_RE.source})
  )?/xi

  PARSE_TIME_CB_RE = /\A(\d+)h?(?:\s*:?\s*(\d+)m?(?:\s*:?\s*(\d+)(?:[,.](\d+))?s?)?)?(?:\s*([ap])(?:m\b|\.m\.))?/i
  private_constant :PARSE_TIME_ZONE_RE, :PARSE_TIME_RE, :PARSE_TIME_CB_RE

  # EU date format
  PARSE_EU_RE = /('?(?<!\d)\d+)[^\-\d\s]*\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^\-\d\s']*(?:\s*(?:\b(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))\b)?\s*('?-?\d+(?:(?:st|nd|rd|th)\b)?))?/i

  # US date format
  PARSE_US_RE = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^\-\d\s']*\s*('?\d+)[^\-\d\s']*(?:\s*,?\s*(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))?\s*('?-?\d+))?/i

  # ISO date (YYYY-MM-DD)
  PARSE_ISO_RE = /('?[-+]?(?<!\d)\d+)-(\d+)-('?-?\d+)/

  # JIS X 0301
  PARSE_JIS_RE = /\b([mtshr])(\d+)\.(\d+)\.(\d+)/i

  # VMS format: DD-Mon-YYYY
  PARSE_VMS11_RE = /('?-?(?<!\d)\d+)-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^\-\/.]*-('?-?\d+)/i
  PARSE_VMS12_RE = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^\-\/.]*-('?-?\d+)(?:-('?-?\d+))?/i

  # Slash format
  PARSE_SLA_RE = /('?-?(?<!\d)\d+)\/\s*('?\d+)(?:\D\s*('?-?\d+))?/

  # Dot format
  PARSE_DOT_RE = /('?-?(?<!\d)\d+)\.\s*('?\d+)\.\s*('?-?\d+)/

  # ISO week/ordinal formats
  PARSE_ISO21_RE = /\b(\d{2}|\d{4})?-?w(\d{2})(?:-?(\d))?\b/i
  PARSE_ISO22_RE = /-w-(\d)\b/i
  PARSE_ISO23_RE = /--(\d{2})?-(\d{2})\b/
  PARSE_ISO24_RE = /--(\d{2})(\d{2})?\b/
  PARSE_ISO25_RE = /\b(\d{2}|\d{4})-(\d{3})\b/
  PARSE_ISO26_RE = /\b-(\d{3})\b/

  # DDD (continuous digit) pattern
  PARSE_DDD_RE = /([-+]?)((?<!\d)\d{2,14})(?:\s*t?\s*(\d{2,6})?(?:[,.](\d*))?)?(?:\s*(z\b|[-+]\d{1,4}\b|\[[-+]?\d[^\]]*\]))?/i

  # Fragment (1-2 digit remaining)
  PARSE_FRAG_RE = /\A\s*(\d{1,2})\s*\z/

  private_constant :PARSE_EU_RE, :PARSE_US_RE, :PARSE_ISO_RE, :PARSE_JIS_RE,
                   :PARSE_VMS11_RE, :PARSE_VMS12_RE, :PARSE_SLA_RE, :PARSE_DOT_RE,
                   :PARSE_ISO21_RE, :PARSE_ISO22_RE, :PARSE_ISO23_RE,
                   :PARSE_ISO24_RE, :PARSE_ISO25_RE, :PARSE_ISO26_RE,
                   :PARSE_DDD_RE, :PARSE_FRAG_RE

  # Fast path patterns for common formats (bypass full _parse pipeline)
  FAST_PARSE_US_RE  = /\A\s*([a-zA-Z]{3})[a-zA-Z]*\s+(\d{1,2})\s*,?\s*(\d{4})\s*\z/
  FAST_PARSE_EU_RE  = /\A\s*(\d{1,2})\s+([a-zA-Z]{3})[a-zA-Z]*\s+(\d{4})\s*\z/
  FAST_PARSE_RFC2822_RE = /\A\s*([a-zA-Z]{3}),\s+(\d{1,2})\s+([a-zA-Z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([-+]\d{4})\s*\z/
  private_constant :FAST_PARSE_US_RE, :FAST_PARSE_EU_RE, :FAST_PARSE_RFC2822_RE

  # === Strptime constants (from strptime.rb) ===

  # Zone pattern matching: numeric offsets and named zones
  # Matches (case-insensitive):
  #   - Numeric: +/-HHMM, +/-HH:MM, +/-HH:MM:SS, +/-HH,frac, +/-HH.frac
  #     optionally preceded by gmt/utc/ut
  #   - Named: "Eastern Standard Time", "EST", "Japan DST", etc.
  STRPTIME_ZONE_PAT = /\A(
    (?:gmt|utc?)?[-+]\d+(?:[,.:]\d+(?::\d+)?)?
    |(?-i:[[:alpha:].\s]+)(?:standard|daylight)\s+time\b
    |(?-i:[[:alpha:]]+)(?:\s+dst)?\b
  )/ix.freeze
  private_constant :STRPTIME_ZONE_PAT

  # Priority table for completing partial date fragments (same order as C)
  COMPLETE_FRAGS_TAB = [
    [:time,       [:hour, :min, :sec]],
    [nil,         [:jd]],
    [:ordinal,    [:year, :yday, :hour, :min, :sec]],
    [:civil,      [:year, :mon, :mday, :hour, :min, :sec]],
    [:commercial, [:cwyear, :cweek, :cwday, :hour, :min, :sec]],
    [:wday,       [:wday, :hour, :min, :sec]],
    [:wnum0,      [:year, :wnum0, :wday, :hour, :min, :sec]],
    [:wnum1,      [:year, :wnum1, :wday, :hour, :min, :sec]],
    [nil,         [:cwyear, :cweek, :wday, :hour, :min, :sec]],
    [nil,         [:year, :wnum0, :cwday, :hour, :min, :sec]],
    [nil,         [:year, :wnum1, :cwday, :hour, :min, :sec]],
  ].freeze
  private_constant :COMPLETE_FRAGS_TAB
end
