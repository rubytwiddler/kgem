require 'cgi'
require 'benchmark'

#--------------------------------------------------------------------------------
#
#
module InstallOption
    def makeArgs
        args = []
        options = Settings.instance
        if options.installRdocFlag then
            args.push( '--rdoc' )
        else
            args.push( '--no-rdoc' )
        end
        if options.installRiFlag then
            args.push( '--ri' )
        else
            args.push( '--no-ri' )
        end
        if options.installSheBangFlag then
            args.push( '--env-shebang' )
        else
            args.push( '--no-env-shebang' )
        end
        if options.installUnitTestFlag then
            args.push( '--test' )
        else
            args.push( '--no-test' )
        end
        if options.installBinWrapFlag then
            args.push( '--wrappers' )
        else
            args.push( '--no-wrappers' )
        end
        if options.installIgnoreDepsFlag then
            args.push( '--ignore-dependencies' )
        end
        if options.installIncludeDepsFlag then
            args.push( '--include-dependencies' )
        end
        if options.installDevelopmentDepsFlag then
            args.push( '--development' )
        end
        if options.installformatExecutableFlag then
            args.push( '--format-executable' )
        end
        args.push( '-P' )
        args.push( options.installTrustPolicyStr )

        args
    end
end


#--------------------------------------------------------------------------------
#
#
class UpdateDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        self.windowTitle = i18n('Update Gem')

        @msgLabel = Qt::Label.new(i18n('Update Gem'))
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), 'Cancel')
        connect(@okBtn, SIGNAL(:clicked), self, SLOT(:accept))
        connect(@cancelBtn, SIGNAL(:clicked), self, SLOT(:reject))
        @versionComboBox = Qt::ComboBox.new
        @allCheckBox = Qt::CheckBox.new(i18n('Update all'))
        @forceCheckBox = Qt::CheckBox.new(i18n('Force gem to install, bypassing dependency checks'))

        @optionsPage = InstallOptionsPage.new
        @settingsManager = KDE::ConfigDialogManager.new(@optionsPage, Settings.instance)

        # layout
        @versionWidget = HBoxLayoutWidget.new do |l|
            l.addWidgets('Version :', @versionComboBox, nil)
        end
        @versionEnabled = true
        @mainLayout = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLabel)
            l.addWidget(@versionWidget)
            l.addWidget(@allCheckBox)
            l.addWidget(@forceCheckBox)
            l.addWidget(@optionsPage)
            l.addWidgets(nil, @okBtn, @cancelBtn)
        end
        setLayout(@mainLayout)
    end


    def selectOption(gem)
        @allCheckBox.checked = false
        @allCheckBox.enabled = true
        @versionWidget.visible = true
        @gem = gem
        @versionComboBox.clear
        self.windowTitle = @msgLabel.text = i18n('Update Gem %s') % gem.name
        vers = gem.versions
        return unless vers
        @versionComboBox.addItems(vers)
        @versionComboBox.currentIndex = 0
        @settingsManager.updateWidgets
        exec == Qt::Dialog::Accepted
    end

    def confirmUpdateAll
        @allCheckBox.checked = true
        @allCheckBox.enabled = false
        @versionWidget.visible = false
        self.windowTitle = @msgLabel.text = i18n('Update All Gems')

        @settingsManager.updateWidgets
        exec == Qt::Dialog::Accepted
    end


    include InstallOption

    def makeUpdateArgs
        @settingsManager.updateSettings

        args = [ 'update' ]
        unless @allCheckBox.checked then
            args.push( @gem.package )
            args.push( '-r' )
            if @versionComboBox.currentIndex != @gem.nowVersion then
                args.shift
                args.unshift( 'install' )
                args.push( '-v' )
                args.push( @versionComboBox.currentText )
            end
        end
        if @forceCheckBox.checked then
            args.push( '--force' )
        else
            args.push( '--no-force' )
        end
        args += makeArgs
    end
end

