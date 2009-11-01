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

class GemItem
    attr_accessor   :package, :version, :author, :rubyforge, :homepage, :platform
    attr_accessor   :summary, :status, :spec
    alias   :name :package
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
    end

    def latestVersion
        version.split(/,/, 2)[0]
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
        %x{gem query -n '^#{pkg}' -d -r}
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
            updateGemListTable(:makeGemListFromLocal, tableWidget, STATUS_INSTALLED)
        ensure
            @progressDlg.dispose
            @progressDlg = nil
        end
    end

    def updateAvailableGemList( tableWidget )
        setupProgressDlg
        begin
#             updateGemListTable(:makeGemListFromRemote, tableWidget, STATUS_NOTINSTALLED)
#             updateGemListFromCache( tableWidget )
#             createGemDbFromCache
            checkCreateGemDb
            updateGemDiffrence
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
        gem = GemItem.new(r['name'], r['version'].to_s)
        gem.summary   = r['summary']
        gem.author    = [ r['authors'] ]
        gem.rubyforge = r['rubyforge_project']
        gem.homepage  = r['homepage']
        gem.platform  = r['original_platform']
        gem
    end
    alias :getGemInDb :getGem

    
    protected
    def openLocalGemList
        open('|gem query -d -l')
    end
    
    def updateGemListTable(makeGemListMethod, tbl, status)
        gemList = self.method(makeGemListMethod).call
        return unless gemList

        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false

        @progressDlg.labelText = "Makeing Gem Table"
        @progressDlg.setRange(0, gemList.length)
        @progressDlg.setValue(0)

        tbl.clearContents
        tbl.rowCount = gemList.length
        gemList.each_with_index do |g, r|
            g.status = status
            tbl.addPackage(r, g)
            @progressDlg.setValue(r)
        end

        tbl.sortingEnabled = sortFlag
    end

    def updateGemListFromCache( tbl )
        status = STATUS_NOTINSTALLED

        sortFlag = tbl.sortingEnabled
        tbl.sortingEnabled = false

        Dir.chdir(getGemSpecDir)
        files = Dir['*.gemspec']
        tbl.clearContents
        tbl.rowCount = files.length
        row = 0
        files.each do |f|
            if f =~ /^(.+)-([\d\.]+)\.gemspec/ then
                gem = GemItem.new($1, $2)
