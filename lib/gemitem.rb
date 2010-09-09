require 'ftools'
require 'fileutils'
require 'rubygems'
require 'rubygems/specification'

# additional libs
require 'korundum4'


#--------------------------------------------------------------------
#
# gemItem is created from gem command output in command line
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
            ver.strip!
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
        @spec = nil
        @downloads = 0
    end

    attr_reader :filePath
    def addLocalPath(filePath)
        @filePath = filePath
    end

    def nowVersion
        version.split(/,/, 2).first
    end

    # available versions at remote server.
    def availableVersions
        return @versions if instance_variable_defined? :@versions

        res = %x{ gem list #{name} -a -r }
        res =~ /#{Regexp.escape(name)}\s+\(([^\)]+)\)/
        res = $1.split(/,\s+/).map { |v| v.split(/ /).first.strip }
        if res then
            @versions = res
        else
            @versions = nil
        end
    end

    def installedLocal?
        res = %x{ gem query -l -d -n '^#{@package}$' }
        res =~ /#{@package}/ and res =~ %r? /home/?
    end

    def self.parseHashGem(hGem)
        gem = self.new(hGem['name'], hGem['version'].to_s)
        gem.author = hGem['authors']
        gem.homepage = hGem['homepage_uri']
        gem.downloads = hGem['downloads']
        gem.summary = hGem['info']
        gem
    end

    def self.parseGemSpec(spec)
        gem = self.new(spec.name, spec.version.to_s)
        gem.author = spec.authors || ''
        gem.homepage = spec.homepage || ''
        gem.summary = spec.summary || ''
        gem.spec = spec
        gem
    end

end



module InstalledGemList
    extend self

    def get
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
                    end
                    gem = GemItem.new(line)
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

        oldeGems = gemList.inject([]) do |s, g|
            vers = g.version.split(/,/).map { |v| v.strip }
            if vers.size > 1 then
                g.version = vers.shift
                vers.each do |v|
                    dupg = g.dup
                    dupg.version = v
                    s << dupg
                end
            end
            s
        end
        @gemList = gemList + oldeGems
    end

    def getCached
        @gemList ||= get
    end

    def checkVersionGemInstalled(versionedName)
        vname = versionedName.gsub(/\.gem$/, '')
        gem = getCached.find do |gem|
            gem.name + '-' + gem.version == vname
        end
        not gem.nil?
    end
end