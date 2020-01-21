#!/opt/td-agent/embedded/bin/ruby

require 'json'
require 'logger'

log = Logger.new(STDOUT)
log.level = Logger::INFO

file_map_cfg_file = "/etc/td-agent/log-file-map.conf"
old_file_map_cfg_file = "/etc/zebrium/log-file-map.cfg"
user_fluentd_cfg_file = "/etc/td-agent/conf.d/user.conf"

if File.exist?(file_map_cfg_file) and File.exist?(old_file_map_cfg_file)
    log.error("Both " + file_map_cfg_file + " and " + old_file_map_cfg_file + " exist")
    exit(1)
end

if not File.exist?(file_map_cfg_file)
    log.info(file_map_cfg_file + " does not exist, try " + old_file_map_cfg_file)
    if not File.exist?(old_file_map_cfg_file)
      exit(0)
    end
    log.warn(old_file_map_cfg_file + " is obsoleted, please move it to " + file_map_cfg_file)
    file_map_cfg_file = old_file_map_cfg_file
end

log.info(file_map_cfg_file + " exist")
file = File.read(file_map_cfg_file)
file_mappings = JSON.parse(file)

file_paths = ''
exclude_paths = ''
file_mappings['mappings'].each { |item|
    if item.key?('file') and item['file'].length > 0
        fpath = item['file']
        if file_paths.length == 0
            file_paths = fpath
        else
            file_paths = file_paths + "," + fpath
        end
    end
    if item.key?('exclude') and item['exclude'].length > 0
      exclude = item['exclude']
      exclude.split(',').each {|str|
        path = str.strip! || str
        if exclude_paths.length == 0
          exclude_paths = '"' + path + '"'
        else
          exclude_paths = exclude_paths + ',' + '"' + path + '"'
        end
      }
    end
}

if file_paths.empty?
    # File path must not be empty, Fluentd will fail if it is empty
    file_paths = "/tmp/__dummy__.log"
end
user_cfg = '<source>
  @type tail
  path "FILE_PATHS"
  exclude_path [EXCLUDE_PATHS]
  path_key tailed_path
  tag node.logs.*
  read_from_head true
  <parse>
    @type none
  </parse>
</source>'

user_cfg.sub!('FILE_PATHS', file_paths)
user_cfg.sub!('EXCLUDE_PATHS', exclude_paths)

open('/etc/td-agent/conf.d/user.conf', 'w') { |f|
  f.puts user_cfg
}
