# frozen_string_literal: true

class Time
  # call-seq:
  #    t.to_time  ->  time
  #
  # Returns self.
  def to_time
    self
  end unless method_defined?(:to_time)

  # call-seq:
  #    t.to_date  ->  date
  #
  # Returns a Date object which denotes self.
  def to_date
    jd = Date.__send__(:gregorian_to_jd, year, mon, mday)
    Date.__send__(:_new_from_jd, jd, Date::ITALY)
  end unless method_defined?(:to_date)

  # call-seq:
  #    t.to_datetime  ->  datetime
  #
  # Returns a DateTime object which denotes self.
  def to_datetime
    jd = Date.__send__(:gregorian_to_jd, year, mon, mday)
    dt = DateTime.allocate
    dt.__send__(:_init_datetime, jd, hour, min, sec, subsec, utc_offset, Date::ITALY)
    dt
  end unless method_defined?(:to_datetime)
end
