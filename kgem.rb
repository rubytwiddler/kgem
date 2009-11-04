#!/usr/bin/ruby
#
#    2009 by ruby.twiddler@gmail.com
#
#      Ruby Gem with KDE GUI
#

$KCODE = 'Ku'
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_DIR = File.expand_path(File.dirname(__FILE__))
APP_VERSION = "0.1"

# standard libs
require 'fileutils'
require 'rubygems'
require 'rubygems/specification'
require 'sqlite3'

# additional libs
require 'korundum4'

#
# my libraries and programs
#
require "#{APP_DIR}/mylibs"
require "#{APP_DIR}/settings"
require "#{APP_DIR}/gemsdb"


#--------------------------------------------------------------------
#
#
#
class GemListTable < Qt::TableWidget
    slots   'filterChanged(const QString &)'
    #
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = 1 | 32    # Qt::ItemIsSelectable | Qt::ItemIsEnabled
        end

        def gem
            tableWidget.gem(self)
        end
    end

    # column no
    PACKAGE_NAME = 0
    PACKAGE_VERSION = 1
    PACKAGE_SUMMARY = 2
    PACKAGE_STATUS = 3
    
    def initialize(title)
        super(0,4)

        self.windowTitle = title
        setHorizontalHeaderLabels(['package', 'version', 'summary', 'status'])
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(PACKAGE_NAME, Qt::AscendingOrder )
        @gems = {}
        restoreColumnWidths
    end

    def restoreColumnWidths
        config = $config.group("tbl-#{windowTitle}")
        str = config.readEntry('columnWidths', "[]")
        if str =~ /^\[[0-9\,\s]*\]$/ then
            cols = str[1..-2].split(/,/).map(&:to_i)
            if cols.length == columnCount then
                columnCount.times do |i| setColumnWidth(i, cols[i]) end
            end
        end
    end
    
    def saveColumnWidths
        config = $config.group("tbl-#{windowTitle}")
        cols = []
        columnCount.times do |i| cols << columnWidth(i) end
        config.writeEntry('columnWidths', cols.inspect)
    end
    
    # caution ! : befor call, sortingEnabled must be set false.
    #   speed performance problem elude changing sortingEnabled each time.
    def addPackage(row, gem)
#         self.sortingEnabled = false
        nameItem = Item.new(gem.package)
        @gems[nameItem] = gem           # 0 column item is hash key.
        setItem( row, PACKAGE_NAME, nameItem  )
        setItem( row, PACKAGE_VERSION, Item.new(gem.version) )
        setItem( row, PACKAGE_SUMMARY, Item.new(gem.summary) )
        setItem( row, PACKAGE_STATUS, Item.new(gem.status) )
    end

    
    def gem(item)
        gemAtRow(item.row)
    end

    def gemAtRow(row)
        @gems[item(row,0)]       # use 0 column item as hash key.
    end

    def currentGem
        gemAtRow(currentRow)
    end
    
    def showall
        rowCount.times do |r|
            showRow(r)
        end
    end

    def closeEvent(ev)
        saveColumnWidths
        super(ev)
    end
    
    # slot
    public
    def filterChanged(text)
        unless text && !text.empty?
            showall
            return
        end
        
        regxs = /#{text.strip}/i
        rowCount.times do |r|
            gem = gemAtRow(r)
            txt = [ gem.package, gem.summary, gem.author, gem.platform ].inject("") do |s, t|
                        t.nil? ? s : s + t.to_s
            end
            if regxs =~ txt then
                showRow(r)
            else
                hideRow(r)
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
        html = HtmlStr.new
        html.insertHtml("<font size='+1'>#{gem.package}</font><br>")
        html.insertHtml(gem.summary.gsub(/\n/,'<br>'))
        html.insertHtml("<table>")
        html.insertItem('Author', gem.author)
        html.insertUrl('Rubyforge', gem.rubyforge)
        html.insertUrl('homepage', gem.homepage)
        html.insertUrl('platform', gem.platform) if gem.platform !~ /ruby/i
        html.insertHtml("</table><p>")
        html.insertHtml(gem.spec.description.gsub(/\n/,'<br>'))
        
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

