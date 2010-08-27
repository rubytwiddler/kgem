#
#
#
class PreviewWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        createWidget
        readSettings
    end

    def createWidget
        @titleLabel = Qt::Label.new('')
        @textEditor = KTextEditor::EditorChooser::editor
        @closeBtn = KDE::PushButton.new(KDE::Icon.new('dialog-close'), \
                                        i18n('Close')) do |w|
            connect(w, SIGNAL(:clicked), self, SLOT(:hide))
        end

        @document = @textEditor.createDocument(nil)
        @textView = @document.createView(self)

        # layout
        lo = Qt::VBoxLayout.new
        lo.addWidgets('File Name:', @titleLabel, nil)
        lo.addWidget(@textView)
        lo.addWidgets(nil, @closeBtn)
        setLayout(lo)
    end

    ModeTbl = { /\.rb$/ => 'Ruby',
                /Rakefile$/ => 'Ruby',
                /\.(h|c|cpp)$/ => 'C++',
                /\.json$/ => 'JSON',
                /\.html?$/ => 'HTML',
                /\.xml$/ => 'XML',
                /\.(yml|yaml)$/ => 'YAML',
                /\.java$/ => 'Java',
                /\.js$/ => 'JavaScript',
                /\.css$/ => 'CSS',
                /\.py$/ => 'Python',
                /\.txt$/ => 'Normal',
                /^(\w+)$/i => 'Normal',
                }
    def findMode(text)
        file = File.basename(text)
        m = ModeTbl.find do |k,v|
            k =~ file
        end
        m ? m[1] : 'Ruby'
    end
    def setText(title, text)
        @titleLabel.text = title
        @document.setReadWrite(true)
        @document.setText(text)
        puts " Text mode = " + findMode(title)
        @document.setMode(findMode(title))
        @document.setReadWrite(false)
        show
    end

    def setFile(file)
        @titleLabel.text = file
        @document.openUrl(KDE::Url.new(file))
        @document.setReadWrite(false)
        show
    end

    GroupName = 'PreviewWindow'
    def readSettings
        config = $config.group(GroupName)
        restoreGeometry(config.readEntry('windowState', saveGeometry))
    end

    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('windowState', saveGeometry)
    end
end
