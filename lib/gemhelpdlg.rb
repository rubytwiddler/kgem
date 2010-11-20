#
#
#
class GemHelpDlg < KDE::MainWindow
    slots    'listSelected(QListWidgetItem*)'
    GroupName = "GemHelpDlg"

    def initialize(parent=nil)
        super(parent)
        setCaption("gem (command line version) command help")
        createWidget
        iniHelpList
        setAutoSaveSettings(GroupName)
        readSettings
    end

    def createWidget
        closeBtn = KDE::PushButton.new(KDE::Icon.new('dialog-close'), i18n('Close'))
        @helpList = Qt::ListWidget.new
        @helpText = Qt::PlainTextEdit.new
        @helpText.readOnly = true

        connect(@helpList, SIGNAL('itemClicked(QListWidgetItem*)'),
                self, SLOT('listSelected(QListWidgetItem*)'))
        connect(closeBtn, SIGNAL(:clicked), self, SLOT(:hide))

        # layout
        @splitter = Qt::Splitter.new do |s|
            s.addWidget(@helpList)
            s.addWidget(@helpText)
        end
        @splitter.setStretchFactor(0,0)
        @splitter.setStretchFactor(1,1)
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@splitter)
            l.addWidgets(nil, closeBtn)
        end
        w = Qt::Widget.new
        w.setLayout(lo)
        setCentralWidget(w)
    end

    def iniHelpList
        list = GemCmd.exec("help command").split(/[\r\n]+/).inject([]) do |a, line|
                    line =~ /^\s{4}(\w+)/ ? a << $1 : a
        end
        list.unshift('examples')
        @helpList.clear
        @helpList.addItems(list)
    end


    def listSelected(item)
        text = GemCmd.exec("help #{item.text}")
        @helpText.clear
        @helpText.appendHtml("<pre>" + text + "</pre>")
    end

    # virtual function slot
    def closeEvent(event)
        writeSettings
        super(event)
    end

    def readSettings
        config = $config.group(GroupName)
        @splitter.restoreState(config.readEntry('SplitterState', @splitter.saveState))
    end

    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('SplitterState', @splitter.saveState)
    end
end
