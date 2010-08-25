#!/usr/bin/ruby

require 'fileutils'

TestFile1 = 'tmp-001.txt'

FileUtils.touch(TestFile1)
sleep(1)
File.unlink(TestFile1)
files = Dir['*.txt']
puts files
files.find do |f|
    f == TestFile1
end and puts "Still Exist!!"