#                 specStr = %x{gem specification #{gem.package} -b --marshal}
                specStr = open(gem.package).read
                spec = Marshal.load(specStr)
                gem.summary = spec.summary
                gem.author = spec.authors
                gem.rubyforge = spec.rubyforge_project
                gem.homepage = spec.homepage
                gem.platform = spec.original_platform
                gem.status = status
                tbl.addPackage(row, gem)
                row += 1
            end
        end

        tbl.sortingEnabled = sortFlag
    end

    # temporally 
    def createGemDbFromCache
        FileUtils.mkdir_p(File.dirname(GEM_SPEC_DB))
        db = SQLite3::Database.new(GEM_SPEC_DB)

        db.execute( "drop table gems" )
        
        db.execute( <<-EOF
create table gems (id INTEGER PRIMARY KEY,
    #{SPEC_PARAM.map{|s| s + ' TEXT'}.join(',')})
        EOF
        )

        status = STATUS_NOTINSTALLED
        gemList = makeGemListFromRemote
        return unless gemList

        @progressDlg.labelText = "Inserting Gem in DB"
        @progressDlg.setRange(0, gemList.length)
        @progressDlg.setValue(0)

        gemList.each_with_index do |g, r|
            g.status = status
            name = g.package.sql_escape
            summary = g.summary.sql_escape
            version = g.version
            puts "#{name} : summary #{summary}: ver #{version}"
            STDOUT.flush
            db.execute(<<-EOF
insert into gems (name, summary, version)
    values ('#{g.package.sql_escape}', '#{g.summary.sql_escape}', '#{g.version}')
            EOF
            )
            @progressDlg.setValue(r)
        end
    end

    
    #
    #
    def checkCreateGemDb(forceCreate=false)
        if forceCreate then
            File.delete(GEM_SPEC_DB)
        end
        return if File.exist?(GEM_SPEC_DB)
        
        FileUtils.mkdir_p(File.dirname(GEM_SPEC_DB))
        
        db = SQLite3::Database.new(GEM_SPEC_DB)
        db.execute( <<-EOF
create table gems (id INTEGER PRIMARY KEY,
    #{SPEC_PARAM.map{|s| s + ' TEXT'}.join(',')});
create unique index idx_gems_name on gems (name);
        EOF
        )
    end


    #
    def updateGemDiffrence(forceUpdate=false)
        db = SQLite3::Database.new(GEM_SPEC_DB)
        
        gemsStr = %x{gem query -r -a}.split(/(\n|\r)/)

        @progressDlg.labelText = "Differencial Update from Remote Data"
        @progressDlg.setRange(0, gemsStr.size + 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)

        i = 0
        gemsStr.each do |line|
            _updateGemFromLine(db, line, forceUpdate)
            @progressDlg.setValue(i)
            i += 1
        end
    end

    
    def _updateGemFromLine(db, line, forceUpdate)
        if line =~ /^([\w\-]+)\s+\((.+)\)/
            pkg, vers= $1, $2.split(/,\s*/)
            locVerStr = db.get_first_value("select version from gems where name='#{pkg}'")
            locVers = if locVerStr then locVerStr.split(/,\s*/) else [''] end
            if forceUpdate or /#{locVers[0]}/ !~ vers[0] then
                puts "updateing gem info pkg:#{pkg}, ver:#{locVers[0]}, latest ver:#{vers[0]}"
                spec = forceUpdate ? GemSpec.getGemSpecInCache(pkg) : nil
                spec ||= GemSpec.getGemSpecInCacheWithUpdate(pkg)
                return unless spec

                puts "Can't load latest (#{vers[0]}) spec. loaded #{spec.version.to_s}" if spec.version.to_s != vers[0]
                if locVers[0].empty?
                    db.execute("insert into gems (name) values ('#{pkg}')")
                end

                valStr = SPEC_PARAM.map do |param| "#{param}=" +
                    "#{spec.instance_variable_get('@'+param).to_s.sql_quote}"
                end.join(',')
                sqlCmd = "update gems set #{valStr} where name='#{pkg}'"
                db.execute( sqlCmd )
                puts "  updated gem info pkg:#{pkg}, ver:#{spec.version.to_s}, latest ver:#{vers[0]}"
            end
        end
    end

    #
    #
    #
    def updateGemListFromDb(tbl)
        status = STATUS_NOTINSTALLED

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
            name = r['name']
            gem = GemItem.new(r['name'], r['version'])
#             print "#{gem.package}, "
#             STDOUT.flush

            gem.summary = r['summary']
            gem.author = r['authors']
            gem.rubyforge = r['rubyforge_project']
            gem.homepage = r['homepage']
            gem.platform = r['original_platform']
            gem.status = status
            tbl.addPackage(i, gem)
            i += 1
            @progressDlg.setValue(i)
        end
        tbl.sortingEnabled = sortFlag
    end
    

    def setupProgressDlg
        @progressDlg = Qt::ProgressDialog.new
        @progressDlg.labelText = "Processing Gem List"
        @progressDlg.setRange(0, GemReadRangeSize)
        @progressDlg.forceShow
        @progressDlg.setWindowModality(Qt::WindowModal)
    end


    def makeGemListFromLocal
        makeGemList(:openLocalGemList)
    end
    
    def makeGemListFromRemote
        makeGemList(:openRemoteGemList)
    end
    
    # @return gemList
    def makeGemList(openMethod)
        gemList = nil
        catch (:canceled) do
            gemf = self.method(openMethod).call
            gemList = parseGemFile(gemf)
        end
        gemList
    end

    GemReadRange = 'a'..'z'
    GemReadRangeSize = GemReadRange.count
    GEM_MAX = 5331  # not need accuracy. just for progress bar
    # @param gemf : gem data IO
    # @return gemList
    def parseGemFile(gemf)
        gemList = nil
        cnt = 0
        @progressDlg.labelText = "Parsing Gem Table"
        @progressDlg.setRange(0, GEM_MAX+ 1)  # +1 for avoid closeing progressDlg
        @progressDlg.setValue(0)

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


    # open cache data in tmp dir
    def openRemoteGemList
        tmpdir = Qt::Dir.tempPath + "/#{APP_NAME}/cache"
        FileUtils.mkdir_p(tmpdir)
        tmpName = 'gemdata.raw'
        tmpPath = tmpdir + '/' + tmpName
        unless File.exist?(tmpPath) then
            @progressDlg.labelText = "Loading Gem List from Net."
            @progressDlg.setRange(0, GemReadRangeSize + 1)  # +1 for avoid closeing progressDlg
            @progressDlg.setValue(0)
            open(tmpPath, 'w') do |f|
                cnt = 0
                GemReadRange.each do |c|
                    throw :canceled if @progressDlg.wasCanceled
                    @progressDlg.setValue(cnt)
                    cnt += 1
                    f.write(%x{gem query -n '^#{c}' -d -r})
               end
            end
        end

        open(tmpPath)
    end
end
