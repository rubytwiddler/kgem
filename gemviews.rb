#
#
#
class DockGemViewer
    def initialize(detailView, filesView, previewWin)
        @detailView = detailView
        @filesView = filesView
        @downloadWatcher = []
        @previewWin = previewWin
        @getFileProc = nil

        @filesView.setPreviewCmd(
            lambda do |item|
                file = item.text
                @previewWin.setText( file, @getFileProc.call(file) ) if @previewWin && @getFileProc
            end
        )
    end

    def setDetail(gem)
        @detailView.setDetail(gem)
    end

    def setFiles(files)
        @filesView.setFiles(files)
    end

    # @param ex : Exception.
    def setError(gem, ex)
        @detailView.setError(gem, ex)
    end

    def setGetFileProc(proc)
        @getFileProc = proc
    end

    def addDownloadWatcher(watcher)
        @downloadWatcher << watcher
    end

    def notifyDownload
        @downloadWatcher.each do |w| w.notifyDownload end
    end
end

#--------------------------------------------------------------------
#
#
class DetailWin < Qt::DockWidget
    def initialize(parent)
        super('Detail', parent)
        self.objectName = 'Detail'
        createWidget
    end

    def createWidget
        @textPart = Qt::TextBrowser.new
        connect(@textPart, SIGNAL('anchorClicked(const QUrl&)')) do |url|
            cmd = Settings.browserCmdForOpenDoc(url.toString)
            fork do exec(cmd) end
        end
        @textPart.openLinks = false
        setWidget(@textPart)
    end

    class HtmlStr < String
        def insertHtml(str)
            self.concat(str)
        end
        def insertItem(name, value)
            if value && !value.empty?
                insertHtml("<tr><td>#{name}</td><td>: #{value}</td></tr>")
            end
        end

        def insertUrl(name, url)
            if url && !url.empty?
                insertItem(name, "<a href='#{url}'>#{url}</a>")
            end
        end
    end

    public
    def setDetail(gem)
        @textPart.clear
        return unless gem
        html = HtmlStr.new
        html.insertHtml("<font size='+1'>#{gem.package}</font><br>")
        html.insertHtml(gem.summary.gsub(/\n/,'<br>'))
        html.insertHtml("<table>")
        html.insertItem('Author', gem.author)
        html.insertUrl('Rubyforge', gem.rubyforge)
        html.insertUrl('homepage', gem.homepage)
        html.insertUrl('platform', gem.platform) if gem.platform !~ /ruby/i
        html.insertHtml("</table><p>")
        if gem.spec and gem.spec.description then
            html.insertHtml(gem.spec.description.gsub(/\n/,'<br>'))
        end

        @textPart.insertHtml(html)
    end

    # @param ex : Exception.
    def setError(gem, ex)
        @textPart.clear
        @textPart.append(<<-EOF
#{ex.to_s} : Can not get #{gem.package} gem specification data.
        EOF
        )
    end
end
#--------------------------------------------------------------------
#
#
class FileListWin < Qt::DockWidget
    def initialize(parent)
        super('Files', parent)
        self.objectName = 'Files'
        @previewCmd = nil
        createWidget
    end

    def createWidget
        @fileList = Qt::ListWidget.new
        connect(@fileList, SIGNAL('itemClicked(QListWidgetItem *)'), self,
                                  SLOT('itemClicked(QListWidgetItem *)'))
        setWidget(@fileList)
    end

    def setFiles(files)
        @fileList.clear
        @fileList.addItems(files) if files
    end

    def setPreviewCmd(proc)
        @previewCmd = proc
    end

    slots 'itemClicked(QListWidgetItem *)'
    def itemClicked(item)
        @previewCmd.call(item) if @previewCmd
    end
end

#--------------------------------------------------------------------
#
#
class TerminalWin < Qt::DockWidget
    slots   'processfinished(int,QProcess::ExitStatus)'
    slots   'cleanup(QObject*)'
    slots   :processReadyRead

    def initialize(parent)
        super('Output', parent)
        self.objectName = 'Terminal'
        createWidget
        processSetup

        connect(self, SIGNAL('destroyed(QObject*)'), self, SLOT('cleanup(QObject*)'))
    end

    def createWidget
        @textEdit = Qt::TextEdit.new
        @textEdit.readOnly = true
        setWidget(@textEdit)
    end

    def processSetup
        @process = Qt::Process.new(self)
        @process.setProcessChannelMode(Qt::Process::MergedChannels)
        connect(@process, SIGNAL('finished(int,QProcess::ExitStatus)'),
                self, SLOT('processfinished(int,QProcess::ExitStatus)'))
        connect(@process, SIGNAL(:readyReadStandardOutput),
                self, SLOT(:processReadyRead))
        connect(@process, SIGNAL(:readyReadStandardError),
                self, SLOT(:processReadyRead))
    end

    def write(text)
        @textEdit.append(text)
    end

    def processStart(cmd, args, &block)
        unless @process.state == Qt::Process::NotRunning
            msg = "process is already running."
            write(msg)
            KDE::MessageBox::information(self, msg)
            return
        end
        @process.start(cmd, args)
        @finishProc = block
    end

    def processfinished(exitCode, exitStatus)
        write( @process.readAll.data )
        if @finishProc
            @finishProc.call
        end
    end

    def processReadyRead
        lines = @process.readAll.data
        lines.gsub!(/^kdesu .*?\n/, '')
        lines.gsub!(/~?ScimInputContextPlugin.*?\n/, '')
        unless lines.empty?
            print lines
            write( lines )
        end
    end

    def cleanup(obj)
        puts "killing all process."
        @process.kill
    end
end