#--------------------------------------------------------------------------------
#
#
class GenerateRdocDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        self.windowTitle = i18n('Generate RDoc/ri')

        @msgLabel = Qt::Label.new(i18n('Generate RDoc/ri'))
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), 'Cancel')
        connect(@okBtn, SIGNAL(:clicked), self, SLOT(:accept))
        connect(@cancelBtn, SIGNAL(:clicked), self, SLOT(:reject))
        @allCheckBox = Qt::CheckBox.new(i18n('Generate RDoc/RI documentation for all'))
        @rdocCheckBox = Qt::CheckBox.new(i18n('Generate RDoc Documentation'))
        @rdocCheckBox.checked = true
        @riCheckBox = Qt::CheckBox.new(i18n('Generate RI Documentation'))
        @riCheckBox.checked = true
        @overwriteCheckBox = Qt::CheckBox.new(i18n('Overwrite installed documents'))

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@allCheckBox)
            l.addWidget(@rdocCheckBox)
            l.addWidget(@riCheckBox)
            l.addWidget(@overwriteCheckBox)
            l.addWidgets(nil, @okBtn, @cancelBtn)
        end
        setLayout(lo)
    end

    def all?
        @allCheckBox.checked
    end

    def makeRdocArgs(gem)
        args = ['rdoc']
        return nil unless @rdocCheckBox.checked or @riCheckBox.checked

        args.push(gem.package)
        if @allCheckBox.checked
            args.push('--all')
        end
        if @rdocCheckBox.checked
            args.push('--rdoc')
        else
            args.push('--no-rdoc')
        end
        if @riCheckBox.checked
            args.push('--ri')
        else
            args.push('--no-ri')
        end
        if @overwriteCheckBox.checked
            args.push('--overwrite')
        else
            args.push('--no-overwrite')
        end
        args
    end
end

#--------------------------------------------------------------------------------
#
#
class SelectInstallVerDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        self.windowTitle = i18n('Install Ruby Gem')

        @msgLabel = Qt::Label.new
        @msgLabel.wordWrap = true
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), 'Cancel')
        connect(@okBtn, SIGNAL(:clicked), self, SLOT(:accept))
        connect(@cancelBtn, SIGNAL(:clicked), self, SLOT(:reject))
        @checkOtherVersion = KDE::PushButton.new(i18n("Check Other Version's Availability"))
        connect(@checkOtherVersion , SIGNAL(:clicked), self, SLOT(:checkOtherVersion))
        @versionComboBox = Qt::ComboBox.new
        @skipVersionCheck = Qt::CheckBox.new(i18n('Always Accept Latest Version to Skip This Dialog'))
        @forceCheckBox = Qt::CheckBox.new(i18n('Force gem to install, bypassing dependency checks'))

        @optionsPage = InstallOptionsPage.new
        @settingsManager = KDE::ConfigDialogManager.new(@optionsPage, Settings.instance)

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLabel)
            l.addWidgets('Version :', @versionComboBox, @checkOtherVersion, nil)
            l.addWidget(@forceCheckBox)
            l.addWidget(@optionsPage)
            l.addWidgets(nil, @okBtn, @cancelBtn)
        end
        setLayout(lo)
    end

    slots :checkOtherVersion
    def checkOtherVersion
        @versionComboBox.clear
        vers = @gem.versions
        return unless vers
        @versionComboBox.addItems(vers)
        @versionComboBox.currentIndex = 0
    end

    def selectVersion(gem)
        @gem = gem
        @versionComboBox.clear
        @versionComboBox.addItem(gem.version)
        @msgLabel.text = 'Install gem ' + gem.name + ' (' + gem.version.strip + ')'
        @settingsManager.updateWidgets
        exec == Qt::Dialog::Accepted
    end

    include InstallOption
    def makeInstallArgs(localFlag)
        @settingsManager.updateSettings

        args = [ 'install' ]
        if @versionComboBox.currentIndex != 0 then
            args.push( @gem.package )
            args.push( '-r' )
            args.push( '-v' )
            args.push( @versionComboBox.currentText )
        elsif localFlag then
            args.push( @gem.filePath )
        else
            args.push( @gem.package )
            args.push( '-r' )
        end
        if @forceCheckBox.checked then
            args.push( '--force' )
        else
            args.push( '--no-force' )
        end
        args += makeArgs
    end

end