#--------------------------------------------------------------------
#
#
class FileListWin < Qt::DockWidget
    def initialize(parent)
        super('Files', parent)
        self.objectName = 'Files'
        createWidget
    end

    def createWidget
        @fileList = Qt::ListWidget.new
        setWidget(@fileList)
    end
    
    def setFiles(files)
        @fileList.clear
        @fileList.addItems(files)
    end
end

#--------------------------------------------------------------------
#
#
class GemHelpDlg < KDE::MainWindow
    slots    'listSelected(QListWidgetItem*)'
    GroupName = "GemHelpDlg"
    
    def initialize(parent=nil)
        super(parent)
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
        list = %x{gem help command}.inject([]) do |a, line|
                    line =~ /^\s{4}(\w+)/ ? a << $1 : a
        end
        list.unshift('examples')
        @helpList.clear
        @helpList.addItems(list)
    end
    

    def listSelected(item)
        text = %x{gem help #{item.text}}
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


#--------------------------------------------------------------------
#--------------------------------------------------------------------
#
#
#
class MainWindow < KDE::MainWindow
    slots   :updateGemList, :updateAvailableGemList, :updateInstalledGemList
    slots   'itemClicked (QTableWidgetItem *)'
    slots   :viewRdoc, :viewDir, :installGem, :uninstallGem
    slots   :configureShortCut, :configureApp, :gemCommandHelp
    slots   :initializeAtStart

    def initialize
        super(nil)
        setCaption(APP_NAME)

        @actions = KDE::ActionCollection.new(self)
        createMenu
        createWidgets
        createDlg
        setupGems
        @actions.readSettings
        setAutoSaveSettings

        Qt::Timer.singleShot(0, self, SLOT(:initializeAtStart))
    end

    
    def createMenu
        updateListAction = KDE::Action.new(KDE::Icon.new('view-refresh'), 'Update List', self)
        updateListAction.setShortcut(KDE::Shortcut.new('Ctrl+R'))
        @actions.addAction(updateListAction.text, updateListAction)
        quitAction = KDE::Action.new(KDE::Icon.new('exit'), '&Quit', self)
        quitAction.setShortcut(KDE::Shortcut.new('Ctrl+Q'))
        @actions.addAction(quitAction.text, quitAction)
        fileMenu = KDE::Menu.new(i18n('&File'), self)
        fileMenu.addAction(updateListAction)
        fileMenu.addAction(quitAction)
        gemHelpAction = KDE::Action.new('Gem Command Line Help', self)
        @actions.addAction(gemHelpAction.text, gemHelpAction)
        installAction = KDE::Action.new('Install', self)
        @actions.addAction(installAction.text, installAction)
        
        # connect actions
        connect(updateListAction, SIGNAL(:triggered), self, SLOT(:updateGemList))
        connect(quitAction, SIGNAL(:triggered), self, SLOT(:close))
        connect(gemHelpAction, SIGNAL(:triggered), self, SLOT(:gemCommandHelp))
        connect(installAction, SIGNAL(:triggered), self, SLOT(:installGem))

        
        # settings menu
        configureShortCutAction = KDE::Action.new(KDE::Icon.new('configure-shortcuts'),
                                                  i18n('Configure Shortcuts'), self)
        configureAppAction = KDE::Action.new(KDE::Icon.new('configure'),
                                              i18n('Configure Kgem'), self)
        settingsMenu = KDE::Menu.new(i18n('&Settings'), self)
        settingsMenu.addAction(configureShortCutAction)
        settingsMenu.addAction(configureAppAction)
        # connect actions
        connect(configureShortCutAction, SIGNAL(:triggered), self, SLOT(:configureShortCut))
        connect(configureAppAction, SIGNAL(:triggered), self, SLOT(:configureApp))
        
            
        # Help menu
        about = i18n(<<-ABOUT
#{APP_NAME} #{APP_VERSION}
    Ruby Gem KDE GUI
        ABOUT
        )
        helpMenu = KDE::HelpMenu.new(self, about)
        helpMenu.menu.addAction(gemHelpAction)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( settingsMenu )
        menu.addSeparator
        menu.addMenu( helpMenu.menu )
        setMenuBar(menu)
    end



    def createWidgets
        # dockable window
        @detailWin = DetailWin.new(self)
        addDockWidget(Qt::BottomDockWidgetArea, @detailWin)
        @fileListWin = FileListWin.new(self)
        tabifyDockWidget(@detailWin, @fileListWin)
        @termilanWin = TerminalWin.new(self)
        tabifyDockWidget(@fileListWin, @termilanWin)

        
        # other
        @installedGemsTable = GemListTable.new('installed')
        @availableGemsTable = GemListTable.new('available')

        @installBtn = KDE::PushButton.new(KDE::Icon.new('list-add'), 'Install')
        @upgradeBtn = KDE::PushButton.new('Upgrade')
        @viewDirBtn = KDE::PushButton.new(KDE::Icon.new('folder'), 'View Directory')
        @viewRdocBtn = KDE::PushButton.new(KDE::Icon.new('help-contents'), 'View RDoc')
        @updateInstalledBtn = KDE::PushButton.new(KDE::Icon.new('view-refresh'), 'Update List')
        @updateAvailableBtn = KDE::PushButton.new(KDE::Icon.new('view-refresh'), 'Update List')
        @uninstallBtn = KDE::PushButton.new(KDE::Icon.new('list-remove'), 'Uninstall')

        @filterInstalledLineEdit = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('textChanged(const QString &)'),
                    @installedGemsTable, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
        end
        @filterInstalledBtn = KDE::PushButton.new('Filter') do |b|
           connect(b, SIGNAL(:clicked)) do
               @installedGemsTable.filterChanged(@filterInstalledLineEdit.text)
           end
        end
        @filterAvilableLineEdit = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('returnPressed(const QString &)'),
                    @availableGemsTable, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
        end
        @filterAvailableBtn = KDE::PushButton.new('Filter') do |b|
            connect(b, SIGNAL(:clicked)) do
                @availableGemsTable.filterChanged(@filterAvilableLineEdit.text)
            end
        end
        
        # connect
        connect(@viewDirBtn, SIGNAL(:clicked), self, SLOT(:viewDir))
        connect(@viewRdocBtn, SIGNAL(:clicked), self, SLOT(:viewRdoc))
        connect(@installBtn, SIGNAL(:clicked), self, SLOT(:installGem))
        connect(@uninstallBtn, SIGNAL(:clicked), self, SLOT(:uninstallGem))
        connect(@updateInstalledBtn, SIGNAL(:clicked),
                self, SLOT(:updateInstalledGemList))
        connect(@updateAvailableBtn, SIGNAL(:clicked),
                self, SLOT(:updateAvailableGemList))
        connect(@installedGemsTable, SIGNAL('itemClicked (QTableWidgetItem *)'),
                    self, SLOT('itemClicked (QTableWidgetItem *)'))
        connect(@availableGemsTable, SIGNAL('itemClicked (QTableWidgetItem *)'),
                    self, SLOT('itemClicked (QTableWidgetItem *)'))
        
        # layout
        @gemsTab = KDE::TabWidget.new
        @gemsTab.addTab(
            VBoxLayoutWidget.new do |w|
                w.addWidget(@filterInstalledLineEdit)
                w.addWidget(@installedGemsTable)
                w.addWidgetWithNilStretch(@updateInstalledBtn, nil,
                                          @viewDirBtn, @viewRdocBtn,
                                          @uninstallBtn)
            end ,
            'Installed Gems'
        )
        @gemsTab.addTab(
            VBoxLayoutWidget.new do |w|
                w.addWidgets(@filterAvilableLineEdit, @filterAvailableBtn)
                w.addWidget(@availableGemsTable)
                w.addWidgetWithNilStretch(@updateAvailableBtn, nil, @installBtn)
            end ,
            'Available Gems'
        )
        
        setCentralWidget(@gemsTab)
    end

    def createDlg
        @settingsDlg = SettingsDlg.new(self)
        @gemHelpdlg = GemHelpDlg.new(self)
    end

    def setupGems
        @gemsDb = GemsDb.new
    end

    def initializeAtStart
        updateInstalledGemList
        @gemsDb.initializeAvailableGemList(@availableGemsTable)
    end
        
    #------------------------------------
    #
    # virtual slot  
    def closeEvent(ev)
        @actions.writeSettings
        @installedGemsTable.closeEvent(ev)
        @availableGemsTable.closeEvent(ev)
        @gemHelpdlg.closeEvent(ev)
        super(ev)
    end


    #------------------------------------
    # slot
    def configureShortCut
        KDE::ShortcutsDialog.configure(@actions)
    end

    # slot
    def configureApp
        @settingsDlg.exec
    end

    # slot
    def gemCommandHelp
        @gemHelpdlg.show
    end

    
    #------------------------------------
    # installed list
    # slot
    def updateInstalledGemList
        @gemsDb.updateInstalledGemList(@installedGemsTable)
    end
        

    
    #------------------------------------
    # available list
    # slot
    def updateAvailableGemList
        @gemsDb.updateAvailableGemList(@availableGemsTable)
    end
    

    # slot
    def updateGemList
        case @gemsTab.currentIndex
        when 0
            updateInstalledGemList
        when 1
            updateAvailableGemList
        end
    end


    # slot
    def itemClicked(item)
        unless item.gem.spec then
            spec = GemSpec.getGemSpecInCache(item.gem)
            unless spec then
                specStr = %x{gem specification #{item.gem.package} -b --marshal}
                begin
                    spec = Marshal.load(specStr)
                rescue NoMethodError, ArgumentError => e
                    # rescue from some error gems.
                    @detailWin.setError(item.gem, e)
                    return
                end
            end
            item.gem.spec = spec
        end
        @detailWin.setDetail( item.gem )
        files = %x{gem contents --prefix #{item.gem.package}}.split(/[\r\n]+/)
        @fileListWin.setFiles( files )
    end
    
        
    # slot
    def viewRdoc
        gem = @installedGemsTable.currentGem
        return unless gem
        
        # make rdoc path
        pkg = gem.package
        ver = gem.latestVersion
        url = addGemPath('/doc/' + pkg + '-' + ver + '/rdoc/index.html')
        cmd = Settings.browserCmdForOpenDoc(url)
        fork do exec(cmd) end
    end

    def getGemPaths
        @gemPath ||= %x{gem environment gempath}.chomp.split(/:/)
    end
    
    def addGemPath(path)
        paths = getGemPaths
        file = nil
        paths.find do |p|
            file = p + path
            File.exist? file
        end
        file
    end


    # slot
    def viewDir
        gem = @installedGemsTable.currentGem
        return unless gem

        pkg = gem.package
        ver = gem.latestVersion
        url = addGemPath('/gems/' + pkg + '-' + ver)
        cmd = Settings.filerCmdForOpenDir(url)
        fork do exec(cmd) end
    end
    

    # slot
    def installGem
        gem = @availableGemsTable.currentGem
        return unless gem

        if Settings.installInSystemDirFlag then
            args = [ '-t', '-c', "#{APP_DIR}/gemcmdwin.rb", '--', 'install' ]
            args.push( gem.package )
            cmd = 'kdesu'
        else
            args = [ 'install' ]
            args.push( gem.package )
            cmd = "#{APP_DIR}/gemcmdwin.rb"
        end
        @termilanWin.processStart(cmd, args) do
            updateInstalledGemList
        end
    end

    # slot
    def uninstallGem
        gem = @installedGemsTable.currentGem
        return unless gem
        
        args = [ '-t', '-c', "#{APP_DIR}/gemcmdwin.rb", '--', 'uninstall' ]
        args.push( gem.package )
        @termilanWin.processStart('kdesu', args) do
            updateInstalledGemList
        end
    end

end


#
#    main start
#

about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION)
KDE::CmdLineArgs.init(ARGV, about)

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
