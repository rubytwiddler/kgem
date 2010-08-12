require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_DIR = File.expand_path(File.dirname(__FILE__))
APP_VERSION = "0.1"

require '../gemsdb.rb'
require '../mylibs.rb'
require 'test/unit'

class MyGemsDbTest < Test::Unit::TestCase
    class TestGemsDb < GemsDb
        def test_updateGemDiffrence
            setupProgressDlg
            begin
                updateGemDiffrence
            rescue
                @progressDlg.dispose
                @progressDlg = nil
            end
        end

        def clean_create
            setupProgressDlg
            begin
                checkCreateGemDb(true)
                updateGemDiffrence(true)
            rescue
            @progressDlg.dispose
            @progressDlg = nil
            end
        end
            
        def test_parameters
            pkg = "rake"
            spec = GemSpec.getGemSpecInCacheWithUpdate(pkg)
            specParams = spec.instance_variables.map{|s| s.gsub(/^@/, '')}
#             puts " param : #{specParams.sort.join(',')}"
            SPEC_PARAM - specParams
        end

        def getGemInCache(pkg)
            spec = GemSpec.getGemSpecInCache(pkg)
            gem = GemItem.new(spec.name, spec.version.to_s)
            gem.summary = spec.summary
            gem.author = spec.authors
            gem.rubyforge = spec.rubyforge_project
            gem.homepage = spec.homepage
            gem.platform = spec.original_platform
            gem
        end

        def getGemSpecInCache(pkg)
            GemSpec.getGemSpecInCache(pkg)
        end
    end

    def setup
        about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION)
        KDE::CmdLineArgs.init(ARGV, about)

        $app = KDE::Application.new
        args = KDE::CmdLineArgs.parsedArgs()

        @gemsdb = TestGemsDb.new
    end

    def teardown
    end

    def test_gemsdb_create
#         @gemsdb.clean_create
    end

    def test_gemsdb_gemspec0
#         assert_equal(@gemsdb.getGemSpecInCache('chrome_watir').version.to_s, "1.5.0")
        assert_equal(@gemsdb.getGemSpecInCache('colour').version.to_s, "0.4")
        assert_equal(@gemsdb.getGemSpecInCache('shared').version.to_s, "1.1.0")
        assert_equal(@gemsdb.getGemSpecInCache('zyps').version.to_s, "0.7.6")
        
        assert_equal(@gemsdb.getGemInCache('googlecharts'), @gemsdb.getGemInDb('googlecharts'))
        assert_equal(@gemsdb.getGemInCache('shared'), @gemsdb.getGemInDb('shared'))
        assert_equal(@gemsdb.test_parameters, ["installed_version"])
    end
    
    def test_gemsdb_gemspec1
        comp_gem('googlecharts')
        comp_gem('shared')
    end





    
    def comp_gem(name)
        cachegem = @gemsdb.getGemInCache(name)
        dbgem = @gemsdb.getGemInDb(name)
        %w{ name version summary author rubyforge homepage platform } .each do |param|
            cacheVal = cachegem.instance_variable_get('@' + param)
            dbVal = dbgem.instance_variable_get('@' + param)
#             puts " #{name}:#{cacheVal}, #{dbVal}"
            assert_equal(cacheVal, dbVal )
        end
    end


end
        
