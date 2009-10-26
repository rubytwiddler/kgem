#
#   settings.
#
require 'singleton'
#
require 'mylibs'


class Settings < SettingsBase
    def initialize
        super()

        setCurrentGroup("Preferences")

        # meta programed version.
        addBoolItem(:installInSystemDirFlag, true)
        addBoolItem(:autoFetchDownloadFlag, true)
        addUrlItem(:autoFetchDownloadDir, KDE::GlobalSettings.downloadPath)
        addChoiceItem(:browser4OpenDoc, %w{Konqueror Firefox Opera}, 0)
        addChoiceItem(:filer4OpenDir, %w{Dolphin Konqueror Krusader}, 0)
    end
end

class GeneralSettingsPage < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    def createWidget
        browserGroup = Qt::GroupBox.new("Document Browser")
        @browserCombo = Qt::ComboBox.new
        @browserCombo.addItems(%w{Konqueror Firefox Opera})
        @browserCombo.editable = false
        @filerCombo = Qt::ComboBox.new
        @filerCombo.addItems(%w{Dolphin Konqueror Krusader})
        @filerCombo.editable = false
        
        # objectNames
        @browserCombo.objectName = 'kcfg_browser4OpenDoc'
        @filerCombo.objectName = 'kcfg_filer4OpenDir'

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@browserCombo)
            l.addWidget(@filerCombo)
            l.addStretch
        end
        setLayout(lo)
    end
end


class FolderSettingsPage < Qt::Widget
    slots   'autoFetchChanged(int)'
    
    def initialize(parent=nil)
        super(parent)
        createWidget
    end
    
    def createWidget
        @installInSystemCheckBox = Qt::CheckBox.new("Install in System Directory. (Root access Required)")
        @autoFetchCheckBox = Qt::CheckBox.new("auto download for fetch without asking location every time.")
        @fileLine = KDE::UrlRequester.new(KDE::Url.new())
        @fileLine.enabled = false
        @fileLine.mode = KDE::File::Directory | KDE::File::LocalOnly
        connect(@autoFetchCheckBox, SIGNAL('stateChanged(int)'),
                self, SLOT('autoFetchChanged(int)'))
        
        # objectNames
        @installInSystemCheckBox.objectName = 'kcfg_installInSystemDirFlag'
        @autoFetchCheckBox.objectName = 'kcfg_autoFetchDownloadFlag'
        @fileLine.objectName = 'kcfg_autoFetchDownloadDir'
        
        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@installInSystemCheckBox)
            l.addWidget(@autoFetchCheckBox)
            l.addLayout(Qt::HBoxLayout.new do |hl|
                        hl.addWidget(Qt::Label.new('  '))
                        hl.addWidget(@fileLine)
                       end
                       )
            l.addStretch
        end
        setLayout(lo)
    end
    
    # slot
    def autoFetchChanged(state)
        @fileLine.enabled = state == 2  # Qt::Checked
    end
end

class SettingsDlg < KDE::ConfigDialog
    def initialize(parent)
        super(parent, "Settings", Settings.instance)
        addPage(GeneralSettingsPage.new, i18n("General"), 'preferences-system')
        addPage(FolderSettingsPage.new, i18n("Folder"), 'folder')
    end
end