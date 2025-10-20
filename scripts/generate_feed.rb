#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rexml/document'
require 'time'

# Parse CHANGELOG.md and extract the latest release information
class ChangelogParser
  def initialize(changelog_path)
    @changelog_path = changelog_path
    @content = File.read(changelog_path, encoding: 'utf-8')
    @lines = @content.split("\n")
  end

  def parse_latest_release
    release_info = {
      date: '',
      version: '',
      modules: []
    }

    in_release = false
    current_module = nil

    @lines.each do |line|
      # Find first release section
      if line.start_with?('# Releases - ')
        if !in_release
          in_release = true
          # Extract date: "# Releases - 2025.09.25"
          release_info[:date] = line.split(' - ')[1]&.strip || ''
          next
        else
          # Found next release, stop parsing
          break
        end
      end

      next unless in_release

      # Extract version
      if line.start_with?('## Version ')
        release_info[:version] = line.sub('## Version ', '').strip
        next
      end

      # Extract module
      if line.start_with?('### ')
        # Save previous module if exists
        release_info[:modules] << current_module if current_module

        # Start new module
        module_line = line.sub('### ', '').strip
        parts = module_line.split(' ', 2)
        current_module = {
          name: parts[0],
          version: parts[1] || '',
          content: []
        }
        next
      end

      # Collect module content (skip empty lines and other headers)
      if current_module && !line.empty? && !line.start_with?('#')
        current_module[:content] << line
      end
    end

    # Add last module
    release_info[:modules] << current_module if current_module

    release_info
  end
end

# Generate Atom feed XML from release information
class AtomFeedGenerator
  def initialize(release_info, feed_url, link_url)
    @release_info = release_info
    @feed_url = feed_url
    @link_url = link_url
    @updated_time = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  end

  def generate
    doc = REXML::Document.new
    doc << REXML::XMLDecl.new('1.0', 'UTF-8')

    # Create feed element
    feed = doc.add_element('feed', 'xmlns' => 'http://www.w3.org/2005/Atom')

    # Feed metadata
    feed.add_element('title').text = 'iOS SDK Release Notes'
    feed.add_element('link', 'href' => @link_url, 'rel' => 'alternate')
    feed.add_element('link', 'href' => @feed_url, 'rel' => 'self')
    feed.add_element('id').text = @feed_url
    feed.add_element('updated').text = @updated_time

    # Add entries for each module
    @release_info[:modules].each do |mod|
      add_entry(feed, mod)
    end

    # Format XML with indentation
    formatter = REXML::Formatters::Pretty.new(2)
    formatter.compact = true
    output = String.new
    formatter.write(doc, output)
    output
  end

  private

  def add_entry(feed, mod)
    entry = feed.add_element('entry')

    # Entry metadata
    title = "#{mod[:name]} #{mod[:version]}"
    entry.add_element('title').text = title
    entry.add_element('link', 'href' => @link_url)

    entry_id = "urn:release:#{@release_info[:version]}:#{mod[:name]}:#{mod[:version]}"
    entry.add_element('id').text = entry_id
    entry.add_element('updated').text = @updated_time

    # Author
    author = entry.add_element('author')
    author.add_element('name').text = 'KARTE'

    # Content
    content_html = "<h3>#{escape_html(title)}</h3>\n"
    content_html += escape_html(mod[:content].join("\n"))
    entry.add_element('content', 'type' => 'html').text = content_html

    # Summary
    summary = "#{title} - Released on #{@release_info[:date]}"
    entry.add_element('summary').text = summary
  end

  def escape_html(text)
    text.gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
        .gsub('"', '&quot;')
        .gsub("'", '&apos;')
  end
end

# Main execution
def main
  if ARGV.length != 3
    warn 'Usage: generate_feed.rb <changelog_path> <feed_url> <link_url>'
    exit 1
  end

  changelog_path = ARGV[0]
  feed_url = ARGV[1]
  link_url = ARGV[2]

  unless File.exist?(changelog_path)
    warn "Error: CHANGELOG file not found: #{changelog_path}"
    exit 1
  end

  # Parse CHANGELOG
  parser = ChangelogParser.new(changelog_path)
  release_info = parser.parse_latest_release

  if release_info[:modules].empty?
    warn 'Warning: No modules found in the latest release'
    exit 0
  end

  # Generate feed
  generator = AtomFeedGenerator.new(release_info, feed_url, link_url)
  feed_xml = generator.generate

  # Output to stdout
  puts feed_xml
end

main if __FILE__ == $PROGRAM_NAME
