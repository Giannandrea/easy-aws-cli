require "rubygems"
require "aws-sdk"
require "terminal-table"
require 'progress_bar'
require 'trollop'
require 'resolv'
require "ipaddress"
require "amazon-pricing"
require "check_poller.rb"

@region = nil
@pricing = nil
@ebs_price = nil
regions = {"US" => "ec2.us-east-1.amazonaws.com", "EU" => "ec2.eu-west-1.amazonaws.com"}
map_methods = {:list => "instances_show", :show => "instances_show"}

AWS.config(YAML.load(File.read("../config/config.yml")))

def valid_hostname?(hostname)
  return false if hostname.length > 255 or hostname.scan('..').any?
  hostname = hostname[0 ... -1] if hostname.index('.', -1)
  return hostname.split('.').collect { |i| i.size <= 63 and not (i.rindex('-', 0) or i.index('-', -1) or i.scan(/[^a-z\d-]/i).any?)}.all?
end

def check_argument(arg)
  return "IP" if IPAddress.valid? arg
  return "HOSTNAME" if valid_hostname? arg
  return "INSTANCE" if /^i-.*/ =~ arg 
end

def find_region_from_avz(i_avz)
  avzones = AWS::EC2.new(:ec2_endpoint => @region).availability_zones
  region = nil
  avzones.each { |avz|
    region = avz.region.name
    break if region
  }
  return region
end

def init_price(availability_zone)
  puts "inizializzo"
  @pricing = AwsPricing::PriceList.new
  @region = find_region_from_avz(availability_zone)
  @ebs_price = @pricing.get_region(@region).ebs_price
  return true
end

def calculate_instance_price(region, instance_type, attachments)
  instance_price = @pricing.get_instance_type(region, :on_demand, instance_type, :medium).linux_price_per_hour*24*30.4
  all_ebs_price = 0
  attachments.each { |ebs_k, ebs_v|
    if ebs_v.volume.iops.to_i > 0
      all_ebs_price += @ebs_price.preferred_per_iops * ebs_v.volume.iops 
      all_ebs_price += ebs_v.volume.size * @ebs_price.preferred_per_gb
    else
      all_ebs_price += ebs_v.volume.size * @ebs_price.standard_per_gb
    end
  }
  ret_value = [instance_price, all_ebs_price]
  return ret_value
end


def instances_show(region, price)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  rows = []
  ec2s = ec2.instances
  puts "Starting collecting information about AWS instances"
  bar = ProgressBar.new(ec2s.count)
  puts ""
  initizialized = false
  ec2s.each {|itm|
      (initizialized = init_price itm.availability_zone) if !initizialized and price
      if price
      unless (itm.status.to_s.eql? "stopped")
        values = calculate_instance_price(@region, itm.instance_type, itm.attachments)
      else
        values = ["", ""]
      end
      rows << [itm.tags["Name"], itm.id, itm.status, itm.public_dns_name, itm.elastic_ip, values[0], values[1], (values[0].to_i + values[1].to_i).to_s]
    else
      rows << [itm.tags["Name"], itm.id, itm.status, itm.public_dns_name, itm.elastic_ip]
    end
    bar.increment!
  }
  if price 
    (table = Terminal::Table.new :headings => ['TAG', 'ID', 'STATUS', 'IP ADDRESS', 'EIP', 'EC2 PRICE', 'EBS PRICE', 'TOTAL PRICE'], :rows => rows)
  else 
    (table = Terminal::Table.new :headings => ['TAG', 'ID', 'STATUS', 'IP ADDRESS', 'EIP'], :rows => rows)
  end
  puts table
end

def instance_show(region, id)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  rows = []
  puts "Starting collecting information about AWS instance"
  item = ec2.instances[id]
  rows << [item.tags["Name"], item.id, item.status, item.public_dns_name, item.elastic_ip]
  table = Terminal::Table.new :headings => ['TAG', 'ID', 'STATUS', 'IP ADDRESS', 'EIP'], :rows => rows
  puts table
end

def take_instance_infos(id, region)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  i = ec2.instances[id]
  puts "id: #{id} doesn't exist, please use a valid id" and exit unless i.exists?
  puts "Windows platform is not supported" and exit if i.platform == "windows"
  type = i.instance_type
  monitoring = i.monitoring
  s_group = i.security_groups
  name = i.tags[:Name]
  elastic_ip = i.ip_address if i.has_elastic_ip?
  az = i.availability_zone
  return_values = {:name => name, :type => type, :monitoring => monitoring, :elastic_ip => elastic_ip, :az => az, :security_groups => s_group}
  return return_values
