#!/usr/bin/ruby

require 'rubygems'
require 'rubygems/gem_runner'
require 'rubygems/exceptions'

required_version = Gem::Requirement.new "> 1.8.3"

unless required_version.satisfied_by? Gem.ruby_version then
  abort "Expected Ruby Version #{required_version}, was #{Gem.ruby_version}"
end

#--------------------------------------------------------------------------
#
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_VERSION = "0.1"

# standard libs
require 'fileutils'

# additional libs
require 'korundum4'

#
# my libraries and programs
#
require "mylibs"


#--------------------------------------------------------------------------
#
#
class ChooseListDlg < Qt::Dialog
    def initialize(parent)
        super(parent)
        self.windowTitle = 'RubyGem Asking Choose from List.'

        # createWidget
        @msgLine = Qt::TextEdit.new
        @msgLine.readOnly = true
        @msgLine.minimumHeight = 15
        @table = Qt::TableWidget.new(0,1)
        @table.horizontalHeader.stretchLastSection = true
        @table.selectionMode = Qt::AbstractItemView::SingleSelection  # seg fault
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK') do |w|
            connect(w, SIGNAL(:clicked), self, SLOT(:accept))
        end


        # layout
        layout.dispose if layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLine)
            l.addWidget(@table)
            l.addWidgetAtRight(@okBtn)
        end
        lo.setStretch(0, 0)
        lo.setStretch(1, 1)
        setLayout(lo)
    end

    def ask(question, list)
        @msgLine.clear
        @msgLine.append( question )
        @table.clearContents
        @table.rowCount = list.length
        btm = list.length-1
        list.each_with_index do |l, r|
            item = Qt::TableWidgetItem.new(l)
            item.flags = 1 | 32     # Qt::GraphicsItem::ItemIsSelectable | Qt::GraphicsItem::ItemIsEnabled
            @table.setItem(r, 0, item)
        end
        @table.setRangeSelected(Qt::TableWidgetSelectionRange.new(btm,0, btm,0), true)
        exec
        return nil, nil unless @table.currentItem
        row = @table.currentItem.row
        [list[row], row]
    end
end

class AskDlg < Qt::Dialog
    def initialize(parent)
        super(parent)
        self.windowTitle = 'RubyGem Asking.'

        # createWidget
        @msgLine = Qt::TextEdit.new
        @msgLine.readOnly = true
        @lineEdit = Qt::LineEdit.new
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK') do |w|
            connect(w, SIGNAL(:clicked), self, SLOT(:accept))
        end

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLine)
            l.addWidget(@lineEdit)
            l.addWidgetAtRight(@okBtn)
        end
        setLayout(lo)
    end

    def ask(question)
        @msgLine.clear
        @msgLine.append( question )
        @lineEdit.text = ''
        exec
        @lineEdit.text
    end
end

class YesNoDlg < Qt::Dialog
    def initialize(parent)
        super(parent)
        self.windowTitle = 'RubyGem Asking Y/N.'

        @msgLine = Qt::TextEdit.new
        @msgLine.readOnly = true
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK') do |w|
            connect(w, SIGNAL(:clicked), self, SLOT(:accept))
        end
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), 'Cancel') do |w|
            connect(w, SIGNAL(:clicked), self, SLOT(:reject))
        end

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLine)
            l.addWidgetAtRight(@okBtn, @cancelBtn)
        end
        setLayout(lo)
    end

    def ask(question)
        @msgLine.clear
        @msgLine.append(question)
        exec == Qt::Dialog::Accepted ? true : false
    end
end

#--------------------------------------------------------------------------
#
#
class MainWindow < KDE::MainWindow
    slots   :startCmd
    
    def initialize(args)
        super(nil)
#         args.unshift('--backtrace')
        @args = args
        
        # read config
        @config = KDE::Config.new(APP_NAME+'rc')

        self.windowTitle = 'Ruby Gem'
        createWidget

        # config
        applyMainWindowSettings(KDE::Global.config.group("MainWindow"))
        setAutoSaveSettings()
        
        Qt::Timer.singleShot(0, self, SLOT(:startCmd))
    end

    def createWidget
        @logWidget = Qt::TextBrowser.new
        @okButton = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')

        connect(@okButton, SIGNAL(:clicked), $app, SLOT(:quit))

        # layout
        lw = VBoxLayoutWidget.new do |w|
            w.addWidget(@logWidget)
            w.addWidgetAtRight(@okButton)
        end
        setCentralWidget( lw )
    end

    
    # slot
    def startCmd
        # initialize gem ui
        @winUi = Gem::DefaultUserInteraction.ui = WinUI.new(self, @logWidget)

#         testWinUi
        
        begin
            Gem::GemRunner.new.run @args
        rescue Gem::SystemExitException => e
            @winUi.write( e.message )
        end
    end

    def testWinUi
        @winUi.ask "test ask."
        @winUi.ask_yes_no "test ask Y/N."
        @winUi.choose_from_list "test choose.", %w{ zarusoba tensoba yamakakesoba nishinsoba }
        @winUi.alert "test alert."
        @winUi.alert_error "test alert_error."
        @winUi.alert_warning "test alert_warning."
        progress = @winUi.progress_reporter 10, "test progress."
        10.times do |i|
            sleep(0.2)
            progress.updated "testing count : #{i}"
        end
    end
    
    #---------------------------
    #
    class WinUI
        attr_reader :outs, :errs
        def initialize(parent, outW)
            @outs = @errs = OutStream.new(outW)
            
            # dialogs
            @askDlg = AskDlg.new(parent)
            @yesnoDlg = YesNoDlg.new(parent)
            @chooseListDlg = ChooseListDlg.new(parent)
        end

        def write(msg)
            @outs.write(msg)
        end

        #
        class OutStream
            def initialize(outW)
                @outWidget = outW
            end
            
            def write(msg)
                STDOUT.puts msg
                @outWidget.append(msg.to_s)
            end
            
            alias   :puts :write
            alias   :print :write

            def tty?
                true
            end
        end
        
        # ui methods
        def choose_from_list(question, list)
            @chooseListDlg.ask(question, list)
        end
    
        def ask_yes_no(question, default=nil)
            @yesnoDlg.ask(question)
        end

        def ask(question)
            @askDlg.ask(question)
        end

        def say(statement="")
            write(statement)
        end

        def alert(statement, question=nil)
            write("INFO: #{statement}")
            ask(question) if question
        end

        def alert_warning(statement, question=nil)
            write("WARNING: #{statement}")
            ask(question) if question
        end

        def alert_error(statement, question=nil)
            write("ERROR: #{statement}")
            ask(question) if question
        end

        def debug(statement)
            write(statement)
        end


        def terminate_interaction(status = 0)
            raise Gem::SystemExitException, status
        end

        def progress_reporter(*args)
            ProgressReporter.new(*args)
        end

        class ProgressReporter
            def initialize(size, initial_message,
                        terminal_message = 'complete')
                @progressDlg = Qt::ProgressDialog.new
                @progressDlg.labelText = initial_message
                @progressDlg.setRange(0, size)
                @progressDlg.forceShow
                @progressDlg.setWindowModality(Qt::WindowModal)
                @count = 0
                @terminal_message = terminal_message
            end

            def updated(message)
                @progressDlg.labelText = message
                @count += 1
                @progressDlg.setValue(@count)
            end

            def done
                @progressDlg.hide
            end
        end
    end
end


#--------------------------------------------------------------------------
#
#
about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION)
KDE::CmdLineArgs.init([], about)

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
win = MainWindow.new(ARGV)
$app.setTopWidget(win)

win.show
$app.exec
