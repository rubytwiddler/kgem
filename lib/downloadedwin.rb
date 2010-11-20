require 'time'

class FetchedGem
    attr_accessor  :fileName, :directory, :installed

    def filePath
        File.join(@directory, @fileName)
    end

    def installed_str
        @installed ? 'installed' : ''
    end
end

#
#
#
class DownloadedTable < Qt::TableWidget
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
        end
    end

    def initialize
        super(0,3)

        self.windowTitle = i18n('Search Result')
        setHorizontalHeaderLabels(['file name', 'directory', 'installed'])
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.selectionMode = Qt::AbstractItemView::SingleSelection
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(0, Qt::AscendingOrder)
        @fetchedGems = {}
    end

    def addPackage(row, fetchedGem)
        nameItem = Item.new(fetchedGem.fileName)
        @fetchedGems[nameItem] = fetchedGem    # 0 column item is hash key.
        setItem( row, 0, nameItem )
        setItem( row, 1, Item.new(fetchedGem.directory) )
        setItem( row, 2, Item.new(fetchedGem.installed_str) )
    end

    def updateGemList(gemList)
        sortFlag = self.sortingEnabled
        self.sortingEnabled = false

        clearContents
        self.rowCount = gemList.length
        gemList.each_with_index do |g,r|
            addPackage(r, g)
        end

        self.sortingEnabled = sortFlag
    end

    def gem(item)
        gemAtRow(item.row)
    end

    def gemAtRow(row)
        @fetchedGems[item(row,0)]       # use 0 column item as hash key.
    end

    def currentGem
        gemAtRow(currentRow)
    end

    def showall
        rowCount.times do |r|
            showRow(r)
        end
    end

    slots 'filterChanged(const QString &)'
    def filterChanged(text)
        unless text && !text.empty?
            showall
            return
        end

        regxs = /#{Regexp.escape(text.strip)}/i
        rowCount.times do |r|
            txt = item(r,0).text.gsub(/\.gem$/, '')
            if regxs =~ txt then
                showRow(r)
            else
                hideRow(r)
            end
        end
    end
end


#----------------------------------------------------------------------------
#
#
#
class DownloadedWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        createWidget
        readSettings

        Qt::Timer.singleShot(0, self, SLOT(:updateList))
    end

    GemDirs = GemCmd.exec("environment gempath").split(/:/).map! do |dir|
        File.join(dir.strip, 'cache')
    end

    def createWidget
        @gemFileList = DownloadedTable.new
        @filterLine = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('textChanged(const QString &)'),
                    @gemFileList, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
        end

        @installBtn = KDE::PushButton.new(KDE::Icon.new('run-build-install'), 'Install')
        @deleteBtn = KDE::PushButton.new(KDE::Icon.new('edit-delete'), 'Delete')
        @unpackBtn = KDE::PushButton.new('Unpack')

        #
        connect(@gemFileList, SIGNAL('itemClicked(QTableWidgetItem *)'), self, SLOT('itemClicked(QTableWidgetItem *)'))
        connect(@installBtn, SIGNAL(:clicked), self, SLOT(:install))
        connect(@deleteBtn, SIGNAL(:clicked), self, SLOT(:delete))
        connect(@unpackBtn, SIGNAL(:clicked), self, SLOT(:unpack))

        # layout
        lo = Qt::VBoxLayout.new
        lo.addWidgets('Filter:', @filterLine)
        lo.addWidget(@gemFileList)
        lo.addWidgets(nil, @installBtn, @unpackBtn, @deleteBtn)
        setLayout(lo)
    end

    GroupName = "DownloadedGemWindow"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', @gemFileList.horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        @gemFileList.horizontalHeader.restoreState(config.readEntry('Header', @gemFileList.horizontalHeader.saveState))
    end


    slots :updateList
    def updateList
        def allFilesInDir(dir)
            return [] unless dir
            exDir = File.expand_path(dir)
            return [] unless File.directory?(exDir)
            Dir.chdir(exDir)
            files = Dir['*.gem']
            gems = files.map do |f|
                fGem = FetchedGem.new
                fGem.fileName = f
                fGem.directory = exDir
                fGem.installed = InstalledGemList.checkVersionedGemInstalled(f)
                fGem
            end
        end

        dirs = GemDirs + [ Settings.autoFetchDir ]
        gems = dirs.uniq.inject([]) do |res, dir|
            res + allFilesInDir(dir)
        end

        #
        @gemFileList.updateGemList(gems)

        @filterLine.text = ''
    end

    def notifyDownload
        updateList
    end

    def notifyInstall
        updateList
    end

    attr_accessor :gemViewer
    slots  'itemClicked(QTableWidgetItem *)'
    def itemClicked(item)
        fetchedGem = @gemFileList.gem(item)
        return unless fetchedGem
        filePath = fetchedGem.filePath
        return unless File.exist?(filePath)

        @installBtn.enabled =  @deleteBtn.enabled = ! fetchedGem.installed
        files = %x{ tar xf #{filePath} data.tar.gz -O | gunzip -c | tar t }.split(/\n/)
        files.unshift
        @gemViewer.setFiles(files)
        gem = GemItem::getGemfromCache(filePath)
        @gemViewer.setDetail(gem)

        proc = lambda do |item|
            file = item.text
            @gemViewer.previewWin.setText( file, %x{ tar xf #{filePath.shellescape} data.tar.gz -O | gunzip -c | tar x #{file.shellescape} -O } )
        end
        @gemViewer.setPreviewProc(proc)
    end

    slots :install
    def install
        fetchedGem = @gemFileList.currentGem
        return unless fetchedGem and !fetchedGem.installed

        filePath = fetchedGem.filePath
        gem = GemItem::getGemfromPath(filePath)
        gem.addLocalPath(filePath)
        @gemViewer.install(gem, true)   # localFlag = true
    end

    slots :delete
    def delete
        fetchedGem = @gemFileList.currentGem
        return unless fetchedGem and  !(GemDirs.include?(fetchedGem.directory) \
                                        and fetchedGem.installed)

        filePath = fetchedGem.filePath
        if File.writable?(filePath) then
            File.unlink(filePath)
            passiveMessage(i18n('Deleted ') + filePath)
            updateList
        end
    end

    slots  :unpack
    def unpack
        fetchedGem = @gemFileList.currentGem
        filePath = fetchedGem.filePath
        if Settings.autoUnpackFlag then
            dir = Settings.autoUnpackDir
        else
            dir = Qt::FileDialog::getExistingDirectory(nil, 'select folder',  Settings.autoUnpackDir)
            return unless dir
            Settings.autoUnpackDir.setUrl(dir)
        end
        outDir = File.join(dir, File.basename(filePath).sub(File.extname(filePath),''))
        FileUtils.remove_dir(outDir, true)
        FileUtils.mkdir_p(outDir)
        %x{ tar xf #{filePath.shellescape} data.tar.gz -O | gunzip -c | tar x --directory=#{outDir.shellescape} }
    end

end
