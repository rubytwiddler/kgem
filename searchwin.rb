#
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
        @downloadBtn = KDE::PushButton.new(KDE::Icon.new('download'), i18n('Download'))
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
end
