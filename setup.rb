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

	translate(:lib, 'src/' => '')
	translate(:bin, 'bin/' => '')
	lib(*Dir["src/swiftcore/**/*.rb"])
	ri(*Dir["src/swiftcore/**/*.rb"])
	bin "bin/analogger"

	unit_test "test/TC_Analogger.rb"
	#unit_test "test/TC_Analogger2.rb"
	
	true
}
