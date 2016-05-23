#
# Cookbook Name:: zabbix_lwrp
# Provider:: database
#
# Author:: LLC Express 42 (cookbooks@express42.com)
#
# Copyright (C) 2015 LLC Express 42
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

use_inline_resources

provides :zabbix_database if defined? provides

require 'English'
require 'digest/md5'

def change_admin_password(db_connect_string)
  admin_user_pass = 'zabbix'
  # Get Admin password from data bag
  begin
    admin_user_pass = data_bag_item(node['zabbix']['server']['credentials']['databag'], 'admin')['pass']
  rescue
    log('Using default password for user Admin ... (pass: zabbix)')
  end
  admin_user_pass_md5 = Digest::MD5.hexdigest(admin_user_pass)
  getdb_admin_user_pass_query = IO.popen("#{db_connect_string} -c \"select passwd from users where alias='Admin'\"")
  getdb_admin_user_pass = getdb_admin_user_pass_query.readlines[0].to_s.gsub(/\s+/, '')
  getdb_admin_user_pass_query.close
  if getdb_admin_user_pass != admin_user_pass_md5
    set_admin_pass_query = IO.popen("#{db_connect_string} -c \"update users set passwd='#{admin_user_pass_md5}' where alias = 'Admin';\"")
    set_admin_pass_query_res = set_admin_pass_query.readlines
    set_admin_pass_query.close
  end
  log('Password for web user Admin has been successfully updated.') if set_admin_pass_query_res
end

def check_zabbix_db(db_connect_string)
  check_db_flag = false
  # Check connect to database
  log("Connect to postgres with connection string #{db_connect_string}")
  psql_output = IO.popen("#{db_connect_string} -c 'SELECT 1'")
  psql_output_res = psql_output.readlines
  psql_output.close

  if $CHILD_STATUS.exitstatus != 0 || psql_output_res[0].to_i != 1
    log("Couldn't connect to database, please check database server configuration")
    check_db_flag = false
  else
    # Check if database exist
    check_db_exist = IO.popen("#{db_connect_string} -c \"select count(*) from users where alias='Admin'\"")
    check_db_exist_res = check_db_exist.readlines
    check_db_exist.close
    check_db_flag = !($CHILD_STATUS.exitstatus == 0 && check_db_exist_res[0].to_i == 1)
  end
  check_db_flag
end

action :create do
  db_name = new_resource.db_name
  db_user = new_resource.db_user
  db_pass = new_resource.db_pass
  db_host = new_resource.db_host
  db_port = new_resource.db_port

  db_connect_string = "PGPASSWORD=#{db_pass} psql -q -t -h #{db_host} -p #{db_port} -U #{db_user} -d #{db_name}"

  if Gem::Version.new(node['zabbix']['version']) >= Gem::Version.new("3.0")
    execute 'Provisioning zabbix database' do
      command "zcat /usr/share/doc/zabbix-server-pgsql/create.sql.gz | #{db_connect_string}"
      only_if { check_zabbix_db(db_connect_string) }
      action :run
    end
  else
    execute 'Provisioning zabbix database' do
      command "#{db_connect_string} -f /usr/share/zabbix-server-pgsql/schema.sql; \
               #{db_connect_string} -f /usr/share/zabbix-server-pgsql/images.sql; \
               #{db_connect_string} -f /usr/share/zabbix-server-pgsql/data.sql;"
      only_if { check_zabbix_db(db_connect_string) }
      action :run
    end
  end

  ruby_block 'Set password for web user Admin' do
    block do
      change_admin_password(db_connect_string)
    end
  end

  new_resource.updated_by_last_action(true)
end
