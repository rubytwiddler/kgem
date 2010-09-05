#!/usr/bin/ruby

$KCODE = 'UTF8'
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_VERSION = "0.0.1"

# standard libs
require 'rubygems'
require 'uri'
require 'fileutils'

# additional libs
require 'korundum4'


#
#    main start
#
if ARGV.size then
    text = ARGV.shift
else
    text = "Hello World"
end

$about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION)
KDE::CmdLineArgs.init(ARGV, $about)

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()

msgHandler = KDE::PassivePopupMessageHandler.new
msgHandler.message(1, text, 'Inormation')



popup = KDE::PassivePopup.new
popup.setPopupStyle(1)
Qt.debug_level = Qt::DebugLevel::High

popup.message(text, Qt::SystemTrayIcon::Information)
KDE::PassivePopup::message(text, Qt::SystemTrayIcon::Information)
Qt.debug_level = Qt::DebugLevel::Off
