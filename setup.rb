#!ruby

basedir = File.dirname(__FILE__)
$:.push(basedir)

require 'external/package'
require 'rbconfig'
begin
  require 'rubygems'
rescue LoadError
end

Dir.chdir(basedir)
Package.setup("1.0") {
  name "Swiftcore Analogger"

  translate(:lib, 'lib/' => '')
  translate(:bin, 'bin/' => '')
  lib(*Dir["lib/swiftcore/**/*.rb"])
  ri(*Dir["lib/swiftcore/**/*.rb"])
  bin "bin/analogger"

  unit_test "test/TC_Analogger.rb"
  #unit_test "test/TC_Analogger2.rb"

  true
}
