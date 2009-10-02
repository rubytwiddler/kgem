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
    slots   :updateGemList
    
    def initialize
        super(nil)
        createWidgets
    end

    def createWidgets
        @goBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'GO!')
        @quitBtn = KDE::PushButton.new(KDE::Icon.new('dialog-close'), 'Quit')
        connect(@quitBtn,SIGNAL(:clicked), $app, SLOT(:quit)) 
        connect(@goBtn,SIGNAL(:clicked), self, SLOT(:updateGemList))
        @tbl = Qt::TableWidget.new(1000,4)
        @tbl.setHorizontalHeaderLabels(['package', 'version', 'description', 'status'])

        # layout
        topWidget = VBoxLayoutWidget.new do |w|
                w.addWidget(@tbl)
                w.addWidgetWithNilStretch(nil, @goBtn, @quitBtn)
            end
        setCentralWidget(topWidget)
    end


    def updateGemList
        catch (:Canceled) do
            makeGemList
        end
    end
    
    GemReadRange = 'a'..'z'
    GemReadRangeSize = GemReadRange.count
    # store gem list in @gemList
    def makeGemList
        progressHalf = GemReadRangeSize
        @progressDlg = Qt::ProgressDialog.new
        @progressDlg.labelText = "Processing Gem List"
        @progressDlg.setRange(0, progressHalf*2)
        @progressDlg.setWindowModality(Qt::WindowModal)

        gemf = openGemList

        begin
            @gemList =[]
            desc = ''
            gem = nil
            while line = gemf.gets
                case line
                when /^(\w.*)/ then
                    if gem then
                        gem.description = desc.strip
                        @gemList << gem
                    end
                    gem = Gem.new($1)
                    desc = ''
                when /\s+Author:\s*(.*)\s*/i
                    gem.author = $1
                when /\s+Rubyforge:\s*(.*)\s*/i
                    gem.rubyforge = $1
                when /\s+Homepage:\s*(.*)\s*/i
                    gem.homepage = $1
                else
                    desc += line.strip + '\n'
                end
            end
            gem.description = desc.strip
            @gemList << gem
        ensure
            gemf.close
            @progressDlg.setValue(progressHalf*2)
        end
    end


    # open cache data in tmp dir
    def openGemList
        @progressDlg.forceShow
        @progressDlg.labelText = "Loading Gem List from Net."
        cnt = 0
        GemReadRange.each do |c|
            puts "processing '#{c}'"
            cnt += 1
            sleep(1)
            throw :Canceled if @progressDlg.wasCanceled
            @progressDlg.setValue(cnt)
        end
        @progressDlg.setValue(GemReadRangeSize)

        open(tmpPath)
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
