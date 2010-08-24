require 'ftools'
require 'fileutils'
require 'rubygems'
require 'rubygems/specification'
require 'sqlite3'

# additional libs
require 'korundum4'


#--------------------------------------------------------------------
#
#   Items
#
module PackageStatus
    # package status
    STATUS_INSTALLED = 'installed'
    STATUS_NOTINSTALLED = ''
    STATUS_LATEST = 'latest'
    STATUS_OLD = 'old'
end
include PackageStatus

#
# gemItem is created from command line gem command output
#  and used for inserting item to Qt::TableWidget.
#
class GemItem
    attr_accessor   :package, :version, :author, :rubyforge, :homepage, :platform
    attr_accessor   :summary, :status, :spec, :downloads
    alias   :name :package
    alias   :authors :author
    def initialize(pkg_and_ver, ver=nil)
        if ver.nil?
            pkg, ver = pkg_and_ver.split(/ /, 2)
            ver.tr!('()', '')
        else
            pkg = pkg_and_ver
        end
        @package = pkg
        @version = ver
        @author = ''
        @rubyforge = ''
        @homepage = ''
        @platform = ''
        @summary = ''
        @status = STATUS_NOTINSTALLED
        @spec = nil
        @downloads = 0
    end

    def latestVersion
        version.split(/,/, 2).first
    end

    def installedLocal?
        %x{ gem query -l -n '^#{@package}$' } =~ /#{@package}/
    end

    def self.parseHashGem(hGem)
        gem = self.new(hGem['name'], hGem['version'])
        gem.author = hGem['authors']
        gem.homepage = hGem['homepage_uri']
        gem.downloads = hGem['downloads']
        gem.summary = hGem['info']
        gem
    end

    def self.parseGemSpec(spec)
        gem = self.new(spec.name, spec.version)
        gem.author = spec.authors || ''
        gem.homepage = spec.homepage || ''
        gem.summary = spec.summary || ''
        gem.spec = spec
        gem
    end
end


#--------------------------------------------------------------------
#
#
class GemSpec
    def initialize
    end

    def self.getGemSpecInCacheWithUpdate(pkg)
        # write gem in local.
        %x{gem query -n '^#{pkg}$' -d -r}
        # read gem from local
        GemSpec.getGemSpecInCache(pkg)
    end

    def self.getGemSpecInCache(gem)
        pkg, ver = gem, '*'
        if gem.kind_of? GemItem
            pkg = gem.package
            ver = gem.latestVersion
        end
        spec = nil
        Dir.chdir(self.gemSpecDir)
        file = Dir[ pkg + '-' + ver + '.gemspec' ].select do |f|
                    f =~ /#{pkg}\-[\d\.]+/
                end.max
        if file && File.file?(file) then
            begin
                open(file) do |f|
                    spec = Marshal.load(f.read)
                end
            rescue NoMethodError, ArgumentError
                # rescue from some error gems.
            end
        end
        spec
    end


    def self.gemSpecDir
        @@gemSpecDir ||= self.getGemSpecDir
    end

    protected
    def self.getGemSpecDir
        dir = "#{ENV['HOME']}/.gem/specs/"
        begin
            Dir.chdir(dir)
            dirs = Dir['*']
            while (dir = dirs.shift) && !File.directory?(dir) do end
        end while dir

        Dir.pwd
    end
end