#--------------------------------------------------------------------------------
#
#
class SelectDownloadVerDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        self.windowTitle = i18n('Download Ruby Gem')

        @msgLabel = Qt::Label.new
        @msgLabel.wordWrap = true
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), 'OK')
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), 'Cancel')
        connect(@okBtn, SIGNAL(:clicked), self, SLOT(:accept))
        connect(@cancelBtn, SIGNAL(:clicked), self, SLOT(:reject))
        @checkOtherVersion = KDE::PushButton.new(i18n("Check Other Version's Availability"))
        connect(@checkOtherVersion , SIGNAL(:clicked), self, SLOT(:checkOtherVersion))
        @versionComboBox = Qt::ComboBox.new
        @skipVersionCheck = Qt::CheckBox.new(i18n('Always Accept Latest Version to Skip This Dialog'))

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLabel)
            l.addWidgets('Version :', @versionComboBox, @checkOtherVersion, nil)
            l.addWidget(@skipVersionCheck)
            l.addWidgets(nil, @okBtn, @cancelBtn)
        end
        setLayout(lo)
    end

    slots :checkOtherVersion
    def checkOtherVersion
        @versionComboBox.clear
        vers = @gem.versions
        return unless vers
        @versionComboBox.addItems(vers)
        @versionComboBox.currentIndex = 0
    end

    def selectVersion(gem)
        @gem = gem
        @versionComboBox.clear
        @versionComboBox.addItem(gem.version)
        @msgLabel.text = 'Download gem ' + gem.name + ' (' + gem.version.strip + ')'
        exec == Qt::Dialog::Accepted
    end

    def makeDownloadArgs
        args = [ 'fetch' ]
        args.push( @gem.package )
        args.push( '-r' )
        if @versionComboBox.currentIndex != 0 then
            args.push( '-v' )
            args.push( @versionComboBox.currentText )
        end
        args
    end
end


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
                passiveMessage("Cleaned Up old versions of gems.")
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
        @terminalWin.processStart(cmd, args) do |ret|
            if ret == 0 then
                passiveMessage("Pristined All.")
            end
        end
    end

    slots :checkAlian
    def checkAlian
    end

    slots :checkStale
    def checkStale
    end

    slots :updateSystem
    def updateSystem
        args = %w{ update --system }
        cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        @terminalWin.processStart(cmd, args) do |ret|
            if ret == 0 then
                passiveMessage("Updated All Gems.")
            end
        end
    end

    def upgradable(gem)
        time =  Benchmark.realtime { gem.versions }
        puts "Time : " + time.to_s
        gem.versions.first != gem.nowVersion
    end

    slots :updateAll
    def updateAll
        @updateDlg ||= UpdateDlg.new
        return unless @updateDlg.confirmUpdateAll

        args = @updateDlg.makeUpdateArgs
        cmd = "#{APP_DIR}/bin/gemcmdwin-super.rb"
        @terminalWin.processStart(cmd, args) do |ret|
            if ret == 0 then
                passiveMessage("Updated All Gems (in system).")
                args << '--user-install'
                cmd = "#{APP_DIR}/bin/gemcmdwin.rb"
                @terminalWin.processStart(cmd, args) do |ret|
                    if ret == 0 then
                        passiveMessage("Updated All Gems (in user).")
                    end
                end
            end
            notifyInstall
            notifyDownload
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
        @terminalWin.processStart(cmd, args) do |ret|
            notifyInstall
            notifyDownload
            if ret == 0 then
                passiveMessage("Installed #{gem.package}")
            end
        end
    end

    def install(gem, localFlag)
        @selectInstallVerDlg ||= SelectInstallVerDlg.new
        return unless @selectInstallVerDlg.selectVersion(gem)

        args = @selectInstallVerDlg.makeInstallArgs(localFlag)
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
        @selectDownloadVerDlg ||= SelectDownloadVerDlg.new
        return unless @selectDownloadVerDlg.selectVersion(gem)

        args = @selectDownloadVerDlg.makeInstallArgs
        if Settings.autoFetchFlag then
            dir = Settings.autoFetchDir.pathOrUrl
        else
            dir = KDE::FileDialog::getExistingDirectory(Settings.autoFetchDir)
            return unless dir
            Settings.autoFetchDir.setUrl(dir)
        end
        Dir.chdir(dir)
        cmd = 'gem'
        args = @selectDownloadVerDlg.makeDownloadArgs
        @terminalWin.processStart(cmd, args) do |ret|
            notifyDownload
            if ret == 0 then
                passiveMessage("Downloaded #{gem.package}")
            else
                passiveMessage("Download #{gem.package} failed.")
            end
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
        @terminalWin.processStart(cmd, args) do |ret|
            if ret == 0 then
                passiveMessage("Generated rdoc/ri for #{gem.package}")
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
        @error = 0
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
        @canceled = 1
        @process.start(cmd, args)
        @finishProc = block
    end

    def processfinished(exitCode, exitStatus)
        write( @process.readAll.data )
        if @finishProc
            @finishProc.call(exitCode | @error | @canceled )
        end
    end

    def checkErrorInMsg(msg)
        @canceled = 0
        if msg =~ /Exiting [\w\s]+ exit_code \d/i
            @error = 1
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
