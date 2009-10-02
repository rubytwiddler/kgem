#!/usr/bin/ruby
#
#   Experimental Script
#

$KCODE = 'Ku'
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_VERSION = "0.1"

# standard libs
# require 'uri'
# require 'net/http'
# require 'open-uri'
require 'fileutils'

# additional libs
require 'korundum4'

#
# my libraries and programs
#
require "mylibs"

#--------------------------------------------------------------------
#
#
#
class MainWindow < KDE::MainWindow

    def initialize
        super(nil)

        setDefaultStyle
        createWidgets
    end

    def createWidgets
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')
        @tbl = Qt::TableWidget.new(2000,4)
        @tbl.setHorizontalHeaderLabels(['package', 'version', 'description', 'status'])

        # layout
        topWidget = VBoxLayoutWidget.new do |w|
                w.addWidget(@tbl)
                w.addWidgetWithNilStretch(@okBtn)
            end
        setCentralWidget(topWidget)
    end


    def setDefaultStyle
        myStyle = <<-EOF


QScrollBar:vertical {
    border: 1px solid rgb(60,60,60);
}


QScrollBar::handle:vertical {
    min-height: 16px;
}



EOF
        $app.styleSheet = myStyle
     end


end


#
#    main start
#
about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION)
KDE::CmdLineArgs.init(ARGV, about)

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
