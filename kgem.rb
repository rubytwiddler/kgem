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

#--------------------------------------------------------------------
#
#   Items
#
module PackageStatus
    # package status
    STATUS_INSTALLED = 'installed'
    STATUS_NOTINSTALLED = ''
    STATUS_LATEST = 'latest'
    STATUS_OLD = 'old'
end
include PackageStatus

class GemItem
    attr_accessor   :package, :version, :author, :rubyforge, :homepage, :platform
    attr_accessor   :summary, :status, :spec
    alias   :name :package
    def initialize(pkg_and_ver, ver=nil)
        if ver.nil?
            pkg, ver = pkg_and_ver.split(/ /, 2)
            ver.tr!('()', '')
        else
            pkg = pkg_and_ver
        end
        @package = pkg
        @version = ver
        @author = ''
        @rubyforge = ''
        @homepage = ''
        @platform = ''
        @summary = ''
        @status = STATUS_NOTINSTALLED
        @spec = nil
    end
    
    def latestVersion
        version.split(/,/, 2)[0]
    end

end

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
            txt = gem.package + gem.summary + gem.author + gem.platform
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
        @textPart.openExternalLinks = true
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
        html.insertUrl('platform', gem.platform)
        html.insertHtml("</table><p>")
        html.insertHtml(gem.spec.description.gsub(/\n/,'<br>'))
        
        @textPart.insertHtml(html)
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
    
#     def keyPressEvent(event)
#         print event.text
#         @process.write(event.text) if @process
#     end
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

    def initialize
        super(nil)
        setCaption(APP_NAME)

        @actions = KDE::ActionCollection.new(self)
        createMenu
        createWidgets
        createDlg
        @actions.readSettings
        setAutoSaveSettings
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
        @viewRdocBtn = KDE::PushButton.new(KDE::Icon.new('help-about'), 'View RDoc')
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
        setupProgressDlg
        begin
            updateGemListTable(:openLocalGemList, @installedGemsTable, STATUS_INSTALLED)
        ensure
            @progressDlg.dispose
            @progressDlg = nil
        end
    end

    def openLocalGemList
        open('|gem query -d -l')
    end
    
    #------------------------------------
    # available list
    # slot
    def updateAvailableGemList
        setupProgressDlg
        begin
#             updateGemListTable(:openRemoteGemList, @availableGemsTable, STATUS_NOTINSTALLED)
#             updateGemListFromCache
#             createGemDb
            updateGemListFromDb
            updateGemDiffrence
        ensure
            @progressDlg.dispose
            @progressDlg = nil
        end
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

    def updateGemListTable(openMethod, tbl, status)
        gemList = makeGemList(openMethod)
        return unless gemList

        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false

        @progressDlg.labelText = "Makeing Gem Table"
        @progressDlg.setRange(0, gemList.length)
        @progressDlg.setValue(0)

        tbl.clearContents
        tbl.rowCount = gemList.length
        gemList.each_with_index do |g, r|
            g.status = status
            tbl.addPackage(r, g)
            @progressDlg.setValue(r)
        end

        tbl.sortingEnabled = sortFlag
    end

    def updateGemListFromCache
        tbl = @availableGemsTable
        status = STATUS_NOTINSTALLED
        
        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false
        
        Dir.chdir(getGemSpecDir)
        files = Dir['*.gemspec']
        tbl.clearContents
        tbl.rowCount = files.length
        row = 0
        files.each do |f|
            if f =~ /^(.+)-([\d\.]+)\.gemspec/ then
                gem = GemItem.new($1, $2)
#                 specStr = %x{gem specification #{gem.package} -b --marshal}
                specStr = open(gem.package).read