#--------------------------------------------------------------------
#
#
class GemsDb
    GEM_SPEC_DB = "#{ENV['HOME']}/.gem/gemspec.db"
    SPEC_PARAM = %w{ rubygems_version specification_version name version date
        summary required_ruby_version required_rubygems_version original_platform
        dependencies rubyforge_project email authors description homepage has_rdoc
        new_platform licenses installed_version }

    def initialize
        @updateTime = Time.at(0)
    end

    public
    def updateInstalledGemList( tableWidget )
        setupProgressDlg
        begin
            updateInstalledGemListTableFromCache( tableWidget )
        ensure
            @progressDlg.dispose
            @progressDlg = nil
        end
    end

    def initializeAvailableGemList( tableWidget )
        setupProgressDlg
        begin
            if checkCreateGemDb then
                updateGemDiffrence
                updateInstalledStatusOnDb
            end
            updateGemListFromDb( tableWidget )
        ensure
            @progressDlg.dispose
            @progressDlg = nil
        end
    end

    def updateAvailableGemList( tableWidget )
        setupProgressDlg
        begin
            checkCreateGemDb
            updateGemDiffrence
            updateInstalledStatusOnDb
            updateGemListFromDb( tableWidget )
        ensure
            @progressDlg.dispose
            @progressDlg = nil
        end
    end

    # getGemSpecInDb
    def getGem(pkg)
        db = SQLite3::Database.new(GEM_SPEC_DB)
        db.results_as_hash = true
        gem = nil
        r = db.get_first_row("select * from gems where name='#{pkg}'")
        makeGemfromDbRow(r)
    end
    alias :getGemInDb :getGem


    protected
    def makeGemfromDbRow(r)
        gem = GemItem.new(r['name'], r['version'].to_s)
        gem.summary   = r['summary'] or ''
        gem.author    = [ r['authors'] ] or ''
        gem.rubyforge = r['rubyforge_project']
        gem.homepage  = r['homepage']
        gem.platform  = r['original_platform']

        inVer= r['installed_version']
        gem.status = (inVer.nil? or inVer.empty?) ? STATUS_NOTINSTALLED : STATUS_INSTALLED
        gem
    end

    def updateInstalledGemListTableFromCache( tbl )
        gemList = makeInstalledGemListFromCache
        return unless gemList

        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false

        @progressDlg.labelText = "Makeing Gem Table"
        @progressDlg.setRange(0, gemList.length)
        @progressDlg.setValue(0)

        tbl.clearContents
        tbl.rowCount = gemList.length
        gemList.each_with_index do |g, r|
            g.status = STATUS_INSTALLED
            tbl.addPackage(r, g)
            @progressDlg.setValue(r)
        end

        tbl.sortingEnabled = sortFlag
    end


    #
    # @return : true if created.
    def checkCreateGemDb(forceCreate=false)
        if forceCreate then
            File.delete(GEM_SPEC_DB)
        end
        return false if File.exist?(GEM_SPEC_DB)

        FileUtils.mkdir_p(File.dirname(GEM_SPEC_DB))

        db = SQLite3::Database.new(GEM_SPEC_DB)
        db.execute( <<-EOF
create table gems (id INTEGER PRIMARY KEY,
    #{SPEC_PARAM.map{|s| s + ' TEXT'}.join(',')});
create unique index idx_gems_name on gems (name);
        EOF
        )
        true
    end


    #
    def updateGemDiffrence(forceUpdate=false)
        @progressDlg.labelText = "Load query for all."
        @progressDlg.setRange(0, 1)
        @progressDlg.setValue(0)
        gemsStr = %x{gem list -r}.split(/[\n\r]+/)

        db = SQLite3::Database.new(GEM_SPEC_DB)
        i = 0
        @progressDlg.labelText = "Differencial Update from Remote Data. #{gemsStr.size} gems"
        @progressDlg.setRange(0, gemsStr.size + 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)
        gemsStr.each do |line|
            _updateGemFromLine(db, line, forceUpdate, i)
            @progressDlg.setValue(i)
            i += 1
        end
    end


    def _updateGemFromLine(db, line, forceUpdate, count)
        if line =~ /^([\w\-]+)\s+\((.+)\)/
            pkg, vers= $1, $2.split(/,\s*/)
            latestVer = vers[0].split(/ /).first
            locVerStr = db.get_first_value("select version from gems where name='#{pkg}'")
            locVers = if locVerStr then locVerStr.split(/,\s*/) else [''] end
            locVer = locVers[0].gsub(/ .*$/,'')

            if forceUpdate or locVer.empty? or /#{locVer}/ !~ latestVer then
#                 puts "  %5d  updateing gem info pkg:#{pkg}, ver:#{locVer}, latest ver:#{latestVer}" % [ count ]
                spec = GemSpec.getGemSpecInCache(pkg)
                spec ||= forceUpdate ? GemSpec.getGemSpecInCacheWithUpdate(pkg) : nil
                return unless spec

                if spec.version.to_s != latestVer
                    puts "        Can't load latest (#{latestVer}) spec. loaded #{spec.version.to_s}, pkg :#{pkg}."
                end
                if locVer.empty?
                    db.execute("insert into gems (name) values ('#{pkg}')")
                end

                valStr = SPEC_PARAM.map do |param| "#{param}=" +
                    "#{spec.instance_variable_get('@'+param).to_s.sql_quote}"
                end.join(',')
                sqlCmd = "update gems set #{valStr} where name='#{pkg}'"
                db.execute( sqlCmd )
                puts "  updated gem info pkg:#{pkg}, ver:#{spec.version.to_s}, latest ver:#{vers[0]}"
            else
#                 puts "  %5d     skip   gem info pkg:#{pkg}, ver:#{locVer}, latest ver:#{latestVer}" % [ count ]
            end
        else
            puts "      not package info line '#{line}'"
        end
    end



    #
    #
    # @param tbl : Qt::TableWidget
    def updateGemListFromDb(tbl)
        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false
        tbl.clearContents

        db = SQLite3::Database.new(GEM_SPEC_DB)
        size = db.get_first_value( "select count(*) from gems" ) .to_i
        puts "total size :#{size}"
        tbl.rowCount = size

        @progressDlg.labelText = "Update Gem Table from DB"
        @progressDlg.setRange(0, size + 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)

        db.results_as_hash = true
        i = 0
        db.execute("select * from gems") do |r|
            gem = makeGemfromDbRow(r)
            tbl.addPackage(i, gem)
            i += 1
            @progressDlg.setValue(i)
        end
        tbl.sortingEnabled = sortFlag
    end


    def updateInstalledStatusOnDb
        gemList = makeInstalledGemListFromCache
        db = SQLite3::Database.new(GEM_SPEC_DB)
        db.execute("update gems set installed_version=NULL")    # clear all installed_version=nil
        gemList.each_with_index do |g, r|
            db.execute( "update gems set installed_version='#{g.version}' where name='#{g.name}'")
        end
    end


    # @return gemList
    def makeInstalledGemListFromCache
        gemList = nil
        catch (:canceled) do
            gemList = parseGemFile
        end
        gemList
    end

    GEM_MAX = 5500  # not need accuracy. just for progress bar
    # @return gemList
    def parseGemFile
        @progressDlg.labelText = "Parsing Gem Table"
        @progressDlg.setRange(0, GEM_MAX)
        @progressDlg.setValue(0)

        gemList = nil
        cnt = 0
        gemf = open('|gem query -d -l')
        begin
            summary = ''
            gem = nil
            while line = gemf.gets
                case line
                when /^(\w.*)/ then
                    if gem then
                        gem.summary = summary.strip
                        gemList ||= []
                        gemList << gem
                        cnt += 1
                        @progressDlg.setValue(cnt)
                    end
                    gem = GemItem.new($1)
                    summary = ''
                when /\s+Authors?:\s*(.*)\s*/i
                    gem.author = $1
                when /\s+Rubyforge:\s*(.*)\s*/i
                    gem.rubyforge = $1
                when /\s+Homepage:\s*(.*)\s*/i
                    gem.homepage = $1
                when /\s+Platform:\s*(.*)\s*/i
                    gem.platform = $1
                when /\s+Installed\s+at.*?:\s*(.*)\s*/i
                when /\s+\(.*?\):\s*(.*)\s*/i
                else
                    summary += line.strip + "\n"
                end
            end
            gem.summary = summary.strip
            gemList << gem
        ensure
            gemf.close
        end
        gemList
    end

    #
    def setupProgressDlg
        @progressDlg = Qt::ProgressDialog.new
        @progressDlg.labelText = "Processing Gem List"
        @progressDlg.setRange(0, GEM_MAX)
        @progressDlg.forceShow
        @progressDlg.setWindowModality(Qt::WindowModal)
    end
end
