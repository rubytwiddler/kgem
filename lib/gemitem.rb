require 'fileutils'
require 'rubygems'
require 'rubygems/specification'
require 'yaml'

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

    # return versoin knowing newest, not latest.
    def nowVersion
        version.split(/,/, 2).first
    end

    # available versions at remote server.
    def availableVersions
        return @versions if instance_variable_defined? :@versions

        res = GemCmd.exec("list #{name} -a -r ")
        res =~ /#{Regexp.escape(name)}\s+\(([^\)]+)\)/
        res = $1.split(/,\s+/).map { |v| v.split(/ /).first.strip }
        if res then
            @versions = res
        else
            @versions = nil
        end
    end

    def installedLocal?
        res = GemCmd.exec("query -l -d -n '^#{@package}$'")
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

    def self.getGemfromPath(path)
        res = GemCmd.exec("specification #{path} -b  --marshal")
        return nil if res.empty?
        spec = Marshal.load(res)
        GemItem::parseGemSpec(spec)
    end

    def self.getGemfromCache(filePath)
        res = %x{ tar xf #{filePath.shellescape} metadata.gz -O | gunzip -c }
        return nil if res.empty?
        spec = YAML::load(res)
        GemItem::parseGemSpec(spec)
    end
end

require 'rubygems'
require 'rubygems/gem_runner'
require 'rubygems/exceptions'
require 'stringio'

module GemCmd
    require 'rbconfig'
    extend self

    def _getRubyexe
        File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['RUBY_INSTALL_NAME'])
    end

    def rubyexe
        @rubyexe ||= _getRubyexe
    end

    REQUIRED_VERSION = Gem::Requirement.new ">= 1.8.6"

    def exec(*args)
        execf(*args).string
    end

    def execf(*args)
        if args.size == 1 && args[0].kind_of?(String) then
            args = args[0].strip.split(/\s+/)
        end
        unless REQUIRED_VERSION.satisfied_by? Gem.ruby_version then
            # abort "Expected Ruby Version #{required_version}, is #{Gem.ruby_version}"
            return "Expected Ruby Version #{required_version}, is #{Gem.ruby_version}"
        end

        @outio = StringIO.new
        Gem::DefaultUserInteraction.ui = Gem::StreamUI.new($stdin, @outio, @outio)

        begin
            Gem::GemRunner.new.run args
        rescue Gem::SystemExitException => e
    #        exit e.exit_code
            @outio.puts e.inspect
        end
        @outio
    end

end

module InstalledGemList
    extend self

    def get
        gemList = nil
        cnt = 0
        lines = GemCmd.exec("query -d -l").split(/\n/)
        begin
            summary = ''
            gem = nil
            while line = lines.shift
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
#             gemf.close
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

    def checkVersionedGemInstalled(versionedName)
        vname = versionedName.gsub(/\.gem$/, '')
        gem = getCached.find do |gem|
            gem.name + '-' + gem.version == vname
        end
        not gem.nil?
    end
end