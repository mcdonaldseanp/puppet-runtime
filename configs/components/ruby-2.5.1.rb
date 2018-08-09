component 'ruby-2.5.1' do |pkg, settings, platform|
  pkg.version '2.5.1'
  pkg.md5sum "23867bc8c16c55e43b14dfe0614bcfa8"

  # rbconfig-update is used to munge rbconfigs after the fact.
  pkg.add_source("file://resources/files/rbconfig-update.rb")

  # Most ruby configuration happens in the base ruby config:
  instance_eval File.read('configs/components/_base-ruby.rb')
  # Configuration below should only be applicable to ruby 2.5.1

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

  #   # Fedora 28 uses native GCC 8.0.1. When building ruby C extensions (in
  #   # ruby-augeas, for example) mkmf will fail when ruby 2.5.1's
  #   # CONFIG['warnflags'] are applied to a conftest with -Werror before
  #   # generating the Makefile. This patch removes a few flags from
  #   # CONFIG['warnflags'] that are no longer valid and ignores a few new
  #   # warnings generated by ruby.h.
  #   pkg.apply_patch "resources/patches/ruby_244/rbconfig_gcc8_quiet_warn_flags.patch",
  #                   destination: File.join(settings[:libdir], 'ruby', '2.4.0', 'x86_64-linux'),
  #                   after: 'install'
  # end


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

  target_doubles = {
    'powerpc-ibm-aix6.1.0.0' => 'powerpc-aix6.1.0.0',
    'aarch64-redhat-linux' => 'aarch64-linux',
    'ppc64le-redhat-linux' => 'powerpc64le-linux',
    'powerpc64le-suse-linux' => 'powerpc64le-linux',
    'powerpc64le-linux-gnu' => 'powerpc64le-linux',
    's390x-linux-gnu' => 's390x-linux',
    'i386-pc-solaris2.10' => 'i386-solaris2.10',
    'sparc-sun-solaris2.10' => 'sparc-solaris2.10',
    'i386-pc-solaris2.11' => 'i386-solaris2.11',
    'sparc-sun-solaris2.11' => 'sparc-solaris2.11',
    'arm-linux-gnueabihf' => 'arm-linux-eabihf',
    'arm-linux-gnueabi' => 'arm-linux-eabi',
    'x86_64-w64-mingw32' => 'x64-mingw32',
    'i686-w64-mingw32' => 'i386-mingw32'
  }
  if target_doubles.has_key?(settings[:platform_triple])
    rbconfig_topdir = File.join(settings[:ruby_dir], 'lib', 'ruby', ruby_version_y + '.0', target_doubles[settings[:platform_triple]])
  else
    rbconfig_topdir = "$$(#{settings[:ruby_bindir]}/ruby -e \"puts RbConfig::CONFIG[\\\"topdir\\\"]\")"
  end

  rbconfig_changes = {}
  if platform.name =~ /^fedora-28/
    rbconfig_changes["warnflags"] = '-Wall -Wextra -Wno-unused-parameter -Wno-parentheses -Wno-long-long -Wno-missing-field-initializers -Wno-tautological-compare -Wunused-variable -Wimplicit-int -Wpointer-arith -Wwrite-strings -Wdeclaration-after-statement -Wimplicit-function-declaration -Wdeprecated-declarations -Wno-packed-bitfield-compat -Wsuggest-attribute=noreturn -Wsuggest-attribute=format -Wimplicit-fallthrough=0 -Wno-attributes'
  elsif platform.is_aix?
    rbconfig_changes["CC"] = "gcc"
  end


  pkg.install do
    [
      "#{settings[:ruby_bindir]}/ruby ../rbconfig-update.rb \"#{rbconfig_changes.to_s.gsub('"', '\"')}\" #{rbconfig_topdir}",
      "cp #{rbconfig_topdir}/rbconfig.rb #{settings[:datadir]}/doc/rbconfig-2.5.1-orig.rb",
      "cp new_rbconfig.rb #{rbconfig_topdir}/rbconfig.rb",
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
