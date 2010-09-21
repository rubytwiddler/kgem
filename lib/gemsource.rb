require 'set'

class GemSourceDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        self.windowTitle = i18n('Gem sources')
        createWidget
    end

    def createWidget
        @sourceList = Qt::ListWidget.new
        @rubygemsCheckBox = Qt::CheckBox.new(i18n('add rubygems source'))
        connect(@rubygemsCheckBox, SIGNAL('stateChanged(int)'), self, \
                SLOT('rubygemsStateChanged(int)'))
        @githubCheckBox = Qt::CheckBox.new(i18n('add github source'))
        connect(@githubCheckBox, SIGNAL('stateChanged(int)'), self, \
                SLOT('githubStateChanged(int)'))
        @addUrlLineEdit = KDE::LineEdit.new
        @addBtn = KDE::PushButton.new(i18n('add'))
        @deleteBtn = KDE::PushButton.new(i18n('delete'))
        @okBtn = KDE::PushButton.new(KDE::Icon.new('dialog-ok'), i18n('Ok'))
        @cancelBtn = KDE::PushButton.new(KDE::Icon.new('dialog-cancel'), i18n('Cancel'))
        connect(@addBtn, SIGNAL(:clicked), self, SLOT(:addItem))
        connect(@deleteBtn, SIGNAL(:clicked), self, SLOT(:deleteItem))
        connect(@okBtn, SIGNAL(:clicked), self, SLOT(:accept))
        connect(@cancelBtn, SIGNAL(:clicked), self, SLOT(:reject))

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@sourceList)
            l.addWidget(@rubygemsCheckBox)
            l.addWidget(@githubCheckBox)
            l.addWidgets(@deleteBtn, nil)
            l.addWidgets(@addBtn, @addUrlLineEdit)
            l.addWidgets(nil, @okBtn, @cancelBtn)
            l.addStretch
        end
        setLayout(lo)
    end

    UrlRegexp = URI.regexp(['http', 'https'])
    GithubUrl = 'http://gems.github.com'
    RubygemsUrl = 'http://rubygems.org/'
    SystemUrls = [ GithubUrl, RubygemsUrl ]
    def updateSources
        @sourceList.clear
        @sourceUrls = {}
        @rubygemsCheckBox.checked = false
        @githubCheckBox.checked = false
        %x{ gem sources -l }.split(/\n/).each do |line|
            url = line[UrlRegexp]
            if url then
                case url
                when RubygemsUrl
                    @rubygemsCheckBox.checked = true
                when GithubUrl
                    @githubCheckBox.checked = true
                else
                    @sourceUrls[url] = item = Qt::ListWidgetItem.new(url)
                    @sourceList.addItem(item)
                end
            end
        end
        @orgUrls = Set.new(@sourceUrls.keys)
    end

    def addUrl(url)
        unless @sourceUrls[url] then
            @sourceUrls[url] = item = Qt::ListWidgetItem.new(url)
            @sourceList.addItem(item)
        end
    end

    def deleteUrl(url)
        if @sourceUrls[url] then
            row = @sourceList.row(@sourceUrls[url])
            @sourceList.takeItem(row)
#             @sourceList.removeItemWidget(@sourceUrls[url]) # cannot use ?
            @sourceUrls.delete(url)
        end
    end

    slots :addItem
    def addItem
        url = @addUrlLineEdit.text.strip
        case url
        when RubygemsUrl
            @rubygemsCheckBox.checked = true
        when GithubUrl
            @githubCheckBox.checked = true
        else
            unless url.empty? or @sourceUrls.has_key?(url) then
                addUrl(url)
            end
        end
    end

    slots :deleteItem
    def deleteItem
        row = @sourceList.currentRow
        return unless row >= 0
        case @sourceList.item(row).text
        when RubygemsUrl
            @rubygemsCheckBox.checked = false
        when GithubUrl
            @githubCheckBox.checked = false
        else
            @sourceList.takeItem(row)
        end
    end

    #-----------------
    def exec
        updateSources
        super
    end

    slots 'githubStateChanged(int)'
    def githubStateChanged(state)
        if state == Qt::Checked then
            addUrl(GithubUrl)
        else
            deleteUrl(GithubUrl)
        end
    end

    slots 'rubygemsStateChanged(int)'
    def rubygemsStateChanged(state)
        if state == Qt::Checked then
            addUrl(RubygemsUrl)
        else
            deleteUrl(RubygemsUrl)
        end
    end

    # overwrite virtual method
    def accept
        msg = ""
        newUrls = Set.new(@sourceUrls.keys)
        deletes =  @orgUrls - newUrls
        deletes.each do |url|
            msg += "delete #{url}\n"
            %x{ gem sources --remove #{url} }
        end

        adds =  newUrls - @orgUrls
        adds.each do |url|
            msg += "add #{url}\n"
            %x{ gem sources --add #{url} }
        end
        unless msg.empty? then
            KDE::MessageBox.information(self, msg)
        end
        super
    end
end
