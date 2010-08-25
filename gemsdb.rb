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

    def self.getInstalledGemList
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
end

