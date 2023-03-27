# frozen_string_literal: true
# date.rb: Written by Tadayoshi Funaba 1998-2011

require 'date_core'

class Date
  VERSION = "3.3.3" # :nodoc:

  # call-seq:
  #   infinite? -> false
  #
  # Returns +false+
  def infinite? = false

  class Infinity < Numeric # :nodoc:

    def initialize(d=1) = @d = d <=> 0

    def d = @d

    protected :d

    def zero? = false
    def finite? = false
    def infinite? = d.nonzero?
    def nan? = d.zero?

    def abs = self.class.new

    def -@ = self.class.new(-d)
    def +@ = self.class.new(+d)

    def <=>(other)
      case other
      when Infinity; return d <=> other.d
      when Float::INFINITY; return d <=> 1
      when -Float::INFINITY; return d <=> -1
      when Numeric; return d
      else
        begin
          l, r = other.coerce(self)
          return l <=> r
        rescue NoMethodError
        end
      end
      nil
    end

    def coerce(other)
      case other
      when Numeric; return -d, d
      else
        super
      end
    end

    def to_f
      return 0 if @d == 0
      if @d > 0
        Float::INFINITY
      else
        -Float::INFINITY
      end
    end

  end

end
