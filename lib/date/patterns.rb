# frozen_string_literal: true

class Date
  # TIME_PAT
  # Regular expression pattern for C's parse_time.
  # $1: entire time portion
  # $2: time zone portion (optional)
  #
  # In the zone portion, [A-Za-z] is used for case-sensitive alphabetic characters.
  TIME_PAT = /
    (                                   # $1: whole time
      \d+\s*                            # hour (required)
      (?:
        (?:                             # Branch A: colon-separated
          :\s*\d+                       # :min
          (?:
            \s*:\s*\d+(?:[,.]\d*)?      # :sec[.frac]
          )?
        |                               # Branch B: h m s separated
          h(?:\s*\d+m?
            (?:\s*\d+s?)?
          )?
        )
        (?:                             # AM PM suffix (optional)
          \s*[ap](?:m\b|\.m\.)
        )?
      |                                 # Branch C: Only AM PM
        [ap](?:m\b|\.m\.)
      )
    )
    (?:                                 # Time Zone (optional)
      \s*
      (                                 # $2: time zone
        (?:gmt|utc?)?[-+]\d+
        (?:[,.:]\d+(?::\d+)?)?
      |
        [[:alpha:].\s]+
        (?:standard|daylight)\stime\b
      |
        [[:alpha:]]+(?:\sdst)?\b
      )
    )?
  /xi
  private_constant :TIME_PAT

  # TIME_DETAIL_PAT
  # Pattern for detailed parsing of time portion
  TIME_DETAIL_PAT = /
    \A(\d+)\s*                          # $1 hour
    (?:
      :\s*(\d+)                         # $2 min (colon)
      (?:\s*:\s*(\d+)([,.]\d*)?)?       # $3 sec, $4 frac (colon)
    |
      h(?:\s*(\d+)m?                    # $5 min (h)
        (?:\s*(\d+)s?)?                 # $6 sec (h)
      )?
    )?
    (?:\s*([ap])(?:m\b|\.m\.))?         # $7 am pm
  /xi
  private_constant :TIME_DETAIL_PAT

  # PARSE_DAY_PAT
  # Non-TIGHT pattern for parse_day.
  # Matches abbreviated day name and consumes trailing characters
  # (e.g., "urday" in "Saturday") so they get replaced by subx.
  PARSE_DAY_PAT = /\b(sun|mon|tue|wed|thu|fri|sat)[^-\/\d\s]*/i
  private_constant :PARSE_DAY_PAT

  # ERA1_PAT
  # Pattern for AD, A.D.
  ERA1_PAT = /\b(a(?:d\b|\.d\.))(?!(?<!\.)[a-z])/i
  private_constant :ERA1_PAT

  # ERA2_PAT
  # Pattern for CE, C.E., BC, B.C., BCE, B.C.E.
  ERA2_PAT = /\b(c(?:e\b|\.e\.)|b(?:ce\b|\.c\.e\.)|b(?:c\b|\.c\.))(?!(?<!\.)[a-z])/i
  private_constant :ERA2_PAT

  # PARSE_EU_PAT
  # European format: DD Mon [era] [YYYY]
  PARSE_EU_PAT = /
    ('?\d+)
    [^\-\d\s]*
    \s*
    (january|february|march|april|may|june|
     july|august|september|october|november|december|
     jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)
    [^\-\d\s']*
    (?:
      \s*
      (?:
        \b
        (c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|
         a(?:d|\.d\.)|b(?:c|\.c\.))
        (?!(?<!\.)[a-z])
      )?
      \s*
      ('?-?\d+(?:(?:st|nd|rd|th)\b)?)
    )?
  /xi
  private_constant :PARSE_EU_PAT

  # PARSE_US_PAT
  # American format: Mon DD[,] [era] [YYYY]
  PARSE_US_PAT = /
    \b
    (january|february|march|april|may|june|
     july|august|september|october|november|december|
     jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)
    [^\-\d\s']*
    \s*
    ('?\d+)
    [^\-\d\s']*
    (?:
      \s*,?
      \s*
      (?:
        \b
        (c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|
         a(?:d|\.d\.)|b(?:c|\.c\.))
        (?!(?<!\.)[a-z])
      )?
      \s*
      ('?-?\d+)
    )?
  /xi
  private_constant :PARSE_US_PAT

  # PARSE_ISO_PAT
  # ISO 8601 extended format: YYYY-MM-DD
  PARSE_ISO_PAT = /('?[-+]?\d+)-(\d+)-('?-?\d+)/
  private_constant :PARSE_ISO_PAT

  # PARSE_JIS_PAT
  # JIS X 0301 format
  PARSE_JIS_PAT = /\b([#{JISX0301_ERA_INITIALS}])(\d+)\.(\d+)\.(\d+)/i
  private_constant :PARSE_JIS_PAT

  # PARSE_VMS11_PAT
  # VMS format: DD-Mon-YYYY
  PARSE_VMS11_PAT = /
    ('?-?\d+)
    -(january|february|march|april|may|june|
      july|august|september|october|november|december|
      jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)
    (?:[^\-\/.])*
    -('?-?\d+)
  /xi
  private_constant :PARSE_VMS11_PAT

  # PARSE_VMS12_PAT
  # VMS format: Mon-DD[-YYYY]
  # C: \b(ABBR_MONTHS)[^-/.]*-('?-?\d+)(?:-('?-?\d+))?
  PARSE_VMS12_PAT = /
    \b
    (january|february|march|april|may|june|
      july|august|september|october|november|december|
      jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)
    (?:[^\-\/.])*
    -('?-?\d+)
    (?:-('?-?\d+))?
  /xi
  private_constant :PARSE_VMS12_PAT

  # PARSE_SLA_PAT
  # Slash-separated format
  PARSE_SLA_PAT = /('?-?\d+)\/\s*('?\d+)(?:\D\s*('?-?\d+))?/
  private_constant :PARSE_SLA_PAT

  # PARSE_DOT_PAT
  # Dot-separated format
  PARSE_DOT_PAT = /('?-?\d+)\.\s*('?\d+)\.\s*('?-?\d+)/
  private_constant :PARSE_DOT_PAT

  # PARSE_ISO21_PAT
  # ISO 8601 week date
  PARSE_ISO21_PAT = /\b(\d{2}|\d{4})?-?w(\d{2})(?:-?(\d))?\b/i
  private_constant :PARSE_ISO21_PAT

  # PARSE_ISO22_PAT
  # ISO 8601 week day only
  PARSE_ISO22_PAT = /-w-(\d)\b/i
  private_constant :PARSE_ISO22_PAT

  # PARSE_ISO23_PAT
  # ISO 8601 month and day
  PARSE_ISO23_PAT = /--(\d{2})?-(\d{2})\b/
  private_constant :PARSE_ISO23_PAT

  # PARSE_ISO24_PAT
  # ISO 8601 month only or month and day
  PARSE_ISO24_PAT = /--(\d{2})(\d{2})?\b/
  private_constant :PARSE_ISO24_PAT

  # PARSE_ISO25_PAT0 and PARSE_ISO25_PAT
  # ISO 8601 year and ordinal day
  PARSE_ISO25_PAT0 = /[,.](\d{2}|\d{4})-\d{3}\b/
  private_constant :PARSE_ISO25_PAT0
  PARSE_ISO25_PAT = /\b(\d{2}|\d{4})-(\d{3})\b/
  private_constant :PARSE_ISO25_PAT

  # PARSE_ISO26_PAT0 and PARSE_ISO26_PAT
  # ISO 8601 ordinal day only
  PARSE_ISO26_PAT0 = /\d-\d{3}\b/
  private_constant :PARSE_ISO26_PAT0
  PARSE_ISO26_PAT = /\b-(\d{3})\b/
  private_constant :PARSE_ISO26_PAT

  # PARSE_YEAR_PAT
  # Apostrophe-prefixed year
  PARSE_YEAR_PAT = /'(\d+)\b/
  private_constant :PARSE_YEAR_PAT

  # PARSE_MON_PAT
  # Month name only
  PARSE_MON_PAT = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\S*/i
  private_constant :PARSE_MON_PAT

  # PARSE_MDAY_PAT
  # Day with ordinal suffix
  PARSE_MDAY_PAT = /(\d+)(st|nd|rd|th)\b/i
  private_constant :PARSE_MDAY_PAT

  # PARSE_DDD_PAT
  # Continuous digit string
  PARSE_DDD_PAT = /
    ([-+]?)
    (\d{2,14})
    (?:
      \s*
      t?
      \s*
      (\d{2,6})?
      (?:[,.](\d*))?
    )?
    (?:
      \s*
      (
        z\b
      |
        [-+]\d{1,4}\b
      |
        \[[-+]?\d[^\]]*\]
      )
    )?
  /xi
  private_constant :PARSE_DDD_PAT

  # PARSE_BC_PAT
  # Pattern for parse_bc (non-TIGHT post-processing).
  # Matches standalone BC/BCE/B.C./B.C.E. and sets _bc flag.
  PARSE_BC_PAT = /\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)/i
  private_constant :PARSE_BC_PAT

  # PARSE_FRAG_PAT
  # Pattern for parse_frag (non-TIGHT post-processing).
  # Matches a standalone 1-2 digit number in the remaining string.
  PARSE_FRAG_PAT = /\A\s*(\d{1,2})\s*\z/i
  private_constant :PARSE_FRAG_PAT

  PARSE_RFC2822_PAT = /
    \A\s*(?:(#{ABBR_DAYS_PATTERN})\s*,\s+)?
    (\d{1,2})\s+
    (#{ABBR_MONTHS_PATTERN})\s+
    (-?\d{2,})\s+
    (\d{2}):(\d{2})(?::(\d{2}))?\s*
    ([-+]\d{4}|ut|gmt|e[sd]t|c[sd]t|m[sd]t|p[sd]t|[a-ik-z])\s*\z
  /xi
  private_constant :PARSE_RFC2822_PAT

  PARSE_HTTPDATE_TYPE1_PAT = /
    \A\s*(#{ABBR_DAYS_PATTERN})\s*,\s+
    (\d{2})\s+
    (#{ABBR_MONTHS_PATTERN})\s+
    (-?\d{4})\s+
    (\d{2}):(\d{2}):(\d{2})\s+
    (gmt)\s*\z
  /xi
  private_constant :PARSE_HTTPDATE_TYPE1_PAT

  PARSE_HTTPDATE_TYPE2_PAT = /
    \A\s*(#{DAYS_PATTERN})\s*,\s+
    (\d{2})\s*-\s*
    (#{ABBR_MONTHS_PATTERN})\s*-\s*
    (\d{2})\s+
    (\d{2}):(\d{2}):(\d{2})\s+
    (gmt)\s*\z
  /xi
  private_constant :PARSE_HTTPDATE_TYPE2_PAT

  PARSE_HTTPDATE_TYPE3_PAT = /
    \A\s*(#{ABBR_DAYS_PATTERN})\s+
    (#{ABBR_MONTHS_PATTERN})\s+
    (\d{1,2})\s+
    (\d{2}):(\d{2}):(\d{2})\s+
    (\d{4})\s*\z
  /xi
  private_constant :PARSE_HTTPDATE_TYPE3_PAT

  PARSE_JISX0301_PAT = /
    \A\s*([mtshr])?(\d{2})\.(\d{2})\.(\d{2})
    (?:t
      (?:(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d*))?)?
      (z|[-+]\d{2}(?::?\d{2})?)?)?
    )?\s*\z
  /xi
  private_constant :PARSE_JISX0301_PAT

  XMLSCHEMA_DATETIME_PAT = /
    \A\s*(-?\d{4,})(?:-(\d{2})(?:-(\d{2}))?)?
    (?:t
      (\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?)?
    (z|[-+]\d{2}:\d{2})?\s*\z
  /xi
  private_constant :XMLSCHEMA_DATETIME_PAT

  XMLSCHEMA_TIME_PAT = /
    \A\s*(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?
    (z|[-+]\d{2}:\d{2})?\s*\z
  /xi
  private_constant :XMLSCHEMA_TIME_PAT

  XMLSCHEMA_TRUNC_PAT = /
    \A\s*(?:--(\d{2})(?:-(\d{2}))?|---(\d{2}))
    (z|[-+]\d{2}:\d{2})?\s*\z
  /xi
  private_constant :XMLSCHEMA_TRUNC_PAT

  RFC3339_PAT = /
    \A\s*(-?\d{4})-(\d{2})-(\d{2})
    (?:t|\s)
    (\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?
    (z|[-+]\d{2}:\d{2})\s*\z
  /xi
  private_constant :RFC3339_PAT

  ISO8601_EXT_DATETIME_PAT = /
    \A\s*(?:
      ([-+]?\d{2,}|-)  # $1: year or '-'
      -(\d{2})?        # $2: mon (optional)
      (?:-(\d{2}))?    # $3: mday (optional)
    |
      ([-+]?\d{2,})?   # $4: year (optional, for ordinal)
      -(\d{3})         # $5: yday
    |
      (\d{4}|\d{2})?   # $6: cwyear (optional)
      -w(\d{2})        # $7: cweek
      -(\d)            # $8: cwday
    |
      -w-(\d)          # $9: cwday only
    )
    (?:t
      (\d{2}):(\d{2})              # $10: hour, $11: min
      (?::(\d{2})(?:[,.](\d+))?)?  # $12: sec, $13: frac
      (z|[-+]\d{2}(?::?\d{2})?)?   # $14: zone
    )?\s*\z
  /xi
  private_constant :ISO8601_EXT_DATETIME_PAT

  ISO8601_BAS_DATETIME_PAT = /
    \A\s*(?:
      ([-+]?(?:\d{4}|\d{2})|--)  # $1: year or '--'
      (\d{2}|-)                  # $2: mon or '-'
      (\d{2})                    # $3: mday
    |
      ([-+]?(?:\d{4}|\d{2}))    # $4: year (ordinal)
      (\d{3})                    # $5: yday
    |
      -(\d{3})                   # $6: yday only
    |
      (\d{4}|\d{2})             # $7: cwyear
      w(\d{2})                   # $8: cweek
      (\d)                       # $9: cwday
    |
      -w(\d{2})                  # $10: cweek (no year)
      (\d)                       # $11: cwday
    |
      -w-(\d)                    # $12: cwday only
    )
    (?:t?
      (\d{2})(\d{2})                  # $13: hour, $14: min
      (?:(\d{2})(?:[,.](\d+))?)?      # $15: sec, $16: frac
      (z|[-+]\d{2}(?:\d{2})?)?        # $17: zone
    )?\s*\z
  /xi
  private_constant :ISO8601_BAS_DATETIME_PAT

  ISO8601_EXT_TIME_PAT = /
    \A\s*(\d{2}):(\d{2})
    (?::(\d{2})(?:[,.](\d+))?
      (z|[-+]\d{2}(:?\d{2})?)?
    )?\s*\z
  /xi
  private_constant :ISO8601_EXT_TIME_PAT

  ISO8601_BAS_TIME_PAT = /
    \A\s*(\d{2})(\d{2})
    (?:(\d{2})(?:[,.](\d+))?
      (z|[-+]\d{2}(\d{2})?)?
    )?\s*\z
  /xi
  private_constant :ISO8601_BAS_TIME_PAT
end