end

def create_image(region, id)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  i = ec2.instances[id]
  time = Time.new
  img_name = "name-#{time.year}-#{time.month}-#{time.day}-#{time.hour}-#{time.min}"
  puts img_name
  test2 = i.create_image(img_name, {:description => img_name, :no_reboot => true})
  test = TestHelper.new
  test.wait_for_image(ec2, test2.image_id)
  return test2.image_id
end  

def launch_image(region, name, type, monitoring, az, img_id, s_group)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  config = {:count => 1, :monitoring_enabled => true, :availability_zone => az, :image_id => img_id, :instance_type => type, :user_data => "test3"}
  config[:security_groups] = s_group
  img = ec2.images[img_id]
  inst = img.run_instance(config)
  ec2.tags.create(inst, 'Name')
  inst.tags[:Name] = "#{name}_clone"
  return inst
end

def clone_instance(id, region)
  puts "collecting aws smaple instance information \n"
  return_values = take_instance_infos(id, region)
  puts "Informations about sample instance collected \n"
  puts "Creating new image"
  img_id = create_image(region, id)
  puts "Image ready "
  instance = launch_image(region, return_values[:name], return_values[:type], return_values[:monitoring], return_values[:az], img_id, return_values[:security_groups])
  puts "Image launched"
  puts "ID : #{instance.id}"
end 

def switch_address(region, address, i_id)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  address = Resolv.new.getaddress address unless IPAddress.valid? address
  ip = ec2.elastic_ips[address]
  ip.associate :instance => i_id
end

def release_address(region, id)
  ec2=AWS::EC2.new(:ec2_endpoint => region)
  case check_argument id
  when "IP" then ec2.elastic_ips[id].disassociate
  when "INSTANCE" then ec2.instances[id].disassociate_elastic_ip
  when "HOSTNAME"
    puts "hostname"
    address = Resolv.new.getaddress id
    ec2.elastic_ips[address].disassociate
  else 
    puts "Invalid ec2 if, or ip or hostname" and exit
  end
end

opts = Trollop::options do
  version "yea2clit 0.2 beta (c) 2013 Mauro Giannandrea"
  banner "AWS command line tool"; 

  opt :assign_ip_to, "move leastic ip to another instance id [eip required]", :type => :string
  opt :release_ip_from, "Release Elastic ip from instance, you can give public ip or instance id or ec2 hostname as argument", :type => :string
  opt :clone, "Make a aws instance clone", :type => :string
  opt :region, "Select the region EU or US [default:US]", :type => :string, :required => :true
  opt :list, "List all instannces in region", :default => false
  opt :show, "Show single aws instance information", :type => :string
  opt :eip, "The aws instance id", :type => :string
  opt :price, "add price to list option", :default => false
end

Trollop::die :region, "Invalid region, this filed is required" unless opts[:region] == "EU" or opts[:region] == "US"
Trollop::die :clone, "please insert a valid instance id" unless (/i-.*/ =~ opts[:clone] or opts[:clone].nil?)
Trollop::die :show, "please insert a valid instance id"  unless (/i-.*/ =~ opts[:show] or opts[:show].nil?)
Trollop::die :assign_ip_to, "please insert a valid instance id" unless (/i-.*/ =~ opts[:assign_ip_to] or opts[:assign_ip_to].nil?)
#Trollop::die :release_ip_from, "please insert a valid instance id" unless (/i-.*/ =~ opts[:release_ip_from] or opts[:release_ip_from].nil?)
Trollop::die "You must specify a --eip option and a valid elastic IP with 'assign_ip_to' command" unless (opts[:assign_ip_to]) or !opts[:eip]
Trollop::die "Only one command is possable" unless (opts[:list] ^ opts[:clone] ^ opts[:show] ^ opts[:assign_ip_to] ^ opts[:release_ip_from])

warn_level = $VERBOSE
$VERBOSE = nil

instances_show(regions[opts[:region]], opts[:price]) if opts[:list]
instance_show(regions[opts[:region]], opts[:show]) if opts[:show]
clone_instance(opts[:clone], regions[opts[:region]]) if opts[:clone] 
switch_address(regions[opts[:region]], opts[:eip], opts[:assign_ip_to]) if opts[:assign_ip_to]
release_address(regions[opts[:region]], opts[:release_ip_from]) if opts[:release_ip_from]
