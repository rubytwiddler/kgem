#
#   settings.
#
require 'singleton'
require 'kio'
#
require "mylibs"


class Settings < SettingsBase
    def initialize
        super()

        setCurrentGroup("Preferences")

        # meta programed version.
        addBoolItem(:installInSystemDirFlag, true)
        addBoolItem(:autoFetchDownloadFlag, true)
        addUrlItem(:autoFetchDownloadDir, KDE::GlobalSettings.downloadPath)
    end
end


class GeneralSettingsPage < Qt::Widget
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
        #  'kcfg_' + class Settings's instance name.
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
    end
end