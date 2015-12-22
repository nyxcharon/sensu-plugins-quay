#! /usr/bin/env ruby
#
#   check-vul-notification
#
# DESCRIPTION:
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: json
#   gem: uri
#
# USAGE: -a account -p api_key
#
# NOTES:
#
# LICENSE:
#   Barry Martin <nyxcharon@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'json'
require 'uri'
require 'net/http'

API_URL="https://quay.io/api/v1"
REPO_URL="#{API_URL}/repository"

#
# Check for repos without security notifications
#
class CheckVulNotification < Sensu::Plugin::Check::CLI
  option :account,
         description: 'The namespace of the account to check',
         short: '-a ACCOUNT',
         long: '--account ACCOUNT',
         required: true

  option :exclude,
         description: 'Comma delimited list of repos to ignore',
         short: '-e REPO1,REPO2...',
         long: '--exclude REPO1,REPO2'

  option :password,
          description: 'The api key to use',
          short: '-p  api_key',
          long: '--password api_key',
          required: true

  def run
    #Argument setup/parsing/checking
    cli = CheckVulNotification.new
    cli.parse_options
    account = cli.config[:account]
    exclude = cli.config[:exclude]
    password = cli.config[:password]

    if exclude and exclude.include?(',')
      exclude_list = exclude.split(',')
    elsif exclude
        exclude_list = [ exclude ]
    else
      exclude_list = ['']
    end

    #Get the list of all the images
    response=fetch_page("#{REPO_URL}?public=false&namespace=#{account}",account,password)
    data=JSON.parse(response)
    images = [ ]
    data['repositories'].each do |repo|
      if not exclude_list.include?(repo['name'])
        images += [ repo['name'] ]
      end
    end

    #For every image check for notifications
    missing = [ ]
    images.each do |image|
      response = fetch_page("#{REPO_URL}/#{account}/#{image}/notification/",account,password)
      data=JSON.parse(response)
      if data['notifications'].empty?
       missing += [ image ]
     else #iterate over the list of notifications
        found = false
        data['notifications'].each do |note|
          if note['event'] == 'vulnerability_found'
            found = true
          end
        end
        if not found
          missing += [ image ]
        end
      end
    end

    #Report results
    if missing.empty?
      ok "No images missing notifications"
    else
      critical "Found images missing notifications #{missing}"
    end
  end


  def fetch_page(request_url,account,password)
    #puts request_url
    uri = URI(request_url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)
    request.add_field 'Authorization', "Bearer #{password}"
    http.use_ssl = true

    response = http.request(request)
    if response.code.include?('429') #HTTP 429 too many requests
      warning 'Bitbucket rate limit has been exceeded'
    elsif response.code.include?('400') #HTTP 400 Bad request
      unknown 'Bad Request'
    elsif response.code.include?('401') #HTTP 401 Unathorized
      warning 'Unauthorized - Check your credentials'
    end

    return response.body
  end

end
