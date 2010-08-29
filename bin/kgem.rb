#!/usr/bin/ruby
#
#    2010 by ruby.twiddler@gmail.com
#
#      Ruby Gem with KDE GUI
#

$KCODE = 'UTF8'
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_DIR = File::dirname(File.expand_path(File.dirname(__FILE__)))
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
require "gemsdb"
require "installedwin"
require "searchwin"
require "downloadedwin"
require "previewwin"
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
        # create actions
        quitAction = KDE::Action.new(KDE::Icon.new('exit'), '&Quit', self)
        quitAction.setShortcut(KDE::Shortcut.new('Ctrl+Q'))
        @actions.addAction(quitAction.text, quitAction)
        gemHelpAction = KDE::Action.new('Gem Command Line Help', self)
        @actions.addAction(gemHelpAction.text, gemHelpAction)

        # connect actions
        connect(quitAction, SIGNAL(:triggered), self, SLOT(:close))
        connect(gemHelpAction, SIGNAL(:triggered), self, SLOT(:gemCommandHelp))


        # settings menu
        configureShortCutAction = KDE::Action.new(KDE::Icon.new('configure-shortcuts'),
                                                  i18n('Configure Shortcuts'), self)
        configureAppAction = KDE::Action.new(KDE::Icon.new('configure'),
                                              i18n('Configure Kgem'), self)
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
        # connect actions
        connect(configureShortCutAction, SIGNAL(:triggered), self, SLOT(:configureShortCut))
        connect(configureAppAction, SIGNAL(:triggered), self, SLOT(:configureApp))


        # Help menu
        aboutDlg = KDE::AboutApplicationDialog.new($about)
        openAboutAction = KDE::Action.new(KDE::Icon.new('kgem'),
                                          i18n('About kgem'), self)
        connect(openAboutAction, SIGNAL(:triggered), aboutDlg, SLOT(:exec))

        #
        openDocUrlAction = KDE::Action.new(KDE::Icon.new('help-contents'),
                                           i18n('Open Document Wiki'), self)
        connect(openDocUrlAction, SIGNAL(:triggered), self, SLOT(:openDocUrl))

        #
        openReportIssueUrlAction = KDE::Action.new(
            KDE::Icon.new('tools-report-bug'), i18n('Report Bug'), self)
        connect(openReportIssueUrlAction, SIGNAL(:triggered), self,
                SLOT(:openReportIssueUrl))
        openSourceAction = KDE::Action.new(KDE::Icon.new('document-open-folder'),
                                           i18n('Open Source Folder'), self)
        connect(openSourceAction, SIGNAL(:triggered), self, SLOT(:openSource))

        helpMenu = KDE::Menu.new(i18n('&Help'), self)
        helpMenu.addAction(openDocUrlAction)
        helpMenu.addAction(openReportIssueUrlAction)
        helpMenu.addAction(openSourceAction)
        helpMenu.addSeparator
        helpMenu.addAction(openAboutAction)


        # file menu
        fileMenu = KDE::Menu.new(i18n('&File'), self)
        fileMenu.addAction(quitAction)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
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

        # tab windows
        @gemViewer = DockGemViewer.new(@detailWin, @fileListWin, @terminalWin, @previewWin)
        @installedGemWin = InstalledGemWin.new(self) do |w|
            w.gemViewer = @gemViewer
            @gemViewer.addInstallWatcher(w)
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
        cmd = KDE::MimeTypeTrader.self.query('inode/directory').first.exec[/\w+/]
        cmd += " " + APP_DIR
        fork do exec(cmd) end
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
        @settingsDlg.exec
    end

    slots :gemCommandHelp
    def gemCommandHelp
        @gemHelpdlg.show
    end
end


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
