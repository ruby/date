# frozen_string_literal: true

require_relative "lib/date/version"

Gem::Specification.new do |s|
  s.name = "date"
  s.version = Date::VERSION
  s.summary = "The official date library for Ruby."
  s.description = "The official date library for Ruby."

  s.require_path = %w{lib}

  s.files = Dir["README.md", "COPYING", "BSDL", "lib/**/*.rb",
                "ext/date/prereq.mk", "ext/date/zonetab.list"]

  s.required_ruby_version = ">= 3.3.0"

  s.authors = ["Tadayoshi Funaba"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/date"
  s.licenses = ["Ruby", "BSD-2-Clause"]

  s.metadata["changelog_uri"] = s.homepage + "/releases"
end
