component 'ruby-2.5.1' do |pkg, settings, platform|
  pkg.version '2.5.1'
  pkg.md5sum "23867bc8c16c55e43b14dfe0614bcfa8"

  # Most ruby configuration happens in the base ruby config:
  instance_eval File.read('configs/components/_base-ruby.rb')
  # Configuration below should only be applicable to ruby 2.5.1

  ###########
  # RBCONFIGS
  ###########

  # These are a pretty smelly hack, and they run the risk of letting tests
  # based on the generated data (t  hat should otherwise fail) pass
  # erroneously. We should probably fix the "not shipping our compiler"
  # problem that led us to do this sooner rather than later.
  #   Ryan McKern, 26/09/2015
  #   Reference notes:
  #   - 6b089ed2: Provide a sane rbconfig for AIX
  #   - 8e88a51a: (RE-5401) Add rbconfig for solaris 11 sparc
  #   - 8f10f5f8: (RE-5400) Roll rbconfig for solaris 11 back to 2.1.6
  #   - 741d18b1: (RE-5400) Update ruby for solaris 11 i386
  #   - d09ed06f: (RE-5290) Update ruby to replace rbconfig for all solaris
  #   - bba35c1e: (RE-5290) Update ruby for a cross-compile on solaris 10
  rbconfig_info = {
    'powerpc-ibm-aix6.1.0.0' => {
      target_double: 'powerpc-aix6.1.0.0',
    },
    'powerpc-ibm-aix7.1.0.0' => {
      target_double: 'powerpc-aix7.1.0.0',
     },
    'aarch64-redhat-linux' => {
      target_double: 'aarch64-linux',
    },
    'ppc64le-redhat-linux' => {
      target_double: 'powerpc64le-linux',
    },
    'powerpc64le-suse-linux' => {
      target_double: 'powerpc64le-linux',
    },
    'powerpc64le-linux-gnu' => {
      target_double: 'powerpc64le-linux',
    },
    's390x-linux-gnu' => {
      target_double: 's390x-linux',
    },
    'i386-pc-solaris2.10' => {
      target_double: 'i386-solaris2.10',
    },
    'sparc-sun-solaris2.10' => {
      target_double: 'sparc-solaris2.10',
    },
    'i386-pc-solaris2.11' => {
      target_double: 'i386-solaris2.11',
    },
    'sparc-sun-solaris2.11' => {
      target_double: 'sparc-solaris2.11',
    },
    'arm-linux-gnueabihf' => {
      target_double: 'arm-linux-eabihf'
    },
    'arm-linux-gnueabi' => {
      target_double: 'arm-linux-eabi'
    },
    'x86_64-w64-mingw32' => {
      target_double: 'x64-mingw32',
    },
    'i686-w64-mingw32' => {
      target_double: 'i386-mingw32',
    },
  }

  #########
  # PATCHES
  #########

  base = 'resources/patches/ruby_251'
  pkg.apply_patch "#{base}/ostruct_remove_safe_nav_operator.patch"
  pkg.apply_patch "#{base}/Check-for-existance-of-O_CLOEXEC.patch"
  # This patch creates our server/client shared Gem path, used for all gems
  # that are dependencies of the shared Ruby code.
  pkg.apply_patch "#{base}/rubygems_add_puppet_vendor_dir.patch"

  if platform.is_cross_compiled?
    pkg.apply_patch "#{base}/uri_generic_remove_safe_nav_operator.patch"
  end

  if platform.is_aix?
    # TODO: Remove this patch once PA-1607 is resolved.
    pkg.apply_patch "#{base}/aix_configure.patch"
    pkg.apply_patch "#{base}/aix-fix-libpath-in-configure.patch"
    pkg.apply_patch "#{base}/aix_use_pl_build_tools_autoconf.patch"
    pkg.apply_patch "#{base}/aix_ruby_2.1_fix_make_test_failure.patch"
    pkg.apply_patch "#{base}/Remove-O_CLOEXEC-check-for-AIX-builds.patch"
  end

  if platform.is_windows?
    pkg.apply_patch "#{base}/windows_fixup_generated_batch_files.patch"
    pkg.apply_patch "#{base}/update_rbinstall_for_windows.patch"
    pkg.apply_patch "#{base}/PA-1124_add_nano_server_com_support-8feb9779182bd4285f3881029fe850dac188c1ac.patch"
    pkg.apply_patch "#{base}/windows_socket_compat_error.patch"
  end

  if platform.name =~ /^fedora-28/
    # Fedora 28 uses native GCC 8.0.1. When building ruby C extensions (in
    # ruby-augeas, for example) mkmf will fail when ruby 2.5.1's
    # CONFIG['warnflags'] are applied to a conftest with -Werror before
    # generating the Makefile. This patch removes a few flags from
    # CONFIG['warnflags'] that are no longer valid and ignores a few new
    # warnings generated by ruby.h.
    pkg.apply_patch "resources/patches/ruby_244/rbconfig_gcc8_quiet_warn_flags.patch",
                    destination: File.join(settings[:libdir], 'ruby', '2.4.0', 'x86_64-linux'),
                    after: 'install'
  end


  ####################
  # ENVIRONMENT, FLAGS
  ####################

  if platform.is_macos?
    pkg.environment 'optflags', settings[:cflags]
  elsif platform.is_windows?
    pkg.environment 'optflags', settings[:cflags] + ' -O3'
  else
    pkg.environment 'optflags', '-O2'
  end

  special_flags = " --prefix=#{settings[:ruby_dir]} --with-opt-dir=#{settings[:prefix]} "

  if platform.is_aix?
    # This normalizes the build string to something like AIX 7.1.0.0 rather
    # than AIX 7.1.0.2 or something
    special_flags += " --build=#{settings[:platform_triple]} "
  elsif platform.is_cross_compiled_linux?
    special_flags += " --with-baseruby=#{settings[:host_ruby]} "
  elsif platform.is_solaris? && platform.architecture == "sparc"
    special_flags += " --with-baseruby=#{settings[:host_ruby]} --enable-close-fds-by-recvmsg-with-peek "
  elsif platform.is_windows?
    special_flags = " CPPFLAGS='-DFD_SETSIZE=2048' debugflags=-g --prefix=#{settings[:ruby_dir]} --with-opt-dir=#{settings[:prefix]} "
  end

  ###########
  # CONFIGURE
  ###########

  # TODO: Remove this once PA-1607 is resolved.
  # TODO: Can we use native autoconf? The dependencies seemed a little too extensive
  pkg.configure { ["/opt/pl-build-tools/bin/autoconf"] } if platform.is_aix?

  # Here we set --enable-bundled-libyaml to ensure that the libyaml included in
  # ruby is used, even if the build system has a copy of libyaml available
  pkg.configure do
    [
      "bash configure \
        --enable-shared \
        --enable-bundled-libyaml \
        --disable-install-doc \
        --disable-install-rdoc \
        #{settings[:host]} \
        #{special_flags}"
     ]
  end

  #########
  # INSTALL
  #########

  rbconfig_changes = {
    "warnflags" => '"-Wall -Wextra -Wno-unused-parameter -Wno-parentheses -Wno-long-long -Wno-missing-field-initializers -Wno-tautological-compare -Wunused-variable -Wimplicit-int -Wpointer-arith -Wwrite-strings -Wdeclaration-after-statement -Wimplicit-function-declaration -Wdeprecated-declarations -Wno-packed-bitfield-compat -Wsuggest-attribute=noreturn -Wsuggest-attribute=format -Wimplicit-fallthrough=0 -Wno-attributes"'
  }
  rbconfig_location = ''

  pkg.add_source("file://resources/files/rbconfig-update.rb")

  target_dir = "$(#{settings[:ruby_bindir]}/ruby -e 'puts RbConfig::CONFIG[\"topdir\"]')"

  pkg.install do
    [
      "#{settings[:ruby_bindir]}/ruby ../rbconfig-update.rb \"#{rbconfig_changes.to_s.gsub('"', '\"').gsub('\\', '\\\\')}\"}",
      "cp #{target_dir}/rbconfig.rb #{settings[:datadir]}/doc/rbconfig-2.5.1-orig.rb",
      "cp new_rbconfig.rb #{target_dir}/rbconfig.rb",
    ]
  end

  # if platform.is_cross_compiled_linux? || platform.is_solaris? || platform.is_aix? || platform.is_windows?
  #   # Here we replace the rbconfig from our ruby compiled with our toolchain
  #   # with an rbconfig from a ruby of the same version compiled with the system
  #   # gcc. Without this, the rbconfig will be looking for a gcc that won't
  #   # exist on a user system and will also pass flags which may not work on
  #   # that system.
  #   # We also disable a safety check in the rbconfig to prevent it from being
  #   # loaded from a different ruby, because we're going to do that later to
  #   # install compiled gems.
  #   #
  #   # On AIX we build everything using our own GCC. This means that gem
  #   # installing a compiled gem would not work without us shipping that gcc.
  #   # This tells the ruby setup that it can use the default system gcc rather
  #   # than our own.
  #   target_dir = File.join(settings[:ruby_dir], 'lib', 'ruby', '2.5.0', rbconfig_info[settings[:platform_triple]][:target_double])
  #   sed = "sed"
  #   sed = "gsed" if platform.is_solaris?
  #   sed = "/opt/freeware/bin/sed" if platform.is_aix?
  #   pkg.install do
  #     [
  #       "#{sed} -i 's|raise|warn|g' #{target_dir}/rbconfig.rb",
  #       "mkdir -p #{settings[:datadir]}/doc",
  #       "cp #{target_dir}/rbconfig.rb #{settings[:datadir]}/doc/rbconfig-2.5.1-orig.rb",
  #       "cp ../rbconfig-251-#{settings[:platform_triple]}.rb #{target_dir}/rbconfig.rb",
  #     ]
  #   end
  # end
end
