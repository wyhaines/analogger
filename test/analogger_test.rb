# frozen_string_literal: true

external = File.expand_path(File.join(File.dirname(__FILE__), '..', 'external'))
$LOAD_PATH.unshift(external) unless $LOAD_PATH.include?(external)
require 'minitest/autorun'
require 'rbconfig'
require 'logger'
require 'test_support'
SwiftcoreTestSupport.set_src_dir
require 'swiftcore/Analogger'

class TestAnaloggerLog < Minitest::Test
  def test_log_basics
    log = Swiftcore::Analogger::Log.new(service: 'info',
                                        levels: Swiftcore::Analogger::DEFAULT_SEVERITY_LEVELS,
                                        destination: '/tmp/logfile',
                                        cull: true)

    assert_equal('info', log.service)
    assert_equal(Swiftcore::Analogger::DEFAULT_SEVERITY_LEVELS, log.levels)
    assert_equal('/tmp/logfile', log.destination)
    assert_equal(true, log.cull)
  end

  def test_log_representation
    log = Swiftcore::Analogger::Log.new(service: 'info',
                                        levels: Swiftcore::Analogger::DEFAULT_SEVERITY_LEVELS,
                                        destination: '/tmp/logfile',
                                        cull: true)

    assert_equal(
      "service: #{log.service}\nlevels: #{log.levels.inspect}\ndestination: #{log.destination}\ncull: #{log.cull}\n",
      log.to_s
)
  end

  def test_log_comparisons
    log_a = Swiftcore::Analogger::Log.new(service: 'info',
                                          levels: Swiftcore::Analogger::DEFAULT_SEVERITY_LEVELS,
                                          destination: '/tmp/logfile',
                                          cull: true)

    log_b = Swiftcore::Analogger::Log.new(service: 'info',
                                          levels: Swiftcore::Analogger::DEFAULT_SEVERITY_LEVELS,
                                          destination: '/tmp/logfile',
                                          cull: false)

    assert_equal(log_a, log_a)
    assert(log_a != log_b)
  end
end
