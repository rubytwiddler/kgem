require 'cgi'


class SelectInstallVerDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        self.windowTitle = i18n('Installing Ruby Gem')

        @msgLine = Qt::Label.new
        @msgLine.wordWrap = true
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), 'Cancel')
        connect(@okBtn, SIGNAL(:clicked), self, SLOT(:accept))
        connect(@cancelBtn, SIGNAL(:clicked), self, SLOT(:reject))
        @checkOtherVersion = KDE::PushButton.new(i18n('Check Other Version Availability'))
        connect(@checkOtherVersion , SIGNAL(:clicked), self, SLOT(:checkOtherVersion))
        @versionComboBox = Qt::ComboBox.new
        @skipVersionCheck = Qt::CheckBox.new(i18n('Always Accept Latest Version to Skip This Dialog'))


        @rdocCheckBox = Qt::CheckBox.new(i18n('Generate RDoc Documentation'))
        @riCheckBox = Qt::CheckBox.new(i18n('Generate RI Documentation'))
        @sheBangCheckBox = Qt::CheckBox.new(i18n('Rewrite the shebang line on installed scripts to use /usr/bin/env'))
        @forceCheckBox = Qt::CheckBox.new(i18n('Force gem to install, bypassing dependency checks'))
        @utestCheckBox = Qt::CheckBox.new(i18n('Run unit tests prior to installation'))
        @binWrapCheckBox = Qt::CheckBox.new(i18n('Use bin wrappers for executables'))
#         @policyCheckBox = Qt::ComboBox.new
#             Qt::Label.new(i18n('Specify gem trust policy'))
        @ignoreDepsCheckBox = Qt::CheckBox.new(i18n('Do not install any required dependent gems'))
        @includeDepsCheckBox = Qt::CheckBox.new(i18n('Unconditionally install the required dependent gems'))
        @developmentDepsCheckBox = Qt::CheckBox.new(i18n('Install any additional development dependencies'))
