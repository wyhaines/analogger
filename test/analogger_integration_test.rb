# frozen_string_literal: true

external = File.expand_path(File.join(File.dirname(__FILE__), '..', 'external'))
puts "EXTERNAL: #{external}"
$LOAD_PATH.unshift(external) unless $LOAD_PATH.include?(external)
require 'minitest/autorun'
require 'rbconfig'
require 'logger'
require 'test_support'
SwiftcoreTestSupport.set_src_dir
require 'swiftcore/Analogger/Client'

class TestAnalogger < Minitest::Test
  # TODO: This testing framework is ancient. Better testing should be written.
  # The tests are all basically functional tests, for better or for worse.
  #
  TestDir = SwiftcoreTestSupport.test_dir(__FILE__)

  def setup
    Dir.chdir(TestDir)
    SwiftcoreTestSupport.announce(:analogger, 'Analogger Tests')

    @rubybin = File.join(::RbConfig::CONFIG['bindir'], ::RbConfig::CONFIG['ruby_install_name'])
    @rubybin << ::RbConfig::CONFIG['EXEEXT']
    ENV['PATH'] = "#{::RbConfig::CONFIG['bindir']}:#{File.expand_path(File.join(TestDir, '..', 'bin'))}:#{ENV['PATH']}"
    ENV['RUBYLIB'] = '../lib'
  end

  def test_hup
    puts "\n\nTesting HUP\n\n"
    @analogger_pid = SwiftcoreTestSupport.create_process(
      dir: '.',
      cmd: ['../bin/analogger -c analogger.cnf -w log/analogger.pid']
    )

    puts "GOT PID of #{@analogger_pid}"
    sleep 3

    pid = File.read('log/analogger.pid').chomp

    assert_equal(@analogger_pid.to_s, pid)

    puts 'Delivering test messages.'

    levels = ['debug', 'info', 'warn']

    logger = Swiftcore::Analogger::Client.new('idontmatch', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['a', 'b', 'c']

    logger = Swiftcore::Analogger::Client.new('a', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    logger = Swiftcore::Analogger::Client.new('b', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    Process.kill 'SIGHUP', @analogger_pid
    sleep(1)

    pid = File.read('log/analogger.pid').chomp
    assert_equal(@analogger_pid.to_s, pid) # PID should not have changed.

    levels = ['info', 'warn', 'fatal']

    logger = Swiftcore::Analogger::Client.new('c', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['info', 'junk']

    logger = Swiftcore::Analogger::Client.new('d', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    logger = Swiftcore::Analogger::Client.new('stderr', '127.0.0.1', '47990')

    5.times { |x| logger.log('info', "Logging to STDERR ##{x}") }

    puts "Waiting for log sync.\n\n"
    sleep 2

    puts "\nChecking results.\n\n"
    logfile = File.read('log/default.log')
    assert(
      logfile =~ /idontmatch|debug|abc123/,
      "Default log doesn't appear to have the expected message: idontmatch|debug|abc123"
    )
    assert(
      logfile =~ /idontmatch|debug|Last message repeated 2 times/,
      "Default log doesn't appear to have the expected message: idontmatch|debug|Last message repeated 2 times"
    )

    logfile = File.read('log/a.log')
    assert(logfile =~ /a|a|abc123/, "Log doesn't appear to have the expected message: a|a|abc123")
    assert(logfile =~ /a|b|abc123/, "Log doesn't appear to have the expected message: a|b|abc123")
    assert(logfile =~ /a|c|abc123/, "Log doesn't appear to have the expected message: a|c|abc123")
    assert(logfile =~ /b|a|abc123/, "Log doesn't appear to have the expected message: b|a|abc123")
    assert(logfile =~ /b|b|abc123/, "Log doesn't appear to have the expected message: b|b|abc123")
    assert(logfile =~ /b|c|abc123/, "Log doesn't appear to have the expected message: b|c|abc123")

    logfile = File.read('log/c.log')
    assert(logfile =~ /c|info|abc123/, "Log doesn't appear to have the expected message: c|info|abc123")
    assert(logfile =~ /c|warn|abc123/, "Log doesn't appear to have the expected message: c|warn|abc123")
    assert(logfile =~ /c|fatal|abc123/, "Log doesn't appear to have the expected message: c|fatal|abc123")

    logfile = File.read('log/d.log')
    assert(logfile =~ /d|info|abc123/, "Log doesn't appear to have the expected message: d|info|abc123")
    assert(logfile !~ /junk/, 'Log file has a message in it that should have been dropped.')
    teardown
  end

  def test_usr2
    puts "\n\nTesting USR2\n\n"
    @analogger_pid = SwiftcoreTestSupport.create_process(
      dir: '.',
      cmd: ['../bin/analogger -c analogger.cnf -w log/analogger.pid']
    )
    sleep 3
    logger = nil

    pid = File.read('log/analogger.pid').chomp

    assert_equal(@analogger_pid.to_s, pid)

    puts 'Delivering test messages.'

    levels = ['debug', 'info', 'warn']

    logger = Swiftcore::Analogger::Client.new('idontmatch', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['a', 'b', 'c']

    logger = Swiftcore::Analogger::Client.new('a', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    logger = Swiftcore::Analogger::Client.new('b', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    sleep(1)
    Process.kill 'SIGUSR2', @analogger_pid
    sleep(1)

    pid = File.read('log/analogger.pid').chomp
    assert_equal(@analogger_pid.to_s, pid)

    levels = ['info', 'warn', 'fatal']

    logger = Swiftcore::Analogger::Client.new('c', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['info', 'junk']

    logger = Swiftcore::Analogger::Client.new('d', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    logger = Swiftcore::Analogger::Client.new('stderr', '127.0.0.1', '47990')

    5.times { |x| logger.log('info', "Logging to STDERR ##{x}") }

    puts "Waiting for log sync.\n\n"
    sleep 2

    puts "\nChecking results.\n\n"
    logfile = File.read('log/default.log')
    assert(
      logfile =~ /idontmatch|debug|abc123/,
      "Default log doesn't appear to have the expected message: idontmatch|debug|abc123"
    )
    assert(
      logfile =~ /idontmatch|debug|Last message repeated 2 times/,
      "Default log doesn't appear to have the expected message: idontmatch|debug|Last message repeated 2 times"
    )

    logfile = File.read('log/a.log')
    assert(logfile =~ /a|a|abc123/, "Log doesn't appear to have the expected message: a|a|abc123")
    assert(logfile =~ /a|b|abc123/, "Log doesn't appear to have the expected message: a|b|abc123")
    assert(logfile =~ /a|c|abc123/, "Log doesn't appear to have the expected message: a|c|abc123")
    assert(logfile =~ /b|a|abc123/, "Log doesn't appear to have the expected message: b|a|abc123")
    assert(logfile =~ /b|b|abc123/, "Log doesn't appear to have the expected message: b|b|abc123")
    assert(logfile =~ /b|c|abc123/, "Log doesn't appear to have the expected message: b|c|abc123")

    logfile = File.read('log/c.log')
    assert(logfile =~ /c|info|abc123/, "Log doesn't appear to have the expected message: c|info|abc123")
    assert(logfile =~ /c|warn|abc123/, "Log doesn't appear to have the expected message: c|warn|abc123")
    assert(logfile =~ /c|fatal|abc123/, "Log doesn't appear to have the expected message: c|fatal|abc123")

    logfile = File.read('log/d.log')
    assert(logfile =~ /d|info|abc123/, "Log doesn't appear to have the expected message: d|info|abc123")
    assert(logfile !~ /junk/, 'Log file has a message in it that should have been dropped.')
    teardown
  end

  def test_analogger
    puts "\n\nTesting regular operation\n\n"
    @analogger_pid = SwiftcoreTestSupport.create_process(
      dir: '.',
      cmd: ['../bin/analogger -c analogger.cnf -w log/analogger.pid']
    )
    sleep 3

    pid = File.read('log/analogger.pid').chomp

    assert_equal(@analogger_pid.to_s, pid)

    puts 'Delivering test messages.'

    levels = ['debug', 'info', 'warn']

    logger = Swiftcore::Analogger::Client.new('idontmatch', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['a', 'b', 'c']

    logger = Swiftcore::Analogger::Client.new('a', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    logger = Swiftcore::Analogger::Client.new('b', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['info', 'warn', 'fatal']

    logger = Swiftcore::Analogger::Client.new('c', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    levels = ['info', 'junk']

    logger = Swiftcore::Analogger::Client.new('d', '127.0.0.1', '47990')

    levels.each do |level|
      logger.log(level, 'abc123')
    end

    logger = Swiftcore::Analogger::Client.new('stderr', '127.0.0.1', '47990')

    5.times { |x| logger.log('info', "Logging to STDERR ##{x}") }

    puts "Waiting for log sync.\n\n"
    sleep 2

    puts "\nChecking results.\n\n"
    logfile = File.read('log/default.log')
    assert(
      logfile =~ /idontmatch|debug|abc123/,
      "Default log doesn't appear to have the expected message: idontmatch|debug|abc123"
    )
    assert(
      logfile =~ /idontmatch|debug|Last message repeated 2 times/,
      "Default log doesn't appear to have the expected message: idontmatch|debug|Last message repeated 2 times"
    )

    logfile = File.read('log/a.log')
    assert(logfile =~ /a|a|abc123/, "Log doesn't appear to have the expected message: a|a|abc123")
    assert(logfile =~ /a|b|abc123/, "Log doesn't appear to have the expected message: a|b|abc123")
    assert(logfile =~ /a|c|abc123/, "Log doesn't appear to have the expected message: a|c|abc123")
    assert(logfile =~ /b|a|abc123/, "Log doesn't appear to have the expected message: b|a|abc123")
    assert(logfile =~ /b|b|abc123/, "Log doesn't appear to have the expected message: b|b|abc123")
    assert(logfile =~ /b|c|abc123/, "Log doesn't appear to have the expected message: b|c|abc123")

    logfile = File.read('log/c.log')
    assert(logfile =~ /c|info|abc123/, "Log doesn't appear to have the expected message: c|info|abc123")
    assert(logfile =~ /c|warn|abc123/, "Log doesn't appear to have the expected message: c|warn|abc123")
    assert(logfile =~ /c|fatal|abc123/, "Log doesn't appear to have the expected message: c|fatal|abc123")

    logfile = File.read('log/d.log')
    assert(logfile =~ /d|info|abc123/, "Log doesn't appear to have the expected message: d|info|abc123")
    assert(logfile !~ /junk/, 'Log file has a message in it that should have been dropped.')
    teardown

    require 'benchmark'

    speedtest('short messages', '0123456789')
    speedtest(
      'larger messages',
      '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789'
    )
    speedtest(
      'Fail Analogger, continue logging locally, and monitor for Analogger return, then drain queue of local logs',
      '00000',
      0.9995
    )
    logger_speedtest('short messages', '0123456789')
    logger_speedtest(
      'larger messages',
      '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789'
    )
  end

  def speedtest(label, message, random_failures = 1)
    puts "Analogger Speedtest -- #{label}"
    message = message.dup
    @analogger_pid = SwiftcoreTestSupport.create_process(
      dir: '.',
      cmd: ['../bin/analogger -c analogger.cnf -w log/analogger.pid']
    )
    sleep 3

    _speedtest(message, random_failures)
  end

  def _speedtest(message, random_failures)
    count = 100_000
    logger = Swiftcore::Analogger::Client.new('speed', '127.0.0.1', '47990')
    lvl = 'info'
    puts "Testing #{count} messages of #{message.length} bytes each."
    start = Time.now
    if random_failures < 1
      count.times do |_cnt|
        # At some random point, kill the Analogger process.
        if @analogger_pid && (rand > random_failures)
          Process.kill 'SIGTERM', @analogger_pid
          Process.wait @analogger_pid
          @analogger_pid = nil
        end

        # The logger client will detect that Analogger is down, and start logging locally.
        logger.log(lvl, message)

        message.next! # Increment messages
      end
    else
      count.times { logger.log(lvl, message) }
    end
    total = Time.now - start

    @analogger_pid ||= SwiftcoreTestSupport.create_process(
      dir: '.',
      cmd: ['../bin/analogger -c analogger.cnf -w log/analogger.pid']
    )
    sleep 3

    rate = count / total
    puts "\nMessage rate: #{rate}/second (#{total})\n\n"
    sleep 5
    teardown
  end

  def logger_speedtest(label, message)
    count = 100_000
    puts "Ruby Logger Speedtest (local file logging only) -- #{label}"
    puts "Testing 100000 messages of #{message.length} bytes each."
    logger = Logger.new('log/ra')
    start = total = nil
    Benchmark.bm do |bm|
      bm.report do
        start = Time.now
        count.times { logger.info(message) }
        total = Time.now - start
      end
    end
    rate = count / total
    puts "\nMessage rate: #{rate}/second (#{total})\n\n"
    logger.close
    File.delete('log/ra')
  end

  def teardown
    @analogger_pid ||= nil
    return unless @analogger_pid

    Process.kill 'SIGTERM', @analogger_pid
    Process.wait @analogger_pid
    Dir['log/*'].each { |fn| File.delete(fn) }
  end
end
