# frozen_string_literal: true
#
# Generator for the strftime C-extension comparison fixtures used by
# test_strftime_cext_matrix.rb.
#
# It enumerates every strftime conversion specifier combined with every
# combination of flags, widths, colon counts and locale modifiers, formats a
# fixed Date and DateTime with each, and records the result. The fixtures must
# be regenerated with a Ruby whose +date+ library is the C extension (the
# behavioural reference), NOT the pure-Ruby library under test:
#
#   ruby test/date/gen_strftime_cext_matrix.rb
#
# Each output line is "<format>\t<result>", where <result> is the formatted
# string's #inspect, or "!<ExceptionClass>" when strftime raised. The files are
# gzip-compressed (about 120 KB each).
#
# Fixed reference values: Date.new(2001, 2, 3) and
# DateTime.new(2001, 2, 3, 14, 5, 6, '+07:30').

require 'date'
require 'zlib'

module StrftimeCextMatrix
  SPECS = %w[a A b B c C d D e F g G h H I j k l L m M n N p P Q r R s S t T u U V v w W x X y Y z Z + %].freeze
  FLAG_CHARS = %w[- _ 0 ^ #].freeze
  FLAG_COMBOS = (0...(1 << FLAG_CHARS.length)).map { |mask|
    FLAG_CHARS.each_index.select { |i| mask[i] == 1 }.map { |i| FLAG_CHARS[i] }.join
  }.freeze
  WIDTHS = ['', '1', '10'].freeze
  COLONS = ['', ':', '::', ':::', '::::'].freeze
  LOCALES = ['', 'E', 'O'].freeze

  REFERENCE = {
    'date'     => Date.new(2001, 2, 3),
    'datetime' => DateTime.new(2001, 2, 3, 14, 5, 6, '+07:30'),
  }.freeze

  module_function

  def each_format
    return enum_for(:each_format) unless block_given?
    SPECS.each do |spec|
      FLAG_COMBOS.each do |flags|
        WIDTHS.each do |w|
          COLONS.each do |colons|
            LOCALES.each do |loc|
              yield "%#{flags}#{w}#{colons}#{loc}#{spec}"
            end
          end
        end
      end
    end
  end

  def encode(obj, fmt)
    obj.strftime(fmt).inspect
  rescue StandardError => e
    "!#{e.class}"
  end

  def fixture_path(dir, key)
    File.join(dir, "strftime_cext_#{key}.tsv.gz")
  end

  def generate(dir = __dir__)
    REFERENCE.each do |key, obj|
      Zlib::GzipWriter.open(fixture_path(dir, key)) do |gz|
        each_format { |fmt| gz.write("#{fmt}\t#{encode(obj, fmt)}\n") }
      end
    end
  end
end

StrftimeCextMatrix.generate if $PROGRAM_NAME == __FILE__
