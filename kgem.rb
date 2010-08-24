#!/usr/bin/ruby
#
#    2010 by ruby.twiddler@gmail.com
#
#      Ruby Gem with KDE GUI
#

$KCODE = 'UTF8'
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_DIR = File.expand_path(File.dirname(__FILE__))
APP_VERSION = "0.1"

# standard libs
require 'fileutils'
require 'rubygems'
require 'rubygems/specification'
require 'sqlite3'
require 'json'
require 'uri'
require 'net/http'
require 'shellwords'

# additional libs
require 'korundum4'
require 'ktexteditor'

#
# my libraries and programs
#
# $:.unshift(APP_DIR)
require "mylibs"
require "settings"
require "gemsdb"


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
                /^(readme|.*license|todo)$/ => 'Normal',
                }
    def findMode(text)
        puts "file : " + text
        m = ModeTbl.find do |k,v|
            k =~ text
        end
        m ? m[1] : 'Ruby'
    end
    def setText(title, text)
        @titleLabel.text = title
        @document.setText(text)
        puts "mode = " + findMode(title)
        @document.setMode(findMode(title))
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

#--------------------------------------------------------------------
#
#
class SearchWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        createWidget
    end

    def createWidget
        @gemList = Qt::ListWidget.new
        @searchLine = KDE::LineEdit.new do |w|
            w.setClearButtonShown(true)
        end

        @searchBtn = KDE::PushButton.new(KDE::Icon.new('search'), i18n('Search'))
        @downloadBtn = KDE::PushButton.new(KDE::Icon.new('down-arrow'), i18n('Download'))
        @installBtn = KDE::PushButton.new(KDE::Icon.new('run-build-install'), i18n('Install'))

        # connect
        connect(@searchBtn, SIGNAL(:clicked), self, SLOT(:search))
        connect(@searchLine, SIGNAL(:returnPressed), self, SLOT(:search))
        connect(@gemList, SIGNAL('itemClicked(QListWidgetItem *)'), self, SLOT('itemClicked(QListWidgetItem *)'))
        connect(@downloadBtn, SIGNAL(:clicked), self, SLOT(:fetch))
        connect(@installBtn, SIGNAL(:clicked), self, SLOT(:install))

        # layout
        lo = Qt::VBoxLayout.new
        lo.addWidgets('Search Gems:', @searchLine, @searchBtn)
        lo.addWidget(@gemList)
        lo.addWidgets(nil, @downloadBtn, @installBtn)
        setLayout(lo)
    end

    attr_accessor :gemViewer
    slots  'itemClicked(QListWidgetItem *)'
    def itemClicked(item)
        gem = @gems[item.text]
        @gemViewer.setDetail(gem) if @gemViewer and gem
        @gemViewer.setFiles(nil)
    end

    slots  :search
    def search
        res = Net::HTTP.get(URI.parse( 'http://rubygems.org/api/v1/search.json?query=' + URI.escape(@searchLine.text)))
        gems = JSON.parse(res)
        @gems = {}
        gems.each do |g| @gems[g['name']] = GemItem.parseHashGem(g) end
        @gemList.clear
        @gemList.addItems(@gems.keys)
    end

    def getCurrentGem
        row = @gemList.currentRow
        return nil unless row < @gemList.count
        name = @gemList.item(row).text
        @gems[name]
    end

    slots  :fetch
    def fetch
        gem = getCurrentGem
        return gem unless gem

        Dir.chdir(Settings.autoFetchDownloadDir.pathOrUrl)
        %x{ gem fetch #{gem.package} }
        @gemViewer.notifyDownload
    end

    slots  :install
    def install
        gem = getCurrentGem
        return gem unless gem

    end
end

#--------------------------------------------------------------------
#
#
#
class DownloadWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        @dirty = true
        @filePathMap = {}
        createWidget
    end

    def createWidget
        @gemFileList = Qt::ListWidget.new
        @filterLine = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('textChanged(const QString &)'),
                    self, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
        end
        @installBtn = KDE::PushButton.new(KDE::Icon.new('run-build-install'), 'Install')
        @deleteBtn = KDE::PushButton.new(KDE::Icon.new('edit-delete'), 'Delete')

        #
        connect(@gemFileList, SIGNAL('itemClicked(QListWidgetItem *)'), self, SLOT('itemClicked(QListWidgetItem *)'))
        connect(@installBtn, SIGNAL(:clicked), self, SLOT(:install))
        connect(@deleteBtn, SIGNAL(:clicked), self, SLOT(:delete))

        # layout
        lo = Qt::VBoxLayout.new
        lo.addWidgets('Filter:', @filterLine)
        lo.addWidget(@gemFileList)
        lo.addWidgets(nil, @installBtn, @deleteBtn)
        setLayout(lo)
    end

    def getCurrentItem
        row = @gemFileList.currentRow
        return nil unless row < @gemFileList.count
        @gemFileList.item(row)
    end

    # virtual slot function
    def updateList
        if @dirty then
            def allFilesInDir(dir)
                exDir = File.expand_path(dir)
                Dir.chdir(dir)
                files = Dir['*.gem']
                files.each do |f|
                    @filePathMap[f] = File.join(exDir, f)
                end
                files
            end
            @filePathMap = {}
            files = allFilesInDir(Settings.autoFetchDownloadDir.pathOrUrl) +
                allFilesInDir("/usr/lib/ruby/gems/1.8/cache/") +
                allFilesInDir("#{ENV['HOME']}/.gem/ruby/1.8/cache/")

            @gemFileList.clear
            files.sort.each do |f|
                @gemFileList.addItem(f)
            end
            @dirty = false
        end
    end

    def notifyDownload
        @dirty = true
        updateList
    end

    attr_accessor :gemViewer
    slots  'itemClicked(QListWidgetItem *)'
    def itemClicked(item)
        filePath = @filePathMap[item.text]
        files = %x{ tar xvf #{filePath} data.tar.gz -O | gunzip -c | tar t }.split(/\n/)
        files.unshift
        @gemViewer.setFiles(files)
        spec = Marshal.load(%x{ gem specification #{filePath} --marshal })
        gem = GemItem::parseGemSpec(spec)
        @gemViewer.setDetail(gem)

        proc = lambda do |file|
            %x{ tar xvf #{filePath.shellescape} data.tar.gz -O | gunzip -c | tar x #{file.shellescape} -O }
        end
        @gemViewer.setGetFileProc(proc)
    end

    slots  :install
    def install

    end

    slots :delete
    def delete
    end

    slots 'filterChanged(const QString &)'
    def filterChanged(text)
        if text.nil? or text.empty? then
            regxs = nil
        else
            regxs = /#{text.strip}/i
        end

        @gemFileList.count.times do |idx|
            item = @gemFileList.item(idx)
            item.setHidden(!(regxs.nil? or regxs =~ item.text))
        end
    end
end

#--------------------------------------------------------------------
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
                @previewWin.setText( file, @getFileProc.call(file) ) if @previewWin
            end
        )
    end

    def setDetail(gem)
        @detailView.setDetail(gem)
    end

    def setFiles(files)
        @filesView.setFiles(files)
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


#--------------------------------------------------------------------
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
#
#
class ToolsWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    def createWidget
        @repoWin = RepositoryWidget.new

        # layout
        @toolsTab = KDE::TabWidget.new
        @toolsTab.addTab(@repoWin, i18n("Repositories"))
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@toolsTab)
        end
        setLayout(lo)
    end

end


class RepositoryWidget < Qt::Widget
    # gem sources -a http://gems.github.com
    #  http://gemcutter.org
    def initialize(parent=nil)
        super(nil)
        createWidget
    end

    def createWidget
        @addGithubCheckBox = Qt::CheckBox.new(i18n("add http://gems.github.com to repository"))
        appyBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok-apply'), i18n('Apply'))
        makeMirrorBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), i18n('Make Mirror'))

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@addGithubCheckBox)
            l.addWidgets(makeMirrorBtn, nil)
            l.addStretch
            l.addWidgets(appyBtn, nil)
        end
        setLayout(lo)
    end
