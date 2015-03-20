require 'minitest/autorun'
require 'rbconfig'
require 'logger'
require 'external/test_support'
SwiftcoreTestSupport.set_src_dir
require 'swiftcore/Analogger/EMClient'
require 'eventmachine'

class TC_Analogger2 < Minitest::Test

  @@testdir = SwiftcoreTestSupport.test_dir(__FILE__)

  def setup
    Dir.chdir(@@testdir)
    SwiftcoreTestSupport.announce(:analogger,"Analogger Tests")

    @rubybin = File.join(::RbConfig::CONFIG['bindir'],::RbConfig::CONFIG['ruby_install_name'])
    @rubybin << ::RbConfig::CONFIG['EXEEXT']

    @rubybin19 = '/usr/local/ruby19/bin/ruby'
    @rubybin18 = '/usr/local/ruby185/bin/ruby'
  end

  def test_analogger
    @analogger_pid = SwiftcoreTestSupport::create_process(:dir => '.',:cmd => ["#{@rubybin} -I ../lib ../bin/analogger -c analogger.cnf"])
    sleep 1
    logger = nil

    pid = File.read('log/analogger.pid').chomp

    assert_equal(@analogger_pid.to_s,pid)

    puts "Delivering test messages."

    levels = ['debug','info','warn']

    _test_simple_new
    _test_levels('idontmatch',levels)
    _test_levels('a',['a','b','c'])
    _test_levels('b',['a','b','c'])
    _test_levels('c',['info','warn','fatal'])
    _test_levels('d',['info','junk'])
    _test_levels('stderr',['info','info','info','info','info'])

    puts "Waiting for log sync.\n\n"
    sleep 2

    puts "\nChecking results.\n\n"
    logfile = ''

    logfile = File.read('log/default.log')
    puts "logfile"
    puts logfile
    assert(logfile =~ /idontmatch|debug|abc123/,"Default log doesn't appear to have the expected message: idontmatch|debug|abc123")
    assert(logfile =~ /idontmatch|debug|Last message repeated 2 times/,"Default log doesn't appear to have the expected message: idontmatch|debug|Last message repeated 2 times")

    logfile = ''
    logfile = File.read('log/a.log')
    assert(logfile =~ /a|a|abc123/,"Log doesn't appear to have the expected message: a|a|abc123")
    assert(logfile =~ /a|b|abc123/,"Log doesn't appear to have the expected message: a|b|abc123")
    assert(logfile =~ /a|c|abc123/,"Log doesn't appear to have the expected message: a|c|abc123")
    assert(logfile =~ /b|a|abc123/,"Log doesn't appear to have the expected message: b|a|abc123")
    assert(logfile =~ /b|b|abc123/,"Log doesn't appear to have the expected message: b|b|abc123")
    assert(logfile =~ /b|c|abc123/,"Log doesn't appear to have the expected message: b|c|abc123")

    logfile = ''
    logfile = File.read('log/c.log')
    assert(logfile =~ /c|info|abc123/,"Log doesn't appear to have the expected message: c|info|abc123")
    assert(logfile =~ /c|warn|abc123/,"Log doesn't appear to have the expected message: c|warn|abc123")
    assert(logfile =~ /c|fatal|abc123/,"Log doesn't appear to have the expected message: c|fatal|abc123")

    logfile = ''
    logfile = File.read('log/d.log')
    assert(logfile =~ /d|info|abc123/,"Log doesn't appear to have the expected message: d|info|abc123")
    assert(logfile !~ /junk/,"Log file has a message in it that should have been dropped.")

    teardown

    require 'benchmark'

    speedtest('short messages','0123456789')
    teardown
    speedtest('larger messages','0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789')
    teardown
    speedtest('larger messages','0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789')
  end

  def _test_simple_new
    EM.run_block do
      Swiftcore::Analogger::Client.new('idontmatch','127.0.0.1','47990')
    end
  end

  def _test_levels(service,levels)
    EM.run do
      logger = Swiftcore::Analogger::Client.new(service,'127.0.0.1','47990')
      levels.each do |level|
        logger.log(level,'abc123')
      end
      EM.add_timer(1) {finished_sending(logger)}
    end
  end

  def finished_sending(conn)
    if conn.get_outbound_data_size > 0
      puts "draining #{conn.get_outbound_data_size} bytes"
      EM.add_timer(1) {finished_sending(conn)}
    else
      EM.stop
    end
  end

  def junk

    logger_speedtest('short messages','0123456789')
    teardown
    logger_speedtest('larger messages','0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789')
  end

  def speedtest(label,message)
    puts "Analogger Speedtest -- #{label}"
    @analogger_pid = SwiftcoreTestSupport::create_process(:dir => '.',:cmd => ["#{@rubybin} -I ../lib ../bin/analogger -c analogger2.cnf"])
    puts "Starting #{@analogger_pid}"
    sleep 1
    #@analogger_pid = SwiftcoreTestSupport::create_process(:dir => '.',:cmd => ["#{@rubybin18} ../bin/analogger -c analogger2.cnf"])
    logger = nil
    puts "Entering event loop"
    real_start = Time.now
    EM.run do
      logger = Swiftcore::Analogger::Client.new('speed','127.0.0.1','47990')
      lvl = 'info'
      puts "Testing 500000 messages of #{message.length} bytes each."
      start = total = nil
      Benchmark.bm do |bm|
        bm.report { start = Time.now; 500000.times { logger.log(lvl,message) }; total = Time.now - start}
      end
      rate = 500000 / total
      puts "\nMessage rate: #{rate}/second (#{total})\n\n"
      EM.add_timer(1) {finished_sending(logger)}
    end
    real_end = Time.now
    puts "Real rate (#{real_end - real_start} seconds): #{500000/(real_end - real_start)}"
  end

  def logger_speedtest(label,message)
    puts "Ruby Logger Speedtest -- #{label}"
    puts "Testing 100000 messages of #{message.length} bytes each."
    logger = Logger.new('log/ra')
    start = total = nil
    Benchmark.bm do |bm|
      bm.report { start = Time.now; 100000.times { logger.info(message) }; total = Time.now - start}
    end
    rate = 100000 / total
    puts "\nMessage rate: #{rate}/second (#{total})\n\n"
    logger.close
    File.delete('log/ra')
  end

  def teardown
    puts "Killing #{@analogger_pid}"
    Process.kill "SIGTERM",@analogger_pid
    Process.wait @analogger_pid
    Dir['log/*'].each {|fn| File.delete(fn)}
    sleep 1
  rescue
  end

end