#         optionsGroupBox = Qt::GroupBox.new(i18n('Show Options'))
#         optionsGroupBox.

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLine)
            l.addWidgets(@versionComboBox, @checkOtherVersion)
            l.addWidget(@skipVersionCheck)
            l.addWidget(@rdocCheckBox)
            l.addWidget(@riCheckBox)
            l.addWidget(@sheBangCheckBox)
            l.addWidget(@forceCheckBox)
            l.addWidget(@utestCheckBox)
            l.addWidget(@binWrapCheckBox)
            l.addWidget(@ignoreDepsCheckBox)
            l.addWidget(@includeDepsCheckBox)
            l.addWidget(@developmentDepsCheckBox)
            l.addWidgetAtRight(@okBtn, @cancelBtn)
        end
        setLayout(lo)
    end

    slots :checkOtherVersion
    def checkOtherVersion
        @versionComboBox.clear
        res = %x{ gem list #{@gem.name} -a -r }
        res = res[/#{Regexp.escape(@gem.name)}\s+\([\w\d.,\s]+\)/]
        return res unless res

        vers = res[/\(.*\)/][1..-2].split(/[\s,]+/)
        vers.each do |v|
            @versionComboBox.addItem(v.strip)
        end
        @versionComboBox.currentIndex = 0
    end

    def selectVersion(gem)
        @gem = gem
        @versionComboBox.clear
        @versionComboBox.addItem(gem.version)
        @msgLine.text = 'Install gem ' + gem.name + ' (' + gem.version.strip + ')'
        exec == Qt::Dialog::Accepted
    end

    def makeInstallArgs
        args = [ 'install' ]
        args.push( @gem.package )
        args.push( '-r' )
        if @versionComboBox.currentIndex != 0 then
            args.push( '-v' )
            args.push( @versionComboBox.currentText )
        end
        if @rdocCheckBox.checked then
            args.push( '--rdoc' )
        else
            args.push( '--no-rdoc' )
        end
        if @riCheckBox.checked then
            args.push( '--ri' )
        else
            args.push( '--no-ri' )
        end
        if @sheBangCheckBox.checked then
            args.push( '--env-shebang' )
        else
            args.push( '--no-env-shebang' )
        end
        if @forceCheckBox.checked then
            args.push( '--force' )
        else
            args.push( '--no-force' )
        end
        if @utestCheckBox.checked then
            args.push( '--test' )
        else
            args.push( '--no-test' )
        end
        if @binWrapCheckBox.checked then
            args.push( '--wrappers' )
        else
            args.push( '--no-wrappers' )
        end
        if @ignoreDepsCheckBox.checked then
            args.push( '--ignore-dependencies' )
        end
        if @includeDepsCheckBox.checked then
            args.push( '--include-dependencies' )
        end
        args
    end
end


#--------------------------------------------------------------------------------
#
#
class DockGemViewer
    attr_reader :previewWin
    def initialize(detailView, filesView, terminalWin, previewWin)
        @detailView = detailView
        @filesView = filesView
        @terminalWin = terminalWin
        @downloadWatcher = []
        @installWatcher  = []
        @previewWin = previewWin

        @selectInstallVerDlg = SelectInstallVerDlg.new
        @detailView.setGetSpecProc(
            Proc.new do |gem|
                res = %x{ gem specification #{gem.name} -b  --marshal }
                unless res.empty?
                    spec = Marshal.load(res)
                    gem = GemItem::parseGemSpec(spec)
                    setDetail(gem)
                end
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

    def setPreviewProc(proc)
        @filesView.setPreviewProc(proc)
    end

    def addDownloadWatcher(watcher)
        @downloadWatcher << watcher
    end

    def notifyDownload
        @downloadWatcher.each do |w| w.notifyDownload end
    end

    def addInstallWatcher(watcher)
        @installWatcher << watcher
    end

    def notifyInstall
        @installWatcher.each do |w| w.notifyInstall end
    end


    def install(gem)
        return unless @selectInstallVerDlg.selectVersion(gem)

        args = @selectInstallVerDlg.makeInstallArgs
        if Settings.installInSystemDirFlag then
            cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        else
            args.push( '--user-install' )
            cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        end
        @terminalWin.processStart(cmd, args) do |ret|
            notifyInstall
            notifyDownload
            if ret == 0 then
                passiveMessage("Installed #{gem.package}")
            end
        end
    end

    def uninstall(gem)
        args = [ 'uninstall' ]
        args.push( gem.package )
        puts "installedLocal? : " + gem.installedLocal?.inspect
        if gem.installedLocal? then
            args.push( '--user-install' )
            cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        else
            cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        end
        @terminalWin.processStart(cmd, args) do |ret|
            notifyInstall
            if ret == 0 then
                passiveMessage("Uninstalled #{gem.package}")
            end
        end
    end

    def download(gem)
        if Settings.autoFetchFlag then
            dir = Settings.autoFetchDir.pathOrUrl
        else
            dir = KDE::FileDialog::getExistingDirectory(Settings.autoFetchDir)
            return unless dir
            Settings.autoFetchDir.setUrl(dir)
        end
        Dir.chdir(dir)
        cmd = 'gem'
        args = [ 'fetch', gem.package ]
        @terminalWin.processStart(cmd, args) do |ret|
            notifyDownload
            if ret == 0 then
                passiveMessage("Downloaded #{gem.package}")
            else
                passiveMessage("Download #{gem.package} failed.")
            end
        end
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
            cmd= Mime::services('.html').first.exec
            cmd.gsub!(/%\w+/, url.toString.shellescape)
            fork do exec(cmd) end
        end
        @textPart.openLinks = false
        @moreInfoBtn = KDE::PushButton.new(i18n('More Information'))
        connect(@moreInfoBtn, SIGNAL(:clicked), self, SLOT(:moreInfo))
        @moreInfoBtn.hide

        lw = VBoxLayoutWidget.new do |l|
            l.addWidget(@textPart)
            l.addWidget(@moreInfoBtn)
        end
        setWidget(lw)
    end

    class HtmlStr < String
        def insertHtml(str)
            self.concat(str)
        end

        def insertItem(name, value)
            if value && !value.empty?
                insertHtml("<tr><td>#{name}</td><td>: #{CGI.escapeHTML(value)}</td></tr>")
            end
        end

        def insertDep(name, value, val2='')
            insertHtml("<tr><td>#{name}</td><td>&nbsp; #{CGI.escapeHTML(value)}</td><td> &nbsp;: #{CGI.escapeHTML(val2)}</td></tr>")
        end

        def insertUrl(name, url)
            if url && !url.empty?
                insertHtml("<tr><td>#{name}</td><td>:<a href='#{url}'>#{url}</a></td></tr>")
            end
        end
    end

    public
    def setDetail(gem)
        @currentGem = gem
        @textPart.clear
        @moreInfoBtn.hide
        return unless gem
        spec = gem.spec
        html = HtmlStr.new
        html.insertHtml("<font size='+1'>#{gem.package}</font><br>")
        html.insertHtml(gem.summary.gsub(/\n/,'<br>'))
        html.insertHtml("<table>")
        author = gem.author
        if author.kind_of? Array then
            author = author.join(', ')
        end
        html.insertItem('Author', author)
        html.insertItem('Version', gem.version)
        if spec then
            html.insertItem('Date', spec.date.strftime('%F'))
        end
        html.insertUrl('Rubyforge', gem.rubyforge)
        html.insertUrl('homepage', gem.homepage)
        html.insertUrl('platform', gem.platform) if gem.platform !~ /ruby/i
        html.insertHtml("</table>")
        if spec then
            deps = spec.dependencies
            if deps.size > 0 then
                html.insertHtml('Dependencies')
                html.insertHtml("<table>")
                deps.each do |dep|
                    html.insertDep('&nbsp;'*2 + dep.name, dep.requirement.to_s, dep.type.to_s)
                end
                html.insertHtml("</table>")
            end
        end
        if spec then
            if spec.description then
                html.insertHtml('<p>'+spec.description.gsub(/\n/,'<br>'))
            end
        else
            @moreInfoBtn.show
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

    def setGetSpecProc(proc)
        @getSpecProc = proc
    end

    slots  :moreInfo
    def moreInfo
        @getSpecProc.call(@currentGem) if @getSpecProc
    end
end

#--------------------------------------------------------------------
#
#
class FileListWin < Qt::DockWidget
    def initialize(parent)
        super('Files', parent)
        self.objectName = 'Files'
        @previewProc = nil
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

    def setPreviewProc(proc)
        @previewProc = proc
    end

    slots 'itemClicked(QListWidgetItem *)'
    def itemClicked(item)
        @previewProc.call(item) if @previewProc
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
        puts "execute : " + cmd.inspect + " " + args.join(' ').inspect
        @process.start(cmd, args)
        @finishProc = block
    end

    def processfinished(exitCode, exitStatus)
        write( @process.readAll.data )
        if @finishProc
            @finishProc.call(exitCode)
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
