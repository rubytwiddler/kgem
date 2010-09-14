#!/usr/bin/ruby

require 'rbconfig'
require 'rubygems'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
    s.name = "kgem"
    s.version = "0.1.2"
    s.author = "ruby.twiddler"
    s.email = "ruby.twiddler at gmail.com"
    s.homepage = "http://github.com/rubytwiddler/kgem/wiki"
    s.summary = "KDE GUI for ruby gem."
    s.files = FileList["{bin,lib}/*"].to_a
    s.files += %w{ README MIT-LICENSE Rakefile pkg_resources/gemcmdwin-super.rb.pam }
    s.executables = [ 'kgem.rb' ]
    s.extensions = [ 'ext/Rakefile' ]
    s.require_path = "lib"
    s.requirements = %w{ korundum4 ktexteditor }
    s.add_runtime_dependency( 'json', '>= 1.4' )
    s.description = <<-EOF
Kgem is KDE GUI for ruby gem tool.
You can install/uninstall/update/download gems just clicking around,
search to find gem, browsing source files in gems without installing these gems.
You don't need to remember gem's command and options any more.
EOF
    s.has_rdoc = false
    s.extra_rdoc_files = ["README"]
end

require 'ftools'
APP_DIR = File.expand_path(File.dirname(__FILE__))
RES_DIR = File::join(APP_DIR, "pkg_resources")
def install_console_helper(console_helper_name, target_cmd_name)
    etc_dir = ENV['etc_dir'] || '/etc'

    console_helper_link = File.join(APP_DIR, 'bin', console_helper_name)
    cmd_path = File.join(APP_DIR, 'bin', target_cmd_name)
    pam_src_path = File.join( RES_DIR, console_helper_name + '.pam' )
    pam_dst_path = File.join(etc_dir, 'pam.d', console_helper_name)
    console_app_file = File.join(etc_dir, 'security', 'console.apps', console_helper_name)
    console_helper_target = %x{ which consolehelper }.strip!

    puts "cp #{pam_src_path} #{pam_dst_path}"
    puts "ln -s #{console_helper_target}  #{console_helper_link}"
    puts "write #{console_app_file}"

    File.cp(pam_src_path, pam_dst_path)
    if File.exist?(console_helper_link) then
        File.unlink(console_helper_link)
    end
    File.symlink(console_helper_target, console_helper_link)

    open(console_app_file, 'w') do |f|
        f.write(<<-EOF
USER=root
PROGRAM=#{cmd_path}
FALLBACK=false
SESSION=true
EOF
               )
    end
end



package = Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_tar = true
end

desc "install as gem package"
task :installgem => :gem do
    system("gem install -l pkg/" + package.gem_file )
end


desc "install pam"
task :installpam do
    install_console_helper('gemcmdwin-super.rb', 'gemcmdwin.rb')
end