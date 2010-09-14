require 'cgi'
require 'benchmark'
require 'date'




#--------------------------------------------------------------------------------
#--------------------------------------------------------------------------------
#
#
class DockGemViewer < Qt::Object
    attr_reader :previewWin
    def initialize(parent, detailView, filesView, terminalWin, previewWin)
        super(nil)
        @parent = parent
        @detailView = detailView
        @filesView = filesView
        @terminalWin = terminalWin
        @downloadWatcher = []
        @installWatcher  = []
        @previewWin = previewWin

        @detailView.setGetSpecProc(
            Proc.new do |g|
                gem = GemItem::getGemfromPath(g.name)
                setDetail(gem)
            end
        )
    end


    def setDetail(gem)
        @detailView.setDetail(gem)
    end

    def setFiles(files)
        @filesView.setFiles(files)
    end

    def setInstallWin(win)
        @installWin = win
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

    #--------------------------------------------------------------
    #
    #
    slots :cleanUp
    def cleanUp
        res = KDE::MessageBox::questionYesNo(
            @parent, Qt::Object.i18n('Clean up old versions of installed gems in the local repository. Clean Up ?'), Qt::Object.i18n('Clean Up.'))
        return unless res == KDE::MessageBox::Yes

        args = %w{ cleanup }
        cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        @terminalWin.processStart(cmd, args) do |ret|
            if ret == 0 then
                passiveMessage("Cleaned Up old versions of gems (system).")
                cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
                @terminalWin.processStart(cmd, args, \
                    i18n("Cleaned Up old versions of gems (in user).")) do |ret|
                    notifyInstall
                end
            end
        end
    end


    slots :pristineAll
    def pristineAll
        res = KDE::MessageBox::questionYesNo(
            @parent, Qt::Object.i18n(<<-EOF
Restores installed gems to pristine condition from files located in the gem cache.

The pristine command compares the installed gems with the contents of the cached gem and restores any files that don't match the cached gem's copy. If you have made modifications to your installed gems, the pristine command will revert them. After all the gem's files have been checked all bin.

Pristine All ?
            EOF
            ), Qt::Object.i18n('Pristine All.'))
        return unless res == KDE::MessageBox::Yes

        args = %w{ pristine --all }
        cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        @terminalWin.processStart(cmd, args, i18n("Pristined All."))
    end

    slots :checkAlien
    def checkAlien
        cmd = "gem"
        args = %w{ check --alien }
        @terminalWin.visible = true
        @terminalWin.processStart(cmd, args, i18n("checked alien see Output Dock window for detail."))
    end


    slots :checkStale
    def checkStale
        lines = %x{ gem stale }.split(/\n/)
        stales = []
        lines.each do |l|
            gv, t = l.split(/ at /, 2)
            atime = Date.parse(t.strip)
            m = gv.match(/(.*)-([^\-]+)/)
            stales << StaleGemItem.new( m[1].strip, m[2].strip, atime )
        end
        @installWin.setStaleTime(stales)
    end

    slots :testGem
    def testGem(gem)
        spec = gem.spec
        return unless spec
        args = %w{ check --test }
        args += [ spec.name, '--version', spec.version.version ]
        cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        @terminalWin.processStart(cmd, args, i18n("Tested the gem. Please check output window"))
    end

    slots :updateSystem
    def updateSystem
        args = %w{ update --system }
        cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        @terminalWin.processStart(cmd, args, i18n("Updated All Gems."))
    end

    def upgradable(gem)
        time =  Benchmark.realtime { gem.availableVersions }
        puts "Time : " + time.to_s
        gem.availableVersions.first != gem.nowVersion
    end

    slots :updateAll
    def updateAll
        @updateDlg ||= UpdateDlg.new
        return unless @updateDlg.confirmUpdateAll

        args = @updateDlg.makeUpdateArgs
        cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        @terminalWin.processStart(cmd, args, i18n("Updated All Gems (in system).")) do |ret|
            if ret == 0 then
                args << '--user-install'
                cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
                @terminalWin.processStart(cmd, args, i18n("Updated All Gems (in user).")) do |ret|
                    notifyInstall
                    notifyDownload
                end
            end
        end

    end

    def updateGem(gem)
        unless upgradable(gem) then
            res = KDE::MessageBox::questionYesNo(@parent, Qt::Object.i18n('Already Installed Latest Gem. install older version ?'), Qt::Object.i18n('Already Installed latest Gem.'))
            return unless res == KDE::MessageBox::Yes
        end

        @updateDlg ||= UpdateDlg.new
        return unless @updateDlg.selectOption(gem)

        args = @updateDlg.makeUpdateArgs
        if gem.installedLocal? then
            args.push( '--user-install' )
            cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        else
            cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        end
        @terminalWin.processStart(cmd, args, "Installed #{gem.package}") do |ret|
            notifyInstall
            notifyDownload
        end
    end

    def install(gem, localFlag)
        return unless gem

        @selectInstallVerDlg ||= SelectInstallVerDlg.new
        return unless @selectInstallVerDlg.selectVersion(gem)

        args = @selectInstallVerDlg.makeInstallArgs(localFlag)
        if Settings.installInSystemDirFlag then
            cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        else
            args.push( '--user-install' )
            cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        end
        @terminalWin.processStart(cmd, args, "Installed #{gem.package}") do |ret|
            notifyInstall
            notifyDownload
        end
    end

    def uninstall(gem)
        return unless gem

        args = [ 'uninstall' ]
        args.push( gem.package )
        puts "installedLocal? : " + gem.installedLocal?.inspect
        if gem.installedLocal? then
            args.push( '--user-install' )
            cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        else
            cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        end
        @terminalWin.processStart(cmd, args, "Uninstalled #{gem.package}") do |ret|
            notifyInstall
        end
    end

    def download(gem)
        @selectDownloadVerDlg ||= SelectDownloadVerDlg.new
        return unless @selectDownloadVerDlg.selectVersion(gem)

        if Settings.autoFetchFlag then
            dir = Settings.autoFetchDir
        else
            dir = KDE::FileDialog::getExistingDirectory(Settings.autoFetchDir)
            return unless dir
            Settings.autoFetchDir.setUrl(dir)
        end
        Dir.chdir(dir)
        cmd = 'gem'
        args = @selectDownloadVerDlg.makeDownloadArgs
        @terminalWin.processStart(cmd, args, "Downloaded #{gem.package}" \
                                  "Download #{gem.package} failed.") do |ret|
            notifyDownload
        end
    end

    def generateRdoc(gem)
        @GenerateRdocDlg ||= GenerateRdocDlg.new
        return unless @GenerateRdocDlg.exec == Qt::Dialog::Accepted

        args = @GenerateRdocDlg.makeRdocArgs(gem)
        return unless args
        puts "installedLocal? : " + gem.installedLocal?.inspect
        if !@GenerateRdocDlg.all? and gem.installedLocal? then
            cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
        else
            cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        end
        @terminalWin.processStart(cmd, args, "Generated rdoc/ri for #{gem.package}")
    end

    def getGemPaths
        @gemPath ||= %x{gem environment gempath}.chomp.split(/:/)
    end

    def findGemPath(path)
        paths = getGemPaths
        file = nil
        paths.find do |p|
            file = p + path
            File.exist? file
        end
        file
    end

    def viewGemRdoc(gem)
        return unless gem

        # make rdoc path
        pkg = gem.package
        ver = gem.nowVersion
        url = findGemPath('/doc/' + pkg + '-' + ver + '/rdoc/index.html')
        cmd= Mime::services('.html').first.exec
        cmd.gsub!(/%\w+/, url)
        fork do exec(cmd) end
    end

    def viewGemDir(gem)
        return unless gem

        pkg = gem.package
        ver = gem.nowVersion
        url = findGemPath('/gems/' + pkg + '-' + ver)
        cmd = KDE::MimeTypeTrader.self.query('inode/directory').first.exec[/\w+/]
        cmd += " " + url
        fork do exec(cmd) end
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
        return unless gem

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
        @clearBtn = KDE::PushButton.new(KDE::Icon.new('edit-clear'), i18n('Clear'))
        connect(@clearBtn, SIGNAL(:clicked), @textEdit, SLOT(:clear))

        lw = VBoxLayoutWidget.new do |l|
            l.addWidget(@textEdit)
            l.addWidgets(nil, @clearBtn)
        end
        setWidget(lw)
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

    def processStart(cmd, args, successMsg='Successed', failMsg='Failed', &block)
        unless @process.state == Qt::Process::NotRunning
            msg = "process is already running."
            write(msg)
            KDE::MessageBox::information(self, msg)
            return
        end
        msg = "execute : " + cmd.inspect + " " + args.join(' ').inspect + "\n"
        print msg
        write(msg)
        @successMsg = successMsg
        @failMsg = failMsg
        @error = 0
        @canceled = 1
        @process.start(cmd, args)
        @finishProc = block
    end

    def processfinished(exitCode, exitStatus)
        write( @process.readAll.data )
#         puts "exitCode:#{exitCode}, @error:#{@error}, @canceled:#{@canceled}"
        ret = exitCode  | @error | @canceled
        msg = ret == 0 ? @successMsg : @failMsg
        passiveMessage(msg)
        if @finishProc
            @finishProc.call(ret)
        end
    end

    def checkErrorInMsg(msg)
        @canceled = 0
        if msg =~ /Exiting [\w\s]+ exit_code (\d)/i
            @error = $1.to_i
        end
    end

    def processReadyRead
        lines = @process.readAll.data
        lines.gsub!(/~?ScimInputContextPlugin.*?\n/, '')
        unless lines.empty?
            print lines
            write( lines )
            checkErrorInMsg(lines)
        end
    end

    def cleanup(obj)
        puts "killing all process."
        @process.kill
    end
end
