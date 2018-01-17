# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'swiftcore/Analogger/version'

Gem::Specification.new do |spec|
  spec.name          = "Analogger"
  spec.version       = Swiftcore::Analogger::VERSION
  spec.authors       = ["Kirk Haines"]
  spec.email         = ["wyhaines@gmail.com"]

  spec.summary       = %q{Analogger is a fast, stable, simple central logging service/client. }
  spec.description   = %q{Analogger provides a fast, very stable central logging service capable of handling heavy logging loads. }
  spec.homepage      = "http://github.com/wyhaines/analogger"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.extensions       = %w[]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 11.0"
  spec.add_development_dependency "minitest", "~> 5"
  spec.add_runtime_dependency "eventmachine", "~> 1.2"
end