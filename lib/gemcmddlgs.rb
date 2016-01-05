
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
#         if options.installUnitTestFlag then
#             args.push( '--test' )
#         else
#             args.push( '--no-test' )
#         end
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
        securityPolicy = options.installTrustPolicyStr
        if securityPolicy !~ /NoSecurity/ then
            args.push( '-P' )
            args.push( securityPolicy )
        end

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
        vers = gem.availableVersions
        return unless vers
        @versionComboBox.addItems(vers)
        @versionComboBox.currentIndex = 0
        Settings.updateWidgets(self)
        @optionsPage.installInSystemVisible = false
        ret = exec == Qt::Dialog::Accepted
        @optionsPage.installInSystemVisible = true
        ret
    end

    def confirmUpdateAll
        @allCheckBox.checked = true
        @allCheckBox.enabled = false
        @versionWidget.visible = false
        self.windowTitle = @msgLabel.text = i18n('Update All Gems')

        Settings.updateWidgets(self)
        @optionsPage.installInSystemVisible = false
        ret = exec == Qt::Dialog::Accepted
        @optionsPage.installInSystemVisible = true
        ret
    end


    include InstallOption

    def makeUpdateArgs
        Settings.updateSettings(self)

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
        @skipVersionCheck.objectName = 'kcfg_installLatestFlag'
        @forceCheckBox = Qt::CheckBox.new(i18n('Force gem to install, bypassing dependency checks'))

        @optionsPage = InstallOptionsPage.new

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@msgLabel)
            l.addWidgets('Version :', @versionComboBox, @checkOtherVersion, nil)
            l.addWidget(@skipVersionCheck)
            l.addWidget(@forceCheckBox)
            l.addWidget(@optionsPage)
            l.addWidgets(nil, @okBtn, @cancelBtn)
        end
        setLayout(lo)
    end

    slots :checkOtherVersion
    def checkOtherVersion
        @versionComboBox.clear
        vers = @gem.availableVersions
        return unless vers
        @versionComboBox.addItems(vers)
        @versionComboBox.currentIndex = 0
    end

    def selectVersion(gem)
        @gem = gem
        @versionComboBox.clear
        @versionComboBox.addItem(gem.version)
        @msgLabel.text = 'Install gem ' + gem.name + ' (' + gem.version.strip + ')'
        Settings.updateWidgets(self)
        return true if @skipVersionCheck.checked
        exec == Qt::Dialog::Accepted
    end

    include InstallOption
    def makeInstallArgs(localFlag)
        Settings.updateSettings(self)

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
        @skipVersionCheck.objectName = 'kcfg_downloadLatestFlag'

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
        vers = @gem.availableVersions
        return unless vers
        @versionComboBox.addItems(vers)
        @versionComboBox.currentIndex = 0
    end

    def selectVersion(gem)
        @gem = gem
        @versionComboBox.clear
        @versionComboBox.addItem(gem.version)
        @msgLabel.text = 'Download gem ' + gem.name + ' (' + gem.version.strip + ')'
        Settings.updateWidgets(self)
        return true if @skipVersionCheck.checked
        exec == Qt::Dialog::Accepted
    end

    def makeDownloadArgs
        Settings.updateSettings(self)

        args = [ 'fetch' ]
        args.push( @gem.package )
        if @versionComboBox.currentIndex != 0 then
            args.push( '-v' )
            args.push( @versionComboBox.currentText )
        end
        args
    end
end
