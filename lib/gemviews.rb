require 'cgi'
require 'date'
require 'rbconfig'



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

        cmdargs = %w{ cleanup }
        @terminalWin.processLocSysGem(cmdargs, i18n("cleaned up old versions of gems.")) do |ret|
            notifyInstall
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

        cmdargs = %w{ pristine --all }
        @terminalWin.processSysGem(cmdargs, i18n("Pristined all."))
    end

    slots :checkAlien
    def checkAlien
        cmdargs = %w{ check --alien }
        @terminalWin.visible = true
        @terminalWin.processSysGem(cmdargs, i18n("checked alien see Output Dock window for detail."))
    end


    slots :checkStale
    def checkStale
        lines = GemCmd.exec("stale").split(/\n/)
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
        cmdargs = %w{ check --test }
        cmdargs += [ spec.name, '--version', spec.version.version ]
        @terminalWin.processLocGem(cmdargs, i18n("Tested the gem. Please check output window"))
    end

    slots :updateSystem
    def updateSystem
        cmdargs = %w{ update --system }
        @terminalWin.processSysGem(cmd, args, i18n("Updated All Gems."))
    end

    def upgradable(gem)
        stime = Time.now
        gem.availableVersions
        puts "Time : " + (Time.now - stime).to_s
        gem.availableVersions.first != gem.nowVersion
    end

    slots :updateAll
    def updateAll
        @updateDlg ||= UpdateDlg.new
        return unless @updateDlg.confirmUpdateAll

        cmdargs = @updateDlg.makeUpdateArgs
        @terminalWin.processUserSysGem(cmdargs, i18n("Update All Gems")) do |ret|
            notifyInstall
            notifyDownload
        end

