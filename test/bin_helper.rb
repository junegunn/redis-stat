#!/usr/bin/env ruby
# encoding: utf-8

# DISCLAIMER: 
#   Not a real test!
#   Just a helper script for running scripts with local source

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '../lib')
load File.join(File.dirname(__FILE__), '../bin/', File.basename(ARGV.shift))
