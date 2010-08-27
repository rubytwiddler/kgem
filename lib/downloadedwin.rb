#
#
#
class DownloadedWin < Qt::Widget
    def initialize(parent=nil)
        super(parent)

        @filePathMap = {}
        createWidget

        Qt::Timer.singleShot(0, self, SLOT(:updateList))
    end

    def createWidget
        @gemFileList = Qt::ListWidget.new
        @filterLine = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('textChanged(const QString &)'),
                    self, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
        end

        @updateBtn = KDE::PushButton.new(KDE::Icon.new('view-refresh'), 'Update List')
        @installBtn = KDE::PushButton.new(KDE::Icon.new('run-build-install'), 'Install')
        @deleteBtn = KDE::PushButton.new(KDE::Icon.new('edit-delete'), 'Delete')

        #
        connect(@gemFileList, SIGNAL('itemClicked(QListWidgetItem *)'), self, SLOT('itemClicked(QListWidgetItem *)'))
        connect(@installBtn, SIGNAL(:clicked), self, SLOT(:install))
        connect(@deleteBtn, SIGNAL(:clicked), self, SLOT(:delete))
        connect(@updateBtn, SIGNAL(:clicked),
                self, SLOT(:updateList))

        # layout
        lo = Qt::VBoxLayout.new
        lo.addWidgets('Filter:', @filterLine)
        lo.addWidget(@gemFileList)
        lo.addWidgets(@updateBtn, nil, @installBtn, @deleteBtn)
        setLayout(lo)
    end

    def getCurrentItem
        row = @gemFileList.currentRow
        return nil unless row < @gemFileList.count
        @gemFileList.item(row)
    end

    # virtual slot function
    slots :updateList
    def updateList
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

        # update ListWidget
        @gemFileList.clear
        files.sort.each do |f|
            @gemFileList.addItem(f)
        end

        @selectedGemFile = nil
    end

    def notifyDownload
        updateList
    end

    def notifyInstall
        updateList
    end

    attr_accessor :gemViewer
    slots  'itemClicked(QListWidgetItem *)'
    def itemClicked(item)
        @selectedGemFile = item.text
        filePath = @filePathMap[item.text]
        return unless File.exist?(filePath)

        files = %x{ tar xvf #{filePath} data.tar.gz -O | gunzip -c | tar t }.split(/\n/)
        files.unshift
        @gemViewer.setFiles(files)
        spec = Marshal.load(%x{ gem specification #{filePath} --marshal })
        gem = GemItem::parseGemSpec(spec)
        @gemViewer.setDetail(gem)

        proc = lambda do |item|
            file = item.text
            @gemViewer.previewWin.setText( file, %x{ tar xvf #{filePath.shellescape} data.tar.gz -O | gunzip -c | tar x #{file.shellescape} -O } )
        end
        @gemViewer.setPreviewProc(proc)
    end

    slots :install
    def install
        return unless @selectedGemFile
        isInstalled = InstalledGemList.getCached.find do |g|
            (g.name + '-' + g.version + '.gem') == @selectedGemFile
        end
        return if isInstalled

        filePath = @filePathMap[@selectedGemFile]
        spec = Marshal.load(%x{ gem specification #{filePath} --marshal })
        gem = GemItem::parseGemSpec(spec)
        @gemViewer.install(gem)
    end

    slots :delete
    def delete
        return unless @selectedGemFile
        isInstalled = InstalledGemList.getCached.find do |g|
            (g.name + '-' + g.version + '.gem') == @selectedGemFile
        end
        filePath = @filePathMap[@selectedGemFile]
        if File.writable?(filePath) and !isInstalled then
            File.unlink(filePath)
            updateList
        end
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