end



#--------------------------------------------------------------------
#--------------------------------------------------------------------
#
#
#
class MainWindow < KDE::MainWindow
    slots   :updateGemList, :updateInstalledGemList
    slots   'itemClicked (QTableWidgetItem *)'
    slots   :viewRdoc, :viewDir, :installGem, :uninstallGem
    slots   :configureShortCut, :configureApp, :gemCommandHelp
    slots   :initializeAtStart

    def initialize
        super(nil)
        setCaption(APP_NAME)

        @actions = KDE::ActionCollection.new(self)
        createWidgets
        createMenu
        createDlg
        setupGems
        @actions.readSettings
        setAutoSaveSettings

        Qt::Timer.singleShot(0, self, SLOT(:initializeAtStart))
    end


    def createMenu
        # create actions
        updateListAction = KDE::Action.new(KDE::Icon.new('view-refresh'), 'Update List', self)
        updateListAction.setShortcut(KDE::Shortcut.new('Ctrl+R'))
        @actions.addAction(updateListAction.text, updateListAction)
        quitAction = KDE::Action.new(KDE::Icon.new('exit'), '&Quit', self)
        quitAction.setShortcut(KDE::Shortcut.new('Ctrl+Q'))
        @actions.addAction(quitAction.text, quitAction)
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
        detailWinAction = @detailWin.toggleViewAction
        fileListWinAction = @fileListWin.toggleViewAction
        termilanWinAction = @terminalWin.toggleViewAction

        settingsMenu = KDE::Menu.new(i18n('&Settings'), self)
        settingsMenu.addAction(detailWinAction)
        settingsMenu.addAction(fileListWinAction)
        settingsMenu.addAction(termilanWinAction)
        settingsMenu.addSeparator
        settingsMenu.addAction(configureShortCutAction)
        settingsMenu.addAction(configureAppAction)
        # connect actions
        connect(configureShortCutAction, SIGNAL(:triggered), self, SLOT(:configureShortCut))
        connect(configureAppAction, SIGNAL(:triggered), self, SLOT(:configureApp))


        # Help menu
        about = i18n(<<-ABOUT
#{APP_NAME} #{APP_VERSION}
    Ruby Gems Tool on KDE GUI
        ABOUT
        )
        helpMenu = KDE::HelpMenu.new(self, about)
        helpMenu.menu.addSeparator
        helpMenu.menu.addAction(gemHelpAction)

        # file menu
        fileMenu = KDE::Menu.new(i18n('&File'), self)
        fileMenu.addAction(updateListAction)
        fileMenu.addAction(quitAction)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( settingsMenu )
        menu.addMenu( helpMenu.menu )
        setMenuBar(menu)
    end



    def createWidgets
        # dockable window
        @detailWin = DetailWin.new(self)
        addDockWidget(Qt::BottomDockWidgetArea, @detailWin)
        @fileListWin = FileListWin.new(self)
        tabifyDockWidget(@detailWin, @fileListWin)
        @terminalWin = TerminalWin.new(self)
        tabifyDockWidget(@fileListWin, @terminalWin)

        @previewWin = PreviewWin.new

        gemViewer = DockGemViewer.new(@detailWin, @fileListWin, @previewWin)
        @toolsWin = ToolsWin.new(self)
        @searchWin = SearchWin.new(self) do |w|
            w.gemViewer = gemViewer
        end
        @downloadWin = DownloadWin.new(self) do |w|
            w.gemViewer = gemViewer
        end
        gemViewer.addDownloadWatcher(@downloadWin)


        # other
        @installedGemsTable = GemListTable.new('installed')

        @upgradeBtn = KDE::PushButton.new('Upgrade')
        @viewDirBtn = KDE::PushButton.new(KDE::Icon.new('folder'), 'View Directory')
        @viewRdocBtn = KDE::PushButton.new(KDE::Icon.new('help-contents'), 'View RDoc')
        @updateInstalledBtn = KDE::PushButton.new(KDE::Icon.new('view-refresh'), 'Update List')
        @uninstallBtn = KDE::PushButton.new(KDE::Icon.new('list-remove'), 'Uninstall')

        @filterInstalledLineEdit = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('textChanged(const QString &)'),
                    @installedGemsTable, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
        end

        # connect
        connect(@viewDirBtn, SIGNAL(:clicked), self, SLOT(:viewDir))
        connect(@viewRdocBtn, SIGNAL(:clicked), self, SLOT(:viewRdoc))
        connect(@uninstallBtn, SIGNAL(:clicked), self, SLOT(:uninstallGem))
        connect(@updateInstalledBtn, SIGNAL(:clicked),
                self, SLOT(:updateInstalledGemList))
        connect(@installedGemsTable, SIGNAL('itemClicked (QTableWidgetItem *)'),
                    self, SLOT('itemClicked (QTableWidgetItem *)'))

        # layout
        @mainTab = KDE::TabWidget.new do |w|
            connect(w, SIGNAL('currentChanged(int)'), self, SLOT('tabChanged(int)'))
        end
        @mainTab.addTab(
            VBoxLayoutWidget.new do |w|
                w.addWidgets('Filter:', @filterInstalledLineEdit)
                w.addWidget(@installedGemsTable)
                w.addWidgetWithNilStretch(@updateInstalledBtn, nil,
                                          @viewDirBtn, @viewRdocBtn,
                                          @uninstallBtn)
            end ,
            'Installed Gems'
        )
        @mainTab.addTab(@searchWin, i18n("Search"))
        @mainTab.addTab(@downloadWin, i18n("Downloaded Gems"))
        @mainTab.addTab(@toolsWin, i18n("Tools"))

        setCentralWidget(@mainTab)
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
    end

    #------------------------------------
    #
    # virtual slot
    def closeEvent(ev)
        @actions.writeSettings
        @installedGemsTable.closeEvent(ev)
        @gemHelpdlg.closeEvent(ev)
        @previewWin.writeSettings
        super(ev)
        $config.sync    # important!  qtruby can't invoke destructor properly.
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


    slots 'tabChanged(int)'
    def tabChanged(index)
        if @mainTab.widget(index) == @downloadWin then
            @downloadWin.updateList
        end
    end

    #------------------------------------
    # installed list
    # slot
    def updateInstalledGemList
        @gemsDb.updateInstalledGemList(@installedGemsTable)
    end





    # slot
    def updateGemList
        case @mainTab.currentIndex
        when 0
            updateInstalledGemList
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

        args = [ 'install' ]
        args.push( gem.package )
        cmd = if Settings.installInSystemDirFlag then
                "#{APP_DIR}/gemcmdwin-super.rb"
            else
                "#{APP_DIR}/gemcmdwin.rb"
                args.push( '--user-install' )
            end
        @terminalWin.processStart(cmd, args) do
            updateInstalledGemList
        end
    end


    # slot
    def uninstallGem
        gem = @installedGemsTable.currentGem
        return unless gem

        args = [ 'uninstall' ]
        args.push( gem.package )
        puts "installedLocal? : " + gem.installedLocal?.inspect
        cmd = if gem.installedLocal? then
                "#{APP_DIR}/gemcmdwin.rb"
            else
                "#{APP_DIR}/gemcmdwin-super.rb"
            end
        @terminalWin.processStart(cmd, args) do
            updateInstalledGemList
        end
    end

end


#
#    main start
#

about = KDE::AboutData.new(APP_NAME, nil, KDE::ki18n(APP_NAME), APP_VERSION)
KDE::CmdLineArgs.init(ARGV, about)

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
