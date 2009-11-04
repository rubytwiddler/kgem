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
        addChoiceItem(:browserForOpenDoc, %w{Konqueror Firefox Opera}, 0)
        addChoiceItem(:filerForOpenDir, %w{Dolphin Konqueror Krusader}, 0)
    end

    def self.filerCmdForOpenDir(url)
        case Settings.filerForOpenDir
        when 0  # dolphin
            %Q{dolphin '#{url}'}
        when 1  # konqueror
            %Q{kfmclient openProfile filemanagement '#{url}'}
        when 2  # krusader
            %Q{krusader --left '#{url}'}
        else
            %Q{dolphin '#{url}'}
        end
    end

    def self.browserCmdForOpenDoc(url)
        case Settings.browserForOpenDoc
        when 0  # konqueror
            %Q{kfmclient openURL '#{url}'}
        when 1  # firefox
            %Q{firefox '#{url}'}
        when 2  # opera
            %Q{opera -newpage -remote openURL '#{url}'}
        else
            %Q{kfmclient openURL '#{url}'}
        end
    end
end

class GeneralSettingsPage < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    def createWidget
        @browserCombo = Qt::ComboBox.new
        @browserCombo.addItems(%w{Konqueror Firefox Opera})
        @browserCombo.editable = false
        @filerCombo = Qt::ComboBox.new
        @filerCombo.addItems(%w{Dolphin Konqueror Krusader})
        @filerCombo.editable = false
        
        # objectNames
        @browserCombo.objectName = 'kcfg_browserForOpenDoc'
        @filerCombo.objectName = 'kcfg_filerForOpenDir'

        # layout
        flo = Qt::FormLayout.new do |l|
            l.addRow('RDoc/Link Browser', @browserCombo)
            l.addRow('File Directory Browser', @filerCombo)
        end
        lo = Qt::VBoxLayout.new do |l|
            l.addLayout(flo)
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