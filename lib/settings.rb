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
        addBoolItem(:autoFetchFlag, false)
        addUrlItem(:autoFetchDir,
                   File.join(KDE::GlobalSettings.downloadPath, 'gem_cache'))
        addBoolItem(:autoUnpackFlag, false)
        addUrlItem(:autoUnpackDir, File.join(KDE::GlobalSettings.downloadPath, 'gem_src'))
    end
end


class GeneralSettingsPage < Qt::Widget

    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    def createWidget
        @installInSystemCheckBox = Qt::CheckBox.new(i18n("Install in System Directory. (Root access Required)"))
        @autoFetchCheckBox = Qt::CheckBox.new(i18n("auto download for fetch without asking location every time."))
        @downloadUrl = KDE::UrlRequester.new(KDE::Url.new())
        @downloadUrl.enabled = false
        @downloadUrl.mode = KDE::File::Directory | KDE::File::LocalOnly
        connect(@autoFetchCheckBox, SIGNAL('stateChanged(int)'),
                self, SLOT('autoFetchChanged(int)'))

        @autoUnpackCheckBox = Qt::CheckBox.new(i18n("auto Unpack without asking location every time."))
        @unpackUrl = KDE::UrlRequester.new(KDE::Url.new())
        @unpackUrl.enabled = false
        @unpackUrl.mode = KDE::File::Directory | KDE::File::LocalOnly
        connect(@autoUnpackCheckBox, SIGNAL('stateChanged(int)'),
                self, SLOT('autoUnpackChanged(int)'))

        # objectNames
        #  'kcfg_' + class Settings's instance name.
        @installInSystemCheckBox.objectName = 'kcfg_installInSystemDirFlag'
        @autoFetchCheckBox.objectName = 'kcfg_autoFetchFlag'
        @downloadUrl.objectName = 'kcfg_autoFetchDir'
        @autoUnpackCheckBox.objectName = 'kcfg_autoUnpackFlag'
        @unpackUrl.objectName = 'kcfg_autoUnpackDir'

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@installInSystemCheckBox)
            l.addWidget(@autoFetchCheckBox)
            l.addWidgets('   ', @downloadUrl)
            l.addWidget(@autoUnpackCheckBox)
            l.addWidgets('   ', @unpackUrl)
            l.addStretch
        end
        setLayout(lo)
    end

    slots   'autoFetchChanged(int)'
    def autoFetchChanged(state)
        @downloadUrl.enabled = state == Qt::Checked
    end

    slots   'autoUnpackChanged(int)'
    def autoUnpackChanged(state)
        @unpackUrl.enabled = state == Qt::Checked
    end
end

class SettingsDlg < KDE::ConfigDialog
    def initialize(parent)
        super(parent, "Settings", Settings.instance)
        addPage(GeneralSettingsPage.new, i18n("General"), 'preferences-system')
    end
end