#                 print "#{gem.package}, "
#                 STDOUT.flush
                spec = Marshal.load(specStr)
                gem.summary = spec.summary
                gem.author = spec.authors
                gem.rubyforge = spec.rubyforge_project
                gem.homepage = spec.homepage
                gem.platform = spec.original_platform
                gem.status = status
                tbl.addPackage(row, gem)
                row += 1
            end
        end

        tbl.sortingEnabled = sortFlag
    end

    GEM_SPEC_DB = "#{ENV['HOME']}/.gem/gemspec.db"
    def createGemDb
        FileUtils.mkdir_p("#{ENV['HOME']}/.gem")
        db = SQLite3::Database.new(GEM_SPEC_DB)

        db.execute( "drop table gems" )
        db.execute( <<-EOF
create table gems (id INTEGER PRIMARY KEY,
    rubygems_version TEXT,
    specification_version TEXT,
    name TEXT,
    version TEXT,
    date TEXT,
    summary TEXT,
    required_ruby_version TEXT,
    required_rubygems_version TEXT,
    original_platform TEXT,
    dependencies TEXT,
    rubyforge_project TEXT,
    email TEXT,
    authors TEXT,
    description TEXT,
    homepage TEXT,
    has_rdoc TEXT,
    new_platform TEXT,
    licenses TEXT,
    installed_version TEXT)
        EOF
        )

        status = STATUS_NOTINSTALLED
        gemList = makeGemList(:openRemoteGemList)
        return unless gemList

        @progressDlg.labelText = "Inserting Gem in DB"
        @progressDlg.setRange(0, gemList.length)
        @progressDlg.setValue(0)

        gemList.each_with_index do |g, r|
            g.status = status
            name = g.package.sql_escape
            summary = g.summary.sql_escape
            version = g.version
            puts "#{name} : summary #{summary}: ver #{version}"
            STDOUT.flush
            db.execute(<<-EOF
insert into gems (name, summary, version)
    values ('#{g.package.sql_escape}', '#{g.summary.sql_escape}', '#{g.version}')
            EOF
            )
            @progressDlg.setValue(r)
        end
    end


    def updateGemListFromDb
        tbl = @availableGemsTable
        status = STATUS_NOTINSTALLED

        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false
        tbl.clearContents

        db = SQLite3::Database.new(GEM_SPEC_DB)
        size = db.get_first_value( "select count(*) from gems" ) .to_i
        puts "total size :#{size}"
        tbl.rowCount = size
        
        @progressDlg.labelText = "Update Gem Table from DB"
        @progressDlg.setRange(0, size + 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)

        db.results_as_hash = true
        i = 0
        db.execute("select * from gems") do |r|
            r['name']
            gem = GemItem.new(r['name'], r['version'])
