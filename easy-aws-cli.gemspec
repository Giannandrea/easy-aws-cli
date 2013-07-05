# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{easy-aws-cli}
  s.version = "0.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Mauro Giannandrea"]
  s.date = %q{2013-07-03}
  s.description = %q{      easy-aws-cli is a ruby library baed on aws sdk 
      designed to semplify some action with aws cloud.
}
  s.email = %q{mauro.giannandrea@gmail.com}
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    "CHANGELOG.rdoc",
    "LICENSE",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "ipaddress.gemspec",
    "lib/ipaddress.rb",
    "lib/ipaddress/ipv4.rb",
    "lib/ipaddress/ipv6.rb",
    "lib/ipaddress/prefix.rb",
    "test/ipaddress/ipv4_test.rb",
    "test/ipaddress/ipv6_test.rb",
    "test/ipaddress/prefix_test.rb",
    "test/ipaddress_test.rb",
    "test/test_helper.rb"
  ]
  s.homepage = %q{http://github.com/bluemonk/ipaddress}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.6.2}
  s.summary = %q{IPv4/IPv6 addresses manipulation library}

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end

