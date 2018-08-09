# **********************
# rbconfig-update.rb
#
# This script is intended to write a new rbconfig file that is
# a copy of an existing rbconfig with updated entries.
#
# entries to update should be included in the static CHANGES hash
# inside this file.
#
# **********************

ORIGIN_RBCONF_LOCATION = ARGV[1] || RbConfig::CONFIG["topdir"]

# parse
#
# in order to provide a format in which you can pass key-value
# pairs in as a single string, the following uses <=> to delimit
# between keys and values and <--> to delimit between pairs.
#
# <--> and <=> were chosen simply because it should be unlikely
# that set of chars together would ever end up in any of the values
def parse(string)
  changes = {}
  string.split('<-->').each do |pair|
    key_value_pair = pair.split('<=>')
    changes[key_value_pair[0]] = key_value_pair[1]
  end
  changes
end

# replace_line
#
# The following replaces any configuration line in an rbconfig
# that matches any of the key value pairs listed in the CHANGES
# hash
def replace_line(changes, line, file)
  chagnges.each do |change_key, change_value|
    if line.strip.start_with?("CONFIG[\"#{change_key}\"]")
      old_value = line.split("=")[1].strip
      # This attempts to use sub instead of forcing an entirely
      # new string in an attempt to preserve any whitespace in the
      # line
      file.puts line.sub(old_value, change_value)
      return true
    end
  end
  false
end


# the following creates a new_rbconfig.rb file that is a copy of
# the rbcofig read from ORIGIN_RBCONF_LOCATION with replacements for
# anything listed in the CHANGES hash
new_rbconfig = File.open("new_rbconfig.rb", "w")
rbconfig_location = File.join(ORIGIN_RBCONF_LOCATION, "rbconfig.rb")
File.open(rbconfig_location, "r").readlines.each do |line|
  # changes = parse(ARGV[0])
  unless replace_line(instance_eval(ARGV[0]), line, new_rbconfig)
    new_rbconfig.puts line
  end
end
new_rbconfig.close
puts rbconfig_location
