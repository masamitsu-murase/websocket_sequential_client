# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'websocket_sequential_client/version'

Gem::Specification.new do |spec|
  spec.name          = "websocket_sequential_client"
  spec.version       = WebsocketSequentialClient::VERSION
  spec.authors       = ["Masamitsu MURASE"]
  spec.email         = ["masamitsu.murase@gmail.com"]

  spec.summary       = %q{A simple WebSocket client to access a server in a sequential way}
  spec.description   = %q{This gem library allows you to access a WebSocket server in a sequential way instead of an event-driven way.}
  spec.homepage      = "https://github.com/masamitsu-murase/websocket_sequential_client"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "websocket"

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.2"
  spec.add_development_dependency "em-websocket"
end
