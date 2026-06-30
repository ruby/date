# frozen_string_literal: true

# Shared methods used across multiple Date implementation files.
class Date
  # Generate a case-insensitive 3-byte integer key from a 3-character string.
  # Used for O(1) abbreviated day/month name lookup in parse.rb and strptime.rb.
  # Key = (byte0_lower << 16) | (byte1_lower << 8) | byte2_lower
  def self.compute_3key(s)
    b0 = s.getbyte(0)
    b1 = s.getbyte(1)
    b2 = s.getbyte(2)
    ((b0 | 0x20) << 16) | ((b1 | 0x20) << 8) | (b2 | 0x20)
  end
  private_class_method :compute_3key
end
