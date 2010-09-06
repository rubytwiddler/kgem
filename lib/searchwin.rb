#
#
#
class SearchTable < Qt::TableWidget
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
        end
    end

    class NumItem < Item
        def lessThan(i)
            self.text.to_i < i.text.to_i
        end
        alias :'operator<' :lessThan
    end

    def initialize
        super(0,3)

        self.windowTitle = i18n('Search Result')
        setHorizontalHeaderLabels(['name', 'version', 'downloads'])
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.selectionMode = Qt::AbstractItemView::SingleSelection
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(0, Qt::AscendingOrder)
        @gems = {}
    end

    def addPackage(row, gem)
        nameItem = Item.new(gem.package)
        @gems[nameItem] = gem   # 0 column item is hash key.
        setItem( row, 0, nameItem )
        setItem( row, 1, Item.new(gem.version) )
        setItem( row, 2, NumItem.new(gem.downloads.to_s) )
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
        @gems[item(row,0)]       # use 0 column item as hash key.
    end

    def currentGem
        gemAtRow(currentRow)
    end
end


#----------------------------------------------------------------------------
#
#
#
class SearchWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        createWidget
        readSettings
    end

    def createWidget
        @gemList = SearchTable.new      #Qt::ListWidget.new
        @searchLine = KDE::LineEdit.new do |w|
            w.setClearButtonShown(true)
        end

        @searchBtn = KDE::PushButton.new(KDE::Icon.new('search'), i18n('Search'))
        @downloadBtn = KDE::PushButton.new(KDE::Icon.new('download'), i18n('Download'))
        @installBtn = KDE::PushButton.new(KDE::Icon.new('run-build-install'), i18n('Install'))

        # connect
        connect(@searchBtn, SIGNAL(:clicked), self, SLOT(:search))
        connect(@searchLine, SIGNAL(:returnPressed), self, SLOT(:search))
        connect(@gemList, SIGNAL('itemClicked(QTableWidgetItem *)'), self, SLOT('itemClicked(QTableWidgetItem *)'))
        connect(@downloadBtn, SIGNAL(:clicked), self, SLOT(:fetch))
        connect(@installBtn, SIGNAL(:clicked), self, SLOT(:install))

        # layout
        lo = Qt::VBoxLayout.new
        lo.addWidgets('Search Gems:', @searchLine, @searchBtn)
        lo.addWidget(@gemList)
        lo.addWidgets(nil, @downloadBtn, @installBtn)
        setLayout(lo)
    end

    GroupName = "SearchWindow"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', @gemList.horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        @gemList.horizontalHeader.restoreState(config.readEntry('Header', @gemList.horizontalHeader.saveState))
    end


    attr_accessor :gemViewer
    slots  'itemClicked(QTableWidgetItem *)'
    def itemClicked(item)
        gem = @gemList.gem(item)
        @gemViewer.setDetail(gem) if @gemViewer and gem
        @gemViewer.setFiles(nil)
    end

    slots  :search
    def search
        res = Net::HTTP.get(URI.parse( 'http://rubygems.org/api/v1/search.json?query=' + URI.escape(@searchLine.text)))
        gems = JSON.parse(res)
        gems.map! do |g| GemItem.parseHashGem(g) end
        @gemList.updateGemList(gems)
    end


    slots  :fetch
    def fetch
        gem = @gemList.currentGem
        return unless gem

        @gemViewer.download(gem)
    end

    slots  :install
    def install
        gem = @gemList.currentGem
        return gem unless gem

        @gemViewer.install(gem, false)   # localFlag = false
    end
end
