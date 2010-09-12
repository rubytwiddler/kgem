#!/usr/bin/ruby
#
#    2010 by ruby.twiddler@gmail.com
#
#      Ruby Gem with KDE GUI
#

$KCODE = 'UTF8'
require 'ftools'

APP_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
APP_NAME = File.basename(APP_FILE).sub(/\.rb/, '')
APP_DIR = File::dirname(File.expand_path(File.dirname(APP_FILE)))
LIB_DIR = File::join(APP_DIR, "lib")
APP_VERSION = "0.1.0"


# standard libs
require 'fileutils'
require 'rubygems'
require 'rubygems/specification'
require 'json'
require 'uri'
require 'net/http'
require 'shellwords'

# additional libs
require 'korundum4'
require 'ktexteditor'

#
# my libraries and programs
#
$:.unshift(LIB_DIR)
require "mylibs"
require "settings"
require "gemitem"
require "installedwin"
require "searchwin"
require "downloadedwin"
require "previewwin"
require "gemcmddlgs"
require "gemviews"
require "gemhelpdlg"

#--------------------------------------------------------------------
#--------------------------------------------------------------------
#
#
#
class MainWindow < KDE::MainWindow
    def initialize
        super(nil)
        setCaption(APP_NAME)

        @actions = KDE::ActionCollection.new(self)
        createWidgets
        createMenu
        createDlg
        @actions.readSettings
        setAutoSaveSettings
    end


    def createMenu
        # file menu
        quitAction = @actions.addNew('Quit', self, \
            { :icon => 'exit', :shortCut => 'Ctrl+Q', :triggered => :close })
        fileMenu = KDE::Menu.new(i18n('&File'), self)
        fileMenu.addAction(quitAction)

        # tool menu
        updateSystemAction = @actions.addNew('Update Gem System', self, \
            { :icon => 'checkbox', :shortCut => 'F4', \
              :triggered => [@gemViewer, :updateSystem ] })
        checkStaleAction = @actions.addNew('Check Stale', self, \
            { :icon => 'checkbox', :shortCut => 'F7', \
              :triggered => [@gemViewer, :checkStale] })
        checkAlienAction = @actions.addNew('Check Alien', self, \
            { :icon => 'checkbox', :shortCut => 'F8', \
              :triggered => [@gemViewer, :checkAlien] })
        cleanUpAction = @actions.addNew('Clean Up', self, \
            { :icon => 'edit-clear', :shortCut => 'F9', \
              :triggered => [@gemViewer, :cleanUp] })
        updateAllAction = @actions.addNew('Update All', self, \
            { :icon => 'checkbox', :shortCut => 'F10', \
              :triggered => [@gemViewer, :updateAll] })
        pristineAllAction = @actions.addNew('Pristine All', self, \
            { :icon => 'checkbox', :shortCut => 'F11', \
              :triggered => [@gemViewer, :pristineAll] })

        toolsMenu = KDE::Menu.new(i18n('&Tools'), self)
        toolsMenu.addAction(updateSystemAction)
        toolsMenu.addSeparator
        toolsMenu.addAction(checkStaleAction)
        toolsMenu.addAction(checkAlienAction)
        toolsMenu.addSeparator
        toolsMenu.addAction(cleanUpAction)
        toolsMenu.addAction(updateAllAction)
        toolsMenu.addAction(pristineAllAction)


        # settings menu
        configureShortCutAction = @actions.addNew(i18n('Configure Shortcuts'), self, \
            { :icon => 'configure-shortcuts', :shortCut => 'F3', :triggered => :configureShortCut })
        configureAppAction = @actions.addNew(i18n('Configure Kgem'), self, \
            { :icon => 'configure', :shortCut => 'F2', :triggered => :configureApp })
        detailWinAction = @detailWin.toggleViewAction
        fileListWinAction = @fileListWin.toggleViewAction
        termilanWinAction = @terminalWin.toggleViewAction

        settingsMenu = KDE::Menu.new(i18n('&Settings'), self)
        settingsMenu.addAction(detailWinAction)
        settingsMenu.addAction(fileListWinAction)
        settingsMenu.addAction(termilanWinAction)
        settingsMenu.addSeparator
        settingsMenu.addAction(configureShortCutAction)
        settingsMenu.addAction(configureAppAction)


        # Help menu
        aboutDlg = KDE::AboutApplicationDialog.new($about)
        gemHelpAction = @actions.addNew(i18n('Gem Command Line Help'), self, \
            { :icon => 'help-about', :shortCut => 'F1', :triggered => :gemCommandHelp })
        openAboutAction = @actions.addNew(i18n('About kgem'), self, \
            { :icon => 'help-about', :triggered => [ aboutDlg, :exec ] })
        openDocUrlAction = @actions.addNew(i18n('Open Document Wiki'), self, \
            { :icon => 'help-contents', :triggered => :openDocUrl })
        openReportIssueUrlAction = @actions.addNew(i18n('Report Bug'), self, \
            { :icon => 'tools-report-bug', :triggered => :openReportIssueUrl })
        openSourceAction = @actions.addNew(i18n('Open Source Folder'), self, \
            { :icon => 'document-open-folder', :triggered => :openSource })
        openRdocAction = @actions.addNew(i18n('Open Rdoc'), self, \
            { :icon => 'document-open-folder', :triggered => :openRdoc })
        envAction = @actions.addNew(i18n('Check Gem Environment'), self, \
            { :triggered => :checkEnv })

        helpMenu = KDE::Menu.new(i18n('&Help'), self)
        helpMenu.addAction(openDocUrlAction)
        helpMenu.addAction(openReportIssueUrlAction)
        helpMenu.addAction(openSourceAction)
        helpMenu.addAction(envAction)
        helpMenu.addAction(gemHelpAction)
        helpMenu.addSeparator
        helpMenu.addAction(openAboutAction)


        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( toolsMenu )
        menu.addMenu( settingsMenu )
        menu.addMenu( helpMenu )
        setMenuBar(menu)
    end



    def createWidgets
        # dockable window
        @detailWin = DetailWin.new(self)
        addDockWidget(Qt::BottomDockWidgetArea, @detailWin)
        @fileListWin = FileListWin.new(self)
        tabifyDockWidget(@detailWin, @fileListWin)
        @terminalWin = TerminalWin.new(self)
        tabifyDockWidget(@fileListWin, @terminalWin)

        @previewWin = PreviewWin.new
        @gemEnvDlg = GemEnvDlg.new

        # tab windows
        @gemViewer = DockGemViewer.new(self, @detailWin, @fileListWin, @terminalWin, @previewWin)
        @installedGemWin = InstalledGemWin.new(self) do |w|
            w.gemViewer = @gemViewer
            @gemViewer.addInstallWatcher(w)
            @gemViewer.setInstallWin(w)
        end
        @searchWin = SearchWin.new(self) do |w|
            w.gemViewer = @gemViewer
        end
        @downloadedWin = DownloadedWin.new(self) do |w|
            w.gemViewer = @gemViewer
            @gemViewer.addInstallWatcher(w)
            @gemViewer.addDownloadWatcher(w)
        end


        # layout
        @mainTab = KDE::TabWidget.new
        @mainTab.tabBar.movable = true
        @mainTab.addTab(@searchWin, i18n("Search"))
        @mainTab.addTab(@installedGemWin, i18n('Installed Gems'))
        @mainTab.addTab(@downloadedWin, i18n("Downloaded Gems"))

        setCentralWidget(@mainTab)
    end

    def createDlg
        @settingsDlg = SettingsDlg.new(self)
        @gemHelpdlg = GemHelpDlg.new(self)
    end



    #------------------------------------
    #
    # virtual slot
    def closeEvent(ev)
        @actions.writeSettings
        @searchWin.writeSettings
        @installedGemWin.writeSettings
        @downloadedWin.writeSettings
        @gemHelpdlg.closeEvent(ev)
        @previewWin.writeSettings
        super(ev)
        $config.sync    # important!  qtruby can't invoke destructor properly.
    end


    #------------------------------------
    #
    #
    slots :openDocUrl
    def openDocUrl
        openUrlDocument('http://github.com/rubytwiddler/kgem/wiki')
    end

    slots :openReportIssueUrl
    def openReportIssueUrl
        openUrlDocument('http://github.com/rubytwiddler/kgem/issues')
    end

    slots  :openSource
    def openSource
        openDirectory(APP_DIR)
    end

    slots :openRdoc
    def openRdoc

    end

    slots :checkEnv
    def checkEnv
        @gemEnvDlg.displayEnv
    end

    def openUrlDocument(url)
        cmd= Mime::services('.html').first.exec
        cmd.gsub!(/%\w+/, url)
        fork do exec(cmd) end
    end

    slots :configureShortCut
    def configureShortCut
        KDE::ShortcutsDialog.configure(@actions)
    end

    slots :configureApp
    def configureApp
        Settings.updateWidgets(@settingsDlg)
        @settingsDlg.exec
    end

    slots :gemCommandHelp
    def gemCommandHelp
        @gemHelpdlg.show
    end
end


#------------------------------------------------------------
#
#
class GemEnvDlg < Qt::Dialog
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    def createWidget
        @textEdit = Qt::TextEdit.new
        @textEdit.readOnly = true
        @closeBtn = KDE::PushButton.new(KDE::Icon.new('dialog-close'), i18n('Close'))
        connect(@closeBtn, SIGNAL(:clicked), self, SLOT(:accept))

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@textEdit)
            l.addWidgets(nil, @closeBtn)
        end
        setLayout(lo)
    end

    def writeEnvData
        @textEdit.setPlainText( %x{ gem env } )
        resize(460,440)
        @wroteEnv = true
    end

    def displayEnv
        writeEnvData unless @wroteEnv
        exec
    end
end


#------------------------------------------------------------------------------
#
#    main start
#

$about = KDE::AboutData.new(APP_NAME, nil, KDE::ki18n(APP_NAME), APP_VERSION,
                            KDE::ki18n('Gem Utitlity with KDE GUI.')
                           )
$about.addLicenseTextFile(APP_DIR + '/MIT-LICENSE')
KDE::CmdLineArgs.init(ARGV, $about)

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
