# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hyperstack is a Ruby-based DSL and modern web toolkit for building interactive web applications. It compiles Ruby code to JavaScript using Opal and provides React/ReactRouter wrappers. The project consists of multiple gems organized in a modular architecture.

## Core Architecture

The codebase is organized as a multi-gem Ruby project with the following key components:

- **hyper-component**: React component wrapper and DSL for Ruby
- **hyper-model**: Isomorphic ActiveRecord models with bi-directional data sync
- **hyper-operation**: Server operations and transport layer
- **hyper-router**: React Router wrapper for Ruby
- **hyper-state**: Observable state management system
- **hyper-store**: Flux-like data stores (legacy)
- **hyper-spec**: Testing framework integration
- **hyper-i18n**: Internationalization support
- **hyperstack-config**: Configuration and autoloader system
- **rails-hyperstack**: Rails integration and generators

Each gem is located in `ruby/<gem-name>/` with its own gemspec, Rakefile, and spec directory.

## Development Commands

### Testing
- `rake spec` - Run specs for individual gems (from gem directory)
- `./runtests` - Run tests for specific component with environment setup
- `./runone` - Run tests for single component (hyper-component by default)
- `./runall` - Run complete test suite with database setup

### Test Environment Variables
- `COMPONENT=<gem-name>` - Specify which gem to test
- `RUBY_VERSION=<version>` - Ruby version for testing
- `TASK=<task>` - Specific task (e.g., part1, part2, part3 for hyper-model)
- `DB=<database>` - Database name for model tests

### Building and Publishing
- `rake publish` - Build and publish all gems to private repository
- `gem build <gem-name>.gemspec` - Build individual gem (from gem directory)

## Key File Structure

- `ruby/version.rb` - Central version management
- `HYPERSTACK_VERSION` - Version file read by version.rb
- `Rakefile` - Main build and publish tasks
- `ruby/<gem>/lib/<gem>.rb` - Main entry point for each gem
- `ruby/<gem>/spec/` - Test suites organized by functionality

## Testing Strategy

- **hyper-model**: Tests split into 7 batches (batch1-batch7) for performance
- **Component-based**: Each gem has isolated test environment with test_app
- **Browser Testing**: Uses Selenium WebDriver with Chrome for integration tests
- **Database Testing**: PostgreSQL and MySQL support with test database setup

## Development Notes

- Ruby code compiles to JavaScript via Opal
- Client/server isomorphic architecture - same Ruby code runs on both sides
- React integration through native JavaScript library wrapping
- Hot reloading support via Webpacker integration
- Component tests use browser automation for full stack validation

## Ruby 3.2.9 Compatibility Issues

When using Ruby 3.2.9 with Rails 6.1.7.10, there are Logger constant loading issues that cause Rails::Application instantiation errors. These manifest as:
- `Rails::Application is abstract, you cannot instantiate it directly` errors
- `uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger` errors

**Solution**: Use `DISABLE_SPRING=1` prefix for Rails commands to bypass Spring's application preloading:
- `DISABLE_SPRING=1 bundle exec rails generate hyperstack:install`
- `DISABLE_SPRING=1 bundle exec rake spec`
- `DISABLE_SPRING=1 bundle exec rails generate model ModelName`

This prevents Spring from trying to preload multiple Rails applications simultaneously, which causes the Logger constant conflicts.

## Common Patterns

- Components inherit from `HyperComponent`
- Models use `ReactiveRecord` for isomorphic behavior
- Operations use Railway pattern for server-side logic
- State management through observable patterns
- Event handling through React synthetic events

## Local Development and Testing

- set OPAL_VERSION=1.8.3 before running specs
- run specs locally in sqlite
- run specs with rspec and spring disabled
- the server and the browser MUST share a timezone, or the `column_type` datetime
  specs fail by the offset (server-computed time vs. browser-rendered time). When
  the browser runs in a Docker container (e.g. `selenium/standalone-chrome`), give
  it the host's `-e TZ=...` or pin both to UTC. See `run-local-docker-specs.sh` and
  the "Running the tests locally" section in `readme.md`.
