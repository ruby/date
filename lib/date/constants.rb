# encoding: US-ASCII
# frozen_string_literal: true

# Constants
class Date
  HAVE_JD     = 0b00000001  # 1
  HAVE_DF     = 0b00000010  # 2
  HAVE_CIVIL  = 0b00000100  # 4
  HAVE_TIME   = 0b00001000  # 8
  COMPLEX_DAT = 0b10000000  # 128
  private_constant :HAVE_JD, :HAVE_DF, :HAVE_CIVIL, :HAVE_TIME, :COMPLEX_DAT

  MONTHNAMES = [nil, "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"].freeze
  ABBR_MONTHNAMES = [nil, "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].freeze
  DAYNAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  ABBR_DAYNAMES = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  # Pattern constants for regex
  ABBR_DAYS_PATTERN = 'sun|mon|tue|wed|thu|fri|sat'
  DAYS_PATTERN = 'sunday|monday|tuesday|wednesday|thursday|friday|saturday'
  ABBR_MONTHS_PATTERN = 'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec'
  private_constant :ABBR_DAYS_PATTERN, :DAYS_PATTERN, :ABBR_MONTHS_PATTERN

  ITALY     = 2299161 # 1582-10-15
  ENGLAND   = 2361222 # 1752-09-14
  JULIAN    = Float::INFINITY
  GREGORIAN = -Float::INFINITY

  DEFAULT_SG = ITALY
  private_constant :DEFAULT_SG

  MINUTE_IN_SECONDS      = 60
  HOUR_IN_SECONDS        = 3600
  DAY_IN_SECONDS         = 86400
  HALF_DAYS_IN_SECONDS   = DAY_IN_SECONDS / 2
  SECOND_IN_MILLISECONDS = 1000
  SECOND_IN_NANOSECONDS  = 1_000_000_000
  private_constant :MINUTE_IN_SECONDS, :HOUR_IN_SECONDS, :DAY_IN_SECONDS, :SECOND_IN_MILLISECONDS, :SECOND_IN_NANOSECONDS, :HALF_DAYS_IN_SECONDS

  JC_PERIOD0 = 1461     # 365.25 * 4
  GC_PERIOD0 = 146097   # 365.2425 * 400
  CM_PERIOD0 = 71149239 # (lcm 7 1461 146097)
  CM_PERIOD = (0xfffffff / CM_PERIOD0) * CM_PERIOD0
  CM_PERIOD_JCY = (CM_PERIOD / JC_PERIOD0) * 4
  CM_PERIOD_GCY = (CM_PERIOD / GC_PERIOD0) * 400
  private_constant :JC_PERIOD0, :GC_PERIOD0, :CM_PERIOD0, :CM_PERIOD, :CM_PERIOD_JCY, :CM_PERIOD_GCY

  REFORM_BEGIN_YEAR = 1582
  REFORM_END_YEAR   = 1930
  REFORM_BEGIN_JD = 2298874  # ns 1582-01-01
  REFORM_END_JD = 2426355    # os 1930-12-31
  private_constant :REFORM_BEGIN_YEAR, :REFORM_END_YEAR, :REFORM_BEGIN_JD, :REFORM_END_JD

  SEC_WIDTH  = 6
  MIN_WIDTH  = 6
  HOUR_WIDTH = 5
  MDAY_WIDTH = 5
  MON_WIDTH  = 4
  private_constant :SEC_WIDTH, :MIN_WIDTH, :HOUR_WIDTH, :MDAY_WIDTH, :MON_WIDTH

  SEC_SHIFT  = 0
  MIN_SHIFT  = SEC_WIDTH
  HOUR_SHIFT = MIN_WIDTH + SEC_WIDTH
  MDAY_SHIFT = HOUR_WIDTH + MIN_WIDTH + SEC_WIDTH
  MON_SHIFT  = MDAY_WIDTH + HOUR_WIDTH + MIN_WIDTH + SEC_WIDTH
  private_constant :SEC_SHIFT, :MIN_SHIFT, :HOUR_SHIFT, :MDAY_SHIFT, :MON_SHIFT

  PK_MASK = ->(x) { (1 << x) - 1 }
  private_constant :PK_MASK

  # Days in each month (non-leap and leap year)
  MONTH_DAYS = [
    [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze,  # non-leap
    [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze   # leap
  ].freeze
  private_constant :MONTH_DAYS

  YEARTAB = [
    [0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334].freeze,  # non-leap
    [0, 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335].freeze   # leap
  ].freeze
  private_constant :YEARTAB

  # Neri-Schneider algorithm constants
  # JDN of March 1, Year 0 in proleptic Gregorian calendar
  NS_EPOCH = 1721120
  private_constant :NS_EPOCH

  # Days in a 4-year cycle (3 normal years + 1 leap year)
  NS_DAYS_IN_4_YEARS = 1461
  private_constant :NS_DAYS_IN_4_YEARS

  # Days in a 400-year Gregorian cycle (97 leap years in 400 years)
  NS_DAYS_IN_400_YEARS = 146097
  private_constant :NS_DAYS_IN_400_YEARS

  # Years per century
  NS_YEARS_PER_CENTURY = 100
  private_constant :NS_YEARS_PER_CENTURY

  # Multiplier for extracting year within century using fixed-point arithmetic.
  # This is ceil(2^32 / NS_DAYS_IN_4_YEARS) for the Euclidean affine function.
  NS_YEAR_MULTIPLIER = 2939745
  private_constant :NS_YEAR_MULTIPLIER

  # Coefficients for month calculation from day-of-year.
  # Maps day-of-year to month using: month = (NS_MONTH_COEFF * doy + NS_MONTH_OFFSET) >> 16
  NS_MONTH_COEFF  = 2141
  NS_MONTH_OFFSET = 197913
  private_constant :NS_MONTH_COEFF, :NS_MONTH_OFFSET

  # Coefficients for civil date to JDN month contribution.
  # Maps month to accumulated days: days = (NS_CIVIL_MONTH_COEFF * m - NS_CIVIL_MONTH_OFFSET) / 32
  NS_CIVIL_MONTH_COEFF   = 979
  NS_CIVIL_MONTH_OFFSET  = 2919
  NS_CIVIL_MONTH_DIVISOR = 32
  private_constant :NS_CIVIL_MONTH_COEFF, :NS_CIVIL_MONTH_OFFSET, :NS_CIVIL_MONTH_DIVISOR

  # Days from March 1 to December 31 (for Jan/Feb year adjustment)
  NS_DAYS_BEFORE_NEW_YEAR = 306
  private_constant :NS_DAYS_BEFORE_NEW_YEAR

  # Safe bounds for Neri-Schneider algorithm to avoid integer overflow.
  # These correspond to approximately years -1,000,000 to +1,000,000.
  NS_JD_MIN = -364_000_000
  NS_JD_MAX = 538_000_000
  private_constant :NS_JD_MIN, :NS_JD_MAX

  JULIAN_EPOCH_DATE              = "-4712-01-01"
  JULIAN_EPOCH_DATETIME          = "-4712-01-01T00:00:00+00:00"
  JULIAN_EPOCH_DATETIME_RFC2822  = "Mon, 1 Jan -4712 00:00:00 +0000"
  JULIAN_EPOCH_DATETIME_HTTPDATE = "Mon, 01 Jan -4712 00:00:00 GMT"
  private_constant :JULIAN_EPOCH_DATE, :JULIAN_EPOCH_DATETIME, :JULIAN_EPOCH_DATETIME_RFC2822, :JULIAN_EPOCH_DATETIME_HTTPDATE

  JISX0301_ERA_INITIALS = 'mtshr'
  JISX0301_DEFAULT_ERA = 'H'  # obsolete
  private_constant :JISX0301_ERA_INITIALS, :JISX0301_DEFAULT_ERA

  HAVE_ALPHA = 1 << 0
  HAVE_DIGIT = 1 << 1
  HAVE_DASH  = 1 << 2
  HAVE_DOT   = 1 << 3
  HAVE_SLASH = 1 << 4
  private_constant :HAVE_ALPHA, :HAVE_DIGIT, :HAVE_DASH, :HAVE_DOT, :HAVE_SLASH

  # C: default strftime format is US-ASCII
  STRFTIME_DEFAULT_FMT = '%F'
  private_constant :STRFTIME_DEFAULT_FMT

  # strftime spec categories
  NUMERIC_SPECS = %w[Y C y m d j H I M S L N G g U W V u w s Q].freeze
  SPACE_PAD_SPECS = %w[e k l].freeze
  CHCASE_UPPER_SPECS = %w[A a B b h].freeze
  CHCASE_LOWER_SPECS = %w[Z p].freeze
  private_constant :NUMERIC_SPECS, :SPACE_PAD_SPECS,
                   :CHCASE_UPPER_SPECS, :CHCASE_LOWER_SPECS

  # strptime digit-consuming specs
  NUM_PATTERN_SPECS = "CDdeFGgHIjkLlMmNQRrSsTUuVvWwXxYy"
  private_constant :NUM_PATTERN_SPECS

  # Fragment completion table for DateTime parsing
  COMPLETE_FRAGS_TABLE = [
    [:time,       [:hour, :min, :sec].freeze],
    [nil,         [:jd].freeze],
    [:ordinal,    [:year, :yday, :hour, :min, :sec].freeze],
    [:civil,      [:year, :mon, :mday, :hour, :min, :sec].freeze],
    [:commercial, [:cwyear, :cweek, :cwday, :hour, :min, :sec].freeze],
    [:wday,       [:wday, :hour, :min, :sec].freeze],
    [:wnum0,      [:year, :wnum0, :wday, :hour, :min, :sec].freeze],
    [:wnum1,      [:year, :wnum1, :wday, :hour, :min, :sec].freeze],
    [nil,         [:cwyear, :cweek, :wday, :hour, :min, :sec].freeze],
    [nil,         [:year, :wnum0, :cwday, :hour, :min, :sec].freeze],
    [nil,         [:year, :wnum1, :cwday, :hour, :min, :sec].freeze],
  ].each { |a| a.freeze }.freeze
  private_constant :COMPLETE_FRAGS_TABLE
end
