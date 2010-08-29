#
#
#
class GemListTable < Qt::TableWidget
    #
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
        end

        def gem
            tableWidget.gem(self)
        end
    end


    # column no
    PACKAGE_NAME = 0
    PACKAGE_VERSION = 1
    PACKAGE_SUMMARY = 2

    def initialize(title)
        super(0,3)

        self.windowTitle = title
        setHorizontalHeaderLabels(['package', 'version', 'summary'])
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(PACKAGE_NAME, Qt::AscendingOrder )
        @gems = {}
    end

    # caution ! : befor call, sortingEnabled must be set false.
    #   if sortingEnabled is on while updating table, it is very sluggish.
    def addPackage(row, gem)
#         self.sortingEnabled = false
        nameItem = Item.new(gem.package)
        @gems[nameItem] = gem           # 0 column item is hash key.
        setItem( row, PACKAGE_NAME, nameItem  )
        setItem( row, PACKAGE_VERSION, Item.new(gem.version) )
        setItem( row, PACKAGE_SUMMARY, Item.new(gem.summary) )
    end


    def updateGemList(gemList)
        sortFlag = self.sortingEnabled
        self.sortingEnabled = false

        self.clearContents
        self.rowCount = gemList.length
        gemList.each_with_index do |g, r|
            self.addPackage(r, g)
        end

        self.sortingEnabled = sortFlag
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


    slots   'filterChanged(const QString &)'
    def filterChanged(text)
        unless text && !text.empty?
            showall
            return
        end

        regxs = /#{Regexp.escape(text.strip)}/i
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
class InstalledGemWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        createWidget
        readSettings

        Qt::Timer.singleShot(0, self, SLOT(:updateInstalledGemList))
    end

    def createWidget
        @installedGemsTable = GemListTable.new('installed')

        @updateInstalledBtn = KDE::PushButton.new(KDE::Icon.new('view-refresh'), 'Update List')
        @viewDirBtn = KDE::PushButton.new(KDE::Icon.new('folder'), 'View Directory')
        @viewRdocBtn = KDE::PushButton.new(KDE::Icon.new('help-contents'), 'View RDoc')

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
        connect(@installedGemsTable, SIGNAL('itemClicked(QTableWidgetItem *)'),
                    self, SLOT('itemClicked(QTableWidgetItem *)'))

        # layout
        lo = Qt::VBoxLayout.new do |w|
                w.addWidgets('Filter:', @filterInstalledLineEdit)
                w.addWidget(@installedGemsTable)
                w.addWidgets(@updateInstalledBtn, nil,
                                          @viewDirBtn, @viewRdocBtn,
                                          @uninstallBtn)
            end
        setLayout(lo)
    end


    GroupName = "InstalledGemWindow"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', @installedGemsTable.horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        @installedGemsTable.horizontalHeader.restoreState(config.readEntry('Header', @installedGemsTable.horizontalHeader.saveState))
    end


    #------------------------------------
    #
    #
    def notifyInstall
        updateInstalledGemList
    end

    slots   :updateInstalledGemList
    def updateInstalledGemList
        gemList = InstalledGemList.get
        @installedGemsTable.updateGemList(gemList)
    end

    attr_accessor :gemViewer
    slots 'itemClicked(QTableWidgetItem *)'
    def itemClicked(item)
        unless item.gem.spec then
            specStr = %x{gem specification #{item.gem.package} -l --marshal}
            begin
                spec = Marshal.load(specStr)
            rescue NoMethodError, ArgumentError => e
                # rescue from some error gems.
                @gemViewer.setError(item.gem, e)
                return
            end
            item.gem.spec = spec
        end
        @gemViewer.setDetail( item.gem )
        files = %x{gem contents --prefix #{item.gem.package}}.split(/[\r\n]+/)
        @gemViewer.setFiles( files )

        proc = lambda do |item|
            file = item.text
            @gemViewer.previewWin.setFile( file )
        end
        @gemViewer.setPreviewProc(proc)
    end

    slots :viewRdoc
    def viewRdoc
        gem = @installedGemsTable.currentGem
        return unless gem

        # make rdoc path
        pkg = gem.package
        ver = gem.latestVersion
        url = findGemPath('/doc/' + pkg + '-' + ver + '/rdoc/index.html')
        cmd= Mime::services('.html').first.exec
        cmd.gsub!(/%\w+/, url)
        fork do exec(cmd) end
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


    slots :viewDir
    def viewDir
        gem = @installedGemsTable.currentGem
        return unless gem

        pkg = gem.package
        ver = gem.latestVersion
        url = findGemPath('/gems/' + pkg + '-' + ver)
        cmd = KDE::MimeTypeTrader.self.query('inode/directory').first.exec[/\w+/]
        cmd += " " + url
        fork do exec(cmd) end
    end

    slots :uninstallGem
    def uninstallGem
        gem = @installedGemsTable.currentGem
        return unless gem

        @gemViewer.uninstall(gem)
    end

end