#             print "#{gem.package}, "
#             STDOUT.flush

            gem.summary = r['summary']
            gem.author = r['authors']
            gem.rubyforge = r['rubyforge_project']
            gem.homepage = r['homepage']
            gem.platform = r['original_platform']
            gem.status = status
            tbl.addPackage(i, gem)
            i += 1
            @progressDlg.setValue(i)
        end
        tbl.sortingEnabled = sortFlag
    end

    def updateGemDiffrence
        db = SQLite3::Database.new(GEM_SPEC_DB)
        size = db.get_first_value( "select count(*) from gems" ) .to_i
        
        @progressDlg.labelText = "Differencial Update from Remote Data"
        @progressDlg.setRange(0, size + 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)
        
        gemsStr = %x{gem query -r -a}.split(/(\n|\r)/)
        i = 0
        gemsStr.each do |line|
            if line =~ /^([\w\-]+)\s+\((.+)\)/
                pkg, vers= $1, $2.split(/,\s*/)
                locVer = db.get_first_value("select version from gems where name='#{pkg}'")
                if /#{locVer}/ !~ vers[0] then
                    puts "updateing gem info pkg : #{pkg}, locVer :#{locVer}, latest ver:#{vers[0]}"

    #             db.execute("update #{pkg} from gems")
                end
                @progressDlg.setValue(i)
                i += 1
            end
        end
    end
    
    def setupProgressDlg
        @progressDlg = Qt::ProgressDialog.new
        @progressDlg.labelText = "Processing Gem List"
        @progressDlg.setRange(0, GemReadRangeSize)
        @progressDlg.forceShow
        @progressDlg.setWindowModality(Qt::WindowModal)
    end
    
    GemReadRange = 'a'..'z'
    GemReadRangeSize = GemReadRange.count
    # @return gemList
    def makeGemList(openMethod)
        gemList = nil
        catch (:canceled) do
            gemf = self.method(openMethod).call
            gemList = parseGemFile(gemf)
        end
        gemList
    end

    GEM_MAX = 5331  # not need accuracy. just for progress bar
    # @param gemf : gem data IO
    # @return gemList
    def parseGemFile(gemf)
        gemList = nil
        cnt = 0
        @progressDlg.labelText = "Parsing Gem Table"
        @progressDlg.setRange(0, GEM_MAX+ 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)

        begin
            summary = ''
            gem = nil
            while line = gemf.gets
                case line
                when /^(\w.*)/ then
                    if gem then
                        gem.summary = summary.strip
                        gemList ||= []
                        gemList << gem
                        cnt += 1
                        @progressDlg.setValue(cnt)
                    end
                    gem = GemItem.new($1)
                    summary = ''
                when /\s+Authors?:\s*(.*)\s*/i
                    gem.author = $1
                when /\s+Rubyforge:\s*(.*)\s*/i
                    gem.rubyforge = $1
                when /\s+Homepage:\s*(.*)\s*/i
                    gem.homepage = $1
                when /\s+Platform:\s*(.*)\s*/i
                    gem.platform = $1
                when /\s+Installed\s+at.*?:\s*(.*)\s*/i
                when /\s+\(.*?\):\s*(.*)\s*/i
                else
                    summary += line.strip + "\n"
                end
            end
            gem.summary = summary.strip
            gemList << gem
        ensure
            gemf.close
        end
        gemList
    end

    
    # open cache data in tmp dir
    def openRemoteGemList
        tmpdir = Qt::Dir.tempPath + "/#{APP_NAME}/cache"
        FileUtils.mkdir_p(tmpdir)
        tmpName = 'gemdata.raw'
        tmpPath = tmpdir + '/' + tmpName
        unless File.exist?(tmpPath) then
            @progressDlg.labelText = "Loading Gem List from Net."
            @progressDlg.setRange(0, GemReadRangeSize + 1)  # +1 for avoid closeing progressDlg
            @progressDlg.setValue(0)
            open(tmpPath, 'w') do |f|
                cnt = 0
                GemReadRange.each do |c|
                    throw :canceled if @progressDlg.wasCanceled
                    @progressDlg.setValue(cnt)
                    cnt += 1
                    f.write(%x{gem query -n '^#{c}' -d -r})
               end
            end
        end
        
        open(tmpPath)
    end


    # slot
    def itemClicked(item)
        unless item.gem.spec then
            spec = getGemSpecCache(item.gem)
            unless spec then
                specStr = %x{gem specification #{item.gem.package} -b --marshal}
                spec = Marshal.load(specStr)
            end
            item.gem.spec = spec
        end
        @detailWin.setDetail( item.gem )
        files = %x{gem contents #{item.gem.package}}.split(/[\r\n]+/)
        @fileListWin.setFiles( files )
    end
    
    def getGemSpecCache(gem)
        file = getGemSpecDir + '/' + gem.package + '-' + gem.latestVersion + '.gemspec'
        spec = nil
        if File.file?(file) then
            open(file) do |f|
                spec = Marshal.load(f.read)
            end
        end
        spec
    end

    def getGemSpecDir
        dir = "#{ENV['HOME']}/.gem/specs/"
        begin
            Dir.chdir(dir)
            dirs = Dir['*']
            while (dir = dirs.shift) && !File.directory?(dir) do end
        end while dir
        Dir.pwd
    end
        
    # slot
    def viewRdoc
        # make rdoc path
        gem = @installedGemsTable.currentGem
        pkg = gem.package
        ver = gem.latestVersion
        url = getGemDir + '/doc/' + pkg + '-' + ver + '/rdoc/index.html'
        cmd = Settings.browserCmdForOpenDoc(url)
        fork do exec(cmd) end
    end
    

    def getGemDir
        $LOAD_PATH[0].sub(/site_ruby/, 'gems')
    end

    # slot
    def viewDir
        gem = @installedGemsTable.currentGem
        pkg = gem.package
        ver = gem.latestVersion
        url = getGemDir + '/gems/' + pkg + '-' + ver
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
