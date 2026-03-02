# encoding: US-ASCII
# frozen_string_literal: true

# Constants
class Date
  MONTHNAMES = [nil, 'January', 'February', 'March', 'April', 'May', 'June',
                'July', 'August', 'September', 'October', 'November', 'December'].freeze
  ABBR_MONTHNAMES = [nil, 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].freeze
  DAYNAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  ABBR_DAYNAMES = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  ITALY     = 2299161 # 1582-10-15
  ENGLAND   = 2361222 # 1752-09-14
  JULIAN    = Float::INFINITY
  GREGORIAN = -Float::INFINITY

  DEFAULT_SG = ITALY
  private_constant :DEFAULT_SG

  # Pre-computed lowercase byte arrays for fast case-insensitive name matching in strptime
  ABBR_DAY_LOWER_BYTES = ABBR_DAYNAMES.map { |n| n.downcase.bytes.freeze }.freeze
  DAY_LOWER_BYTES = DAYNAMES.map { |n| n.downcase.bytes.freeze }.freeze
  ABBR_MONTH_LOWER_BYTES = ABBR_MONTHNAMES.each_with_object([]) { |n, a|
    a << (n ? n.downcase.bytes.freeze : nil)
  }.freeze
  MONTH_LOWER_BYTES = MONTHNAMES.each_with_object([]) { |n, a|
    a << (n ? n.downcase.bytes.freeze : nil)
  }.freeze
  private_constant :ABBR_DAY_LOWER_BYTES, :DAY_LOWER_BYTES,
                   :ABBR_MONTH_LOWER_BYTES, :MONTH_LOWER_BYTES

  # 3-byte integer key lookup tables for O(1) abbreviated name matching.
  # Key = (byte0_lower << 16) | (byte1_lower << 8) | byte2_lower
  # Value = [index, full_name_length]
  ABBR_DAY_3KEY = ABBR_DAYNAMES.each_with_index.to_h { |n, i|
    b = n.downcase.bytes
    [(b[0] << 16) | (b[1] << 8) | b[2], [i, DAYNAMES[i].length].freeze]
  }.freeze
  ABBR_MONTH_3KEY = ABBR_MONTHNAMES.each_with_index.each_with_object({}) { |(n, i), h|
    next if n.nil?
    b = n.downcase.bytes
    h[(b[0] << 16) | (b[1] << 8) | b[2]] = [i, MONTHNAMES[i].length].freeze
  }.freeze
  private_constant :ABBR_DAY_3KEY, :ABBR_MONTH_3KEY

  # Case-insensitive abbreviated month name -> month number (1-12)
  ABBR_MONTH_NUM = ABBR_MONTHNAMES.each_with_index.each_with_object({}) { |(n, i), h|
    next if n.nil?
    h[n.downcase] = i
  }.freeze

  # Case-insensitive abbreviated day name -> wday number (0-6)
  ABBR_DAY_NUM = ABBR_DAYNAMES.each_with_index.to_h { |n, i| [n.downcase, i] }.freeze
  private_constant :ABBR_MONTH_NUM, :ABBR_DAY_NUM

  JULIAN_EPOCH_DATE             = '-4712-01-01'.freeze
  JULIAN_EPOCH_DATETIME         = '-4712-01-01T00:00:00+00:00'.freeze
  JULIAN_EPOCH_DATETIME_RFC2822 = 'Mon, 1 Jan -4712 00:00:00 +0000'.freeze
  JULIAN_EPOCH_DATETIME_HTTPDATE = 'Mon, 01 Jan -4712 00:00:00 GMT'.freeze
  private_constant :JULIAN_EPOCH_DATE, :JULIAN_EPOCH_DATETIME,
                   :JULIAN_EPOCH_DATETIME_RFC2822, :JULIAN_EPOCH_DATETIME_HTTPDATE

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

  STRFTIME_DATE_DEFAULT_FMT = '%F'.encode(Encoding::US_ASCII)
  private_constant :STRFTIME_DATE_DEFAULT_FMT

  ASCTIME_DAYS  = %w[Sun Mon Tue Wed Thu Fri Sat].freeze
  ASCTIME_MONS  = [nil, 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].freeze
  RFC2822_DAYS  = ASCTIME_DAYS
  private_constant :ASCTIME_DAYS, :ASCTIME_MONS, :RFC2822_DAYS

  # Pre-computed " Mon " strings for rfc2822/httpdate: " Jan ", " Feb ", ...
  RFC_MON_SPACE = ASCTIME_MONS.map { |m| m ? " #{m} ".freeze : nil }.freeze
  private_constant :RFC_MON_SPACE

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

  # === String formatting (from strftime.rb) ===

  DEFAULT_STRFTIME_FMT = '%F'
  private_constant :DEFAULT_STRFTIME_FMT

  YMD_FMT = '%Y-%m-%d'
  private_constant :YMD_FMT

  # Locale-independent month/day name tables (same as C ext)
  STRFTIME_MONTHS_FULL  = MONTHNAMES.freeze
  STRFTIME_MONTHS_ABBR  = ABBR_MONTHNAMES.freeze
  STRFTIME_DAYS_FULL    = DAYNAMES.freeze
  STRFTIME_DAYS_ABBR    = ABBR_DAYNAMES.freeze
  private_constant :STRFTIME_MONTHS_FULL, :STRFTIME_MONTHS_ABBR,
                   :STRFTIME_DAYS_FULL,   :STRFTIME_DAYS_ABBR

  # Pre-computed "Sun Jan " prefix table for %c / asctime [wday][month]
  ASCTIME_PREFIX = Array.new(7) { |w|
    Array.new(13) { |m|
      m == 0 ? nil : "#{STRFTIME_DAYS_ABBR[w]} #{STRFTIME_MONTHS_ABBR[m]} ".freeze
    }.freeze
  }.freeze
  private_constant :ASCTIME_PREFIX

  # Pre-computed "Saturday, " prefix table for %A format [wday]
  DAY_FULL_COMMA = STRFTIME_DAYS_FULL.map { |d| "#{d}, ".freeze }.freeze
  # Pre-computed "March " prefix table for %B format [month]
  MONTH_FULL_SPACE = STRFTIME_MONTHS_FULL.map { |m| m ? "#{m} ".freeze : nil }.freeze
  private_constant :DAY_FULL_COMMA, :MONTH_FULL_SPACE

  # Bitmask flag constants for strftime parsing
  FL_LEFT   = 0x01  # '-' flag
  FL_SPACE  = 0x02  # '_' flag
  FL_ZERO   = 0x04  # '0' flag
  FL_UPPER  = 0x08  # '^' flag
  FL_CHCASE = 0x10  # '#' flag
  private_constant :FL_LEFT, :FL_SPACE, :FL_ZERO, :FL_UPPER, :FL_CHCASE

  # Pre-computed 2-digit zero-padded strings for 0..99
  PAD2 = (0..99).map { |n| format('%02d', n).freeze }.freeze
  private_constant :PAD2

  # Map composite spec bytes to their expansion strings
  STRFTIME_COMPOSITE_BYTE = {
    99  => '%a %b %e %H:%M:%S %Y',  # 'c'
    68  => '%m/%d/%y',               # 'D'
    70  => '%Y-%m-%d',               # 'F'
    110 => "\n",                     # 'n'
    114 => '%I:%M:%S %p',            # 'r'
    82  => '%H:%M',                  # 'R'
    116 => "\t",                     # 't'
    84  => '%H:%M:%S',              # 'T'
    118 => '%e-%^b-%4Y',            # 'v'
    88  => '%H:%M:%S',              # 'X'
    120 => '%m/%d/%y',              # 'x'
  }.freeze
  private_constant :STRFTIME_COMPOSITE_BYTE

  # Valid specs for %E locale modifier (as byte values)
  # c=99, C=67, x=120, X=88, y=121, Y=89
  STRFTIME_E_VALID_BYTES = [99, 67, 120, 88, 121, 89].freeze
  # Valid specs for %O locale modifier (as byte values)
  # d=100, e=101, H=72, k=107, I=73, l=108, m=109, M=77, S=83, u=117, U=85, V=86, w=119, W=87, y=121
  STRFTIME_O_VALID_BYTES = [100, 101, 72, 107, 73, 108, 109, 77, 83, 117, 85, 86, 119, 87, 121].freeze
  private_constant :STRFTIME_E_VALID_BYTES, :STRFTIME_O_VALID_BYTES

  # Maximum allowed format width to prevent unreasonable memory allocation
  STRFTIME_MAX_WIDTH = 65535
  # Maximum length for a single formatted field (matches C's STRFTIME_MAX_COPY_LEN)
  STRFTIME_MAX_COPY_LEN = 1024
  private_constant :STRFTIME_MAX_WIDTH, :STRFTIME_MAX_COPY_LEN

  # === Parse regex patterns (from parse.rb) ===

  RFC3339_RE = /\A\s*(-?\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[-+]\d{2}:\d{2})\s*\z/i
  private_constant :RFC3339_RE

  HTTPDATE_TYPE1_RE = /\A\s*(sun|mon|tue|wed|thu|fri|sat)\s*,\s+(\d{2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(-?\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+(gmt)\s*\z/i
  HTTPDATE_TYPE2_RE = /\A\s*(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s*,\s+(\d{2})\s*-\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*-\s*(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+(gmt)\s*\z/i
  HTTPDATE_TYPE3_RE = /\A\s*(sun|mon|tue|wed|thu|fri|sat)\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})\s*\z/i
  # Fast path: simplified Type 1 with generic [a-zA-Z] instead of alternation
  FAST_HTTPDATE_TYPE1_RE = /\A\s*([a-zA-Z]{3}),\s+(\d{2})\s+([a-zA-Z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+(GMT)\s*\z/i
  private_constant :HTTPDATE_TYPE1_RE, :HTTPDATE_TYPE2_RE, :HTTPDATE_TYPE3_RE,
                   :FAST_HTTPDATE_TYPE1_RE

  # Wday lookup from abbreviated day name (3-char lowercase key)
  HTTPDATE_WDAY = {'sun'=>0,'mon'=>1,'tue'=>2,'wed'=>3,'thu'=>4,'fri'=>5,'sat'=>6}.freeze
  HTTPDATE_FULL_WDAY = {'sunday'=>0,'monday'=>1,'tuesday'=>2,'wednesday'=>3,'thursday'=>4,'friday'=>5,'saturday'=>6}.freeze
  private_constant :HTTPDATE_WDAY, :HTTPDATE_FULL_WDAY

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

  # Character class flags
  HAVE_ALPHA = 1
  HAVE_DIGIT = 2
  HAVE_DASH  = 4
  HAVE_DOT   = 8
  HAVE_SLASH = 16
  HAVE_COLON = 32
  private_constant :HAVE_ALPHA, :HAVE_DIGIT, :HAVE_DASH, :HAVE_DOT, :HAVE_SLASH, :HAVE_COLON

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

  # Specs that produce numeric output (used by NUM_PATTERN_P lookahead)
  STRPTIME_NUMERIC_SPECS = 'CDdeFGgHIjkLlMmNQRrSsTUuVvWwXxYy'.freeze
  private_constant :STRPTIME_NUMERIC_SPECS

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

  # O(1) boolean lookup table for numeric specs (used by _sp_num_p_b?)
  # Includes both STRPTIME_NUMERIC_SPECS chars and digits '0'..'9'
  STRPTIME_NUMERIC_SPEC_SET = Array.new(256, false).tap { |a|
    STRPTIME_NUMERIC_SPECS.each_byte { |b| a[b] = true }
    48.upto(57) { |b| a[b] = true } # '0'..'9'
  }.freeze
  private_constant :STRPTIME_NUMERIC_SPEC_SET

  # O(1) boolean lookup table for E-modifier valid specs
  STRPTIME_E_VALID_SET = Array.new(256, false).tap { |a|
    'cCxXyY'.each_byte { |b| a[b] = true }
  }.freeze
  private_constant :STRPTIME_E_VALID_SET

  # O(1) boolean lookup table for O-modifier valid specs
  STRPTIME_O_VALID_SET = Array.new(256, false).tap { |a|
    'deHImMSuUVwWy'.each_byte { |b| a[b] = true }
  }.freeze
  private_constant :STRPTIME_O_VALID_SET
end