#         cmd = getSuGemCmd
#         return unless cmd
#         args = cmdargs + args
#         @terminalWin.processStart(cmd, args, i18n("Updated All Gems (in system).")) do |ret|
#             if ret == 0 then
#                 args << '--user-install'
#                 cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
#                 @terminalWin.processStart(cmd, args, i18n("Updated All Gems (in user).")) do |ret|
#                     notifyInstall
#                     notifyDownload
#                 end
#             end
#         end

    end

    def updateGem(gem)
        unless upgradable(gem) then
            res = KDE::MessageBox::questionYesNo(@parent, Qt::Object.i18n('Already Installed Latest Gem. install older version ?'), Qt::Object.i18n('Already Installed latest Gem.'))
            return unless res == KDE::MessageBox::Yes
        end

        @updateDlg ||= UpdateDlg.new
        return unless @updateDlg.selectOption(gem)

        cmdargs = @updateDlg.makeUpdateArgs
        @terminalWin.processSelectGem(cmdargs, gem.installedLocal?, \
                                i18n("Updated #{gem.package}")) do |ret|
            notifyInstall
            notifyDownload
        end
    end

    def install(gem, localFlag)
        return unless gem

        @selectInstallVerDlg ||= SelectInstallVerDlg.new
        return unless @selectInstallVerDlg.selectVersion(gem)

        cmdargs = @selectInstallVerDlg.makeInstallArgs(localFlag)
        @terminalWin.processSelectGem(cmdargs, !Settings.installInSystemDirFlag, \
                                i18n("Installed #{gem.package}")) do |ret|
            notifyInstall
            notifyDownload
        end
    end

    def uninstall(gem)
        return unless gem

        cmdargs = [ 'uninstall' ]
        cmdargs.push( gem.package )
        @terminalWin.processSelectGem(cmdargs, gem.installedLocal?, \
                                      "Uninstalled #{gem.package}") do |ret|
            notifyInstall
            notifyDownload
        end
    end

    def download(gem)
        @selectDownloadVerDlg ||= SelectDownloadVerDlg.new
        return unless @selectDownloadVerDlg.selectVersion(gem)

        if Settings.autoFetchFlag then
            dir = Settings.autoFetchDir
        else
            puts Settings.autoFetchDir.inspect
            dir = Qt::FileDialog::getExistingDirectory(nil, 'select folder', Settings.autoFetchDir)
            return unless dir
            Settings.autoFetchDir = dir
        end
        FileUtils.mkdir_p(dir)
        Dir.chdir(dir)
        cmdargs = @selectDownloadVerDlg.makeDownloadArgs
        @terminalWin.processLocGem(cmdargs, "Downloaded #{gem.package}" \
                                  "Download #{gem.package} failed.") do |ret|
            notifyDownload
        end
    end

    def generateRdoc(gem)
        @GenerateRdocDlg ||= GenerateRdocDlg.new
        return unless @GenerateRdocDlg.exec == Qt::Dialog::Accepted

        cmdargs = @GenerateRdocDlg.makeRdocArgs(gem)
        return unless cmdargs
        @terminalWin.processSelectGem(cmdargs, \
                !@GenerateRdocDlg.all? && gem.installedLocal?, \
                "Generated rdoc/ri for #{gem.package}")
    end

    def getGemPaths
        @gemPath ||= GemCmd.exec("environment gempath").chomp.split(/:/)
    end

    def findGemPath(relPath)
        paths = getGemPaths
        path = paths.find do |pa|
            File.exist? pa + relPath
        end
        return nil unless path
        path + relPath
    end

    def viewGemRdoc(gem)
        return unless gem

        # make rdoc path
        pkg = gem.package
        ver = gem.nowVersion
        url = findGemPath('/doc/' + pkg + '-' + ver + '/rdoc/index.html')
        openUrlDocument(url)
    end

    def viewGemDir(gem)
        return unless gem

        pkg = gem.package
        ver = gem.nowVersion
        url = findGemPath('/gems/' + pkg + '-' + ver)
        openDirectory(url)
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
#         processSetup

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


    # call gem user mode or system
    def processSelectGem(args, locFlag, successMsg='Successed', failMsg='Failed', &block)
        if locFlag then
            processUserGem(args, successMsg, failMsg, &block)
        else
            processSysGem(args, successMsg, failMsg, &block)
        end
    end

    # call gem locally
    # no appendage
    def processLocGem(args, successMsg='Successed', failMsg='Failed', &block)
        processStartCmds(GemCmd.locCmds + args, successMsg, failMsg, &block)
    end

    # call gem as user mode
    # append '--user-install'
    def processUserGem(args, successMsg='Successed', failMsg='Failed', &block)
        args.push('--user-install')
        processStartCmds(GemCmd.locCmds + args, successMsg, failMsg, &block)
    end

    # call gem as system
    def processSysGem(args, successMsg='Successed', failMsg='Failed', &block)
        processStartCmds(GemCmd.suCmds + args, successMsg, failMsg, &block)
    end

    # local & system
    def processLocSysGem(args, successMsg='Successed', failMsg='Failed', &block)
        processStartCmds(GemCmd.suCmds + args, '(system) '+successMsg, failMsg) do |ret|
            processStartCmds(GemCmd.locCmds + args, '(user) '+successMsg, failMsg, &block)
        end
    end

    # user & system
    # user command appended '--user-install' parameter.
    def processUserSysGem(args, successMsg='Successed', failMsg='Failed', &block)
        processStartCmds(GemCmd.suCmds + args, '(system) '+successMsg, failMsg) do |ret|
            args.push('--user-install')
            processStartCmds(GemCmd.locCmds + args, '(user) '+successMsg, failMsg, &block)
        end
    end

#     def processStart(cmd, args, successMsg='Successed', failMsg='Failed', &block)
#         processStartCmds(args.unshift(cmd), successMsg, failMsg, &block)
#     end

    def processStartCmds(cmdargs, successMsg='Successed', failMsg='Failed', &block)
        processSetup unless @process
        unless @process.state == Qt::Process::NotRunning
            msg = "process is already running. please close (install,uninstall..etc) process window."
            write(msg)
            KDE::MessageBox::information(self, msg)
            return
        end
        msg = "execute : #{cmdargs[0].inspect} #{cmdargs[1..-1].join(' ').inspect}\n"
        print msg
        write(msg)
        @successMsg = successMsg
        @failMsg = failMsg
        @error = 0
        @canceled = 1
        @process.start(cmdargs.shift, cmdargs)
        @finishProc = block
    end

    def processfinished(exitCode, exitStatus)
        write( @process.readAll.data )
#         puts "exitCode:#{exitCode}, @error:#{@error}, @canceled:#{@canceled}"
        ret = exitCode  | @error | @canceled
        msg = ret == 0 ? @successMsg : @failMsg

        # clear process
        @process.kill
        @process.dispose
        @process = nil

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
