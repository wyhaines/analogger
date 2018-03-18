# coding: utf-8
external = File.expand_path(File.join(File.dirname(__FILE__),'..','external'))
puts "EXTERNAL: #{external}"
$LOAD_PATH.unshift(external) unless $LOAD_PATH.include?(external)
require 'minitest/autorun'
require 'rbconfig'
require 'logger'
require 'test_support'
SwiftcoreTestSupport.set_src_dir
require 'swiftcore/Analogger'

class TestAnaloggerLog < Minitest::Test

  def test_log_basics
    log = Swiftcore::Analogger::Log.new({
      Swiftcore::Analogger::Cservice => 'info',
      Swiftcore::Analogger::Clevels =>  Swiftcore::Analogger::DefaultSeverityLevels,
      Swiftcore::Analogger::Clogfile => '/tmp/logfile',
      Swiftcore::Analogger::Ccull =>    true
    })

    assert_equal('info', log.service)
    assert_equal(Swiftcore::Analogger::DefaultSeverityLevels, log.levels)
    assert_equal('/tmp/logfile', log.logfile)
    assert_equal(true, log.cull)
  end

  def test_log_representation
    log = Swiftcore::Analogger::Log.new({
      Swiftcore::Analogger::Cservice => 'info',
      Swiftcore::Analogger::Clevels =>  Swiftcore::Analogger::DefaultSeverityLevels,
      Swiftcore::Analogger::Clogfile => '/tmp/logfile',
      Swiftcore::Analogger::Ccull =>    true
    })

    assert_equal(
        "service: #{log.service}\nlevels: #{log.levels.inspect}\nlogfile: #{log.logfile}\ncull: #{log.cull}\n",
        log.to_s)
  end

  def test_log_comparisons
    log_a = Swiftcore::Analogger::Log.new({
      Swiftcore::Analogger::Cservice => 'info',
      Swiftcore::Analogger::Clevels =>  Swiftcore::Analogger::DefaultSeverityLevels,
      Swiftcore::Analogger::Clogfile => '/tmp/logfile',
      Swiftcore::Analogger::Ccull =>    true
    })

    log_b= Swiftcore::Analogger::Log.new({
      Swiftcore::Analogger::Cservice => 'info',
      Swiftcore::Analogger::Clevels =>  Swiftcore::Analogger::DefaultSeverityLevels,
      Swiftcore::Analogger::Clogfile => '/tmp/logfile',
      Swiftcore::Analogger::Ccull =>    false
    })

    assert_equal(log_a, log_a)
    assert(log_a != log_b)
  end

end